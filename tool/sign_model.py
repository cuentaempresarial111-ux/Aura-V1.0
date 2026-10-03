#!/usr/bin/env python3
"""Generate an RSA key pair and sign the encrypted Aura model artifact."""

import argparse
import getpass
import os
import sys
import tempfile
from pathlib import Path

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MODEL = ROOT / "assets/model/aura_brain_model.enc"
DEFAULT_SIGNATURE = ROOT / "assets/model/aura_brain_model.sig"
DEFAULT_PRIVATE_KEY = ROOT / "tool/private_key.pem"
DEFAULT_PUBLIC_KEY = ROOT / "tool/public_key_string.txt"
MIN_PASSWORD_LENGTH = 12


def _atomic_write(path: Path, content: bytes, mode: int = 0o644) -> None:
    """Write a file atomically, applying restrictive permissions to the temp file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.name}.",
        suffix=".tmp",
        dir=path.parent,
    )
    temporary_path = Path(temporary_name)
    try:
        os.fchmod(descriptor, mode)
        with os.fdopen(descriptor, "wb") as temporary_file:
            temporary_file.write(content)
            temporary_file.flush()
            os.fsync(temporary_file.fileno())
        os.replace(temporary_path, path)
        os.chmod(path, mode)
    except BaseException:
        try:
            os.close(descriptor)
        except OSError:
            pass
        temporary_path.unlink(missing_ok=True)
        raise


def generate_key_pair(
    private_key_path: Path,
    public_key_path: Path,
    password: bytes,
) -> rsa.RSAPrivateKey:
    """Create encrypted PKCS#8 private PEM and SubjectPublicKeyInfo public PEM."""
    if len(password) < MIN_PASSWORD_LENGTH:
        raise ValueError(
            f"La contraseña de la clave privada debe tener al menos "
            f"{MIN_PASSWORD_LENGTH} bytes."
        )
    if private_key_path.exists() or public_key_path.exists():
        raise FileExistsError(
            "Ya existe una de las claves; no se sobrescriben para evitar "
            "invalidar firmas anteriores. Mueva ambas claves para rotarlas."
        )

    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
    )
    private_pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.BestAvailableEncryption(password),
    )
    public_pem = private_key.public_key().public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )

    _atomic_write(private_key_path, private_pem, mode=0o600)
    try:
        _atomic_write(public_key_path, public_pem)
    except BaseException:
        private_key_path.unlink(missing_ok=True)
        raise
    return private_key


def sign_model(
    model_path: Path,
    private_key_path: Path,
    public_key_path: Path,
    signature_path: Path,
    password: bytes,
) -> bytes:
    """Sign model bytes using RSA PKCS#1 v1.5 with SHA-256 and verify the pair."""
    if not model_path.is_file():
        raise FileNotFoundError(f"No se encontró el artefacto: {model_path}")
    if not private_key_path.is_file() or not public_key_path.is_file():
        raise FileNotFoundError(
            "Faltan las claves RSA. Genérelas antes de firmar."
        )

    private_key = serialization.load_pem_private_key(
        private_key_path.read_bytes(),
        password=password,
    )
    public_key = serialization.load_pem_public_key(public_key_path.read_bytes())
    if not isinstance(private_key, rsa.RSAPrivateKey):
        raise TypeError("La clave privada almacenada no es RSA.")
    if not isinstance(public_key, rsa.RSAPublicKey):
        raise TypeError("La clave pública almacenada no es RSA.")
    if private_key.public_key().public_numbers() != public_key.public_numbers():
        raise ValueError("La clave pública no corresponde a la clave privada.")
    if private_key.key_size != 2048:
        raise ValueError("Se esperaba una clave RSA de exactamente 2048 bits.")

    model_bytes = model_path.read_bytes()
    if not model_bytes:
        raise ValueError("No se firma un artefacto vacío.")

    signature = private_key.sign(
        model_bytes,
        padding.PKCS1v15(),
        hashes.SHA256(),
    )
    public_key.verify(signature, model_bytes, padding.PKCS1v15(), hashes.SHA256())
    _atomic_write(signature_path, signature)
    return signature


def verify_signature(
    model_path: Path,
    public_key_path: Path,
    signature_path: Path,
) -> bool:
    """Verify an existing RSA PKCS#1 v1.5 SHA-256 model signature."""
    public_key = serialization.load_pem_public_key(public_key_path.read_bytes())
    if not isinstance(public_key, rsa.RSAPublicKey):
        raise TypeError("La clave pública almacenada no es RSA.")
    try:
        public_key.verify(
            signature_path.read_bytes(),
            model_path.read_bytes(),
            padding.PKCS1v15(),
            hashes.SHA256(),
        )
    except InvalidSignature:
        return False
    return True


def _read_new_password() -> bytes:
    password = getpass.getpass("Contraseña nueva para la clave privada: ")
    confirmation = getpass.getpass("Repita la contraseña: ")
    if password != confirmation:
        raise ValueError("Las contraseñas no coinciden.")
    encoded_password = password.encode("utf-8")
    if len(encoded_password) < MIN_PASSWORD_LENGTH:
        raise ValueError(
            f"La contraseña debe tener al menos {MIN_PASSWORD_LENGTH} bytes."
        )
    return encoded_password


def _read_existing_password() -> bytes:
    return getpass.getpass("Contraseña de la clave privada: ").encode("utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Genera claves RSA-2048 locales y firma aura_brain_model.enc "
            "con SHA-256 y PKCS#1 v1.5."
        )
    )
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--signature", type=Path, default=DEFAULT_SIGNATURE)
    parser.add_argument("--private-key", type=Path, default=DEFAULT_PRIVATE_KEY)
    parser.add_argument("--public-key", type=Path, default=DEFAULT_PUBLIC_KEY)
    args = parser.parse_args()

    try:
        if not args.model.is_file() or args.model.stat().st_size == 0:
            raise FileNotFoundError(
                f"No existe un artefacto de modelo no vacío: {args.model}"
            )
        if args.private_key.exists() != args.public_key.exists():
            raise FileExistsError(
                "Sólo existe una clave del par. Restaure el par coincidente "
                "o mueva la clave restante antes de generar otro."
            )

        if args.private_key.exists():
            password = _read_existing_password()
        else:
            password = _read_new_password()
            generate_key_pair(args.private_key, args.public_key, password)
            print(f"Clave privada cifrada guardada en: {args.private_key}")
            print(f"Clave pública guardada en: {args.public_key}")

        signature = sign_model(
            args.model,
            args.private_key,
            args.public_key,
            args.signature,
            password,
        )
        print(
            f"Firma RSA/SHA-256 creada y verificada en {args.signature} "
            f"({len(signature)} bytes)."
        )
        return 0
    except (OSError, ValueError, TypeError, InvalidSignature) as error:
        print(f"Error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
