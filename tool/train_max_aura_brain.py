import argparse
import csv
import hashlib
import hmac
import json
import math
import os
import re
import tempfile
from pathlib import Path
from urllib.parse import urlsplit

import numpy as np
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from sklearn.ensemble import RandomForestClassifier
from sklearn.tree import _tree

ROOT = Path(__file__).resolve().parents[1]
FEATURE_ORDER = [
    "length",
    "shannon_entropy",
    "digit_ratio",
    "vowel_ratio",
    "consonant_sequence_ratio",
    "suspicious_tld",
]
SUSPICIOUS_TLDS = {
    "cam", "click", "country", "date", "download", "fit", "gq", "loan",
    "mov", "party", "review", "rest", "stream", "support", "tk", "top",
    "wang", "work", "xyz", "zip",
}
DOMAIN_COLUMNS = {"domain", "host", "hostname", "url", "fqdn", "requested_domain"}
LABEL_COLUMNS = {"label", "class", "target", "is_malicious", "malicious", "threat"}
SKIP_DIRS = {".git", ".dart_tool", ".gradle", ".venv", "build", "__pycache__", "venv"}
SEED_DATASET = [
    ("google.com", 0), ("github.com", 0), ("whatsapp.com", 0),
    ("amazon.com", 0), ("bancodevenezuela.com", 0), ("codemagic.io", 0),
    ("flutter.dev", 0), ("wikipedia.org", 0), ("microsoft.com", 0),
    ("netflix.com", 0), ("binance.com", 0), ("youtube.com", 0),
    ("stackoverflow.com", 0), ("apple.com", 0), ("linkedin.com", 0),
    ("zoom.us", 0), ("cloudflare.com", 0), ("android.com", 0),
    ("x7z9q1wplmnb.xyz", 1), ("aqwzsxedcrfv12.top", 1),
    ("free-crypto-rewards.click", 1), ("update-system-android.live", 1),
    ("cxj9812kmzsloq.cc", 1), ("malicious-payload-server.info", 1),
    ("shw28190axmzq.xyz", 1), ("get-root-bypass.top", 1),
    ("91kazmslqo1029az.biz", 1), ("free-cleaner-android.gq", 1),
    ("p0wz9172mlxozq.tk", 1), ("get-unlocked-premium.fit", 1),
]


def normalize_domain(value):
    candidate = value.strip().lower()
    if not candidate:
        return ""
    if "://" in candidate:
        candidate = urlsplit(candidate).hostname or ""
    else:
        candidate = candidate.split("/", 1)[0].split(":", 1)[0]
    return candidate.rstrip(".")


def calculate_shannon_entropy(domain_string):
    if not domain_string:
        return 0.0
    frequencies = {}
    for character in domain_string.lower():
        frequencies[character] = frequencies.get(character, 0) + 1
    length = len(domain_string)
    return -sum(
        (count / length) * math.log2(count / length)
        for count in frequencies.values()
    )


def extract_maximum_features(domain):
    host = normalize_domain(domain)
    length = len(host)
    if length == 0:
        return [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

    letters = [character for character in host if character.isascii() and character.isalpha()]
    digits = sum(character.isascii() and character.isdigit() for character in host)
    vowels = sum(character in "aeiou" for character in letters)
    letter_count = len(letters)
    run_length = 0
    consonant_sequence_characters = 0
    for character in host:
        if character.isascii() and character.isalpha() and character not in "aeiou":
            run_length += 1
        else:
            if run_length >= 3:
                consonant_sequence_characters += run_length
            run_length = 0
    if run_length >= 3:
        consonant_sequence_characters += run_length

    tld = host.rsplit(".", 1)[-1]
    return [
        float(length),
        calculate_shannon_entropy(host),
        digits / length,
        vowels / letter_count if letter_count else 0.0,
        consonant_sequence_characters / letter_count if letter_count else 0.0,
        float(tld in SUSPICIOUS_TLDS),
    ]


def parse_label(value):
    normalized = value.strip().lower()
    if normalized in {"1", "true", "malicious", "malware", "threat", "dga", "bad"}:
        return 1
    if normalized in {"0", "false", "benign", "safe", "legitimate", "good"}:
        return 0
    return None


def discover_csv_files(dataset_root):
    dataset_root = Path(dataset_root)
    if not dataset_root.exists():
        return []
    csv_files = []
    for current_root, directory_names, file_names in os.walk(dataset_root):
        directory_names[:] = sorted(name for name in directory_names if name not in SKIP_DIRS)
        for file_name in file_names:
            if file_name.lower().endswith(".csv"):
                csv_files.append(Path(current_root) / file_name)
    return sorted(csv_files)


def read_csv_samples(csv_files, max_rows):
    samples = []
    for csv_path in csv_files:
        with csv_path.open("r", encoding="utf-8-sig", newline="", errors="replace") as stream:
            reader = csv.DictReader(stream)
            if not reader.fieldnames:
                continue
            columns = {name.strip().lower(): name for name in reader.fieldnames if name}
            domain_column = next((columns[name] for name in DOMAIN_COLUMNS if name in columns), None)
            label_column = next((columns[name] for name in LABEL_COLUMNS if name in columns), None)
            if domain_column is None or label_column is None:
                continue
            for row in reader:
                domain = normalize_domain(row.get(domain_column) or "")
                label = parse_label(row.get(label_column) or "")
                if domain and "." in domain and label is not None:
                    samples.append((domain, label))
                    if max_rows and len(samples) >= max_rows:
                        return samples
    return samples


def read_dart_string_constant(source_path, name):
    source = source_path.read_text(encoding="utf-8")
    match = re.search(
        rf"static\s+const\s+String\s+{re.escape(name)}\s*=\s*'([^']*)'",
        source,
    )
    if match is None:
        raise RuntimeError(f"No se encontró la constante {name} en {source_path}.")
    return match.group(1)


def derive_model_key(master_key):
    crypto_source = ROOT / "lib/agent/aura_crypto_layer.dart"
    salt = read_dart_string_constant(crypto_source, "_derivationSalt").encode("utf-8")
    info = read_dart_string_constant(crypto_source, "_derivationInfo").encode("utf-8")
    pseudo_random_key = hmac.new(salt, master_key.encode("utf-8"), hashlib.sha256).digest()
    return hmac.new(pseudo_random_key, info + b"\x01", hashlib.sha256).digest()


def encrypt_model(plaintext):
    vault_source = ROOT / "lib/secure_vault.dart"
    master_key = read_dart_string_constant(vault_source, "defaultModelMasterKey")
    key = derive_model_key(master_key)
    iv = os.urandom(16)
    padder = padding.PKCS7(algorithms.AES.block_size).padder()
    padded_plaintext = padder.update(plaintext) + padder.finalize()
    encryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).encryptor()
    ciphertext = encryptor.update(padded_plaintext) + encryptor.finalize()
    return (iv + ciphertext).hex()


def serialize_tree(estimator):
    tree = estimator.tree_

    def serialize_node(node_index):
        if tree.feature[node_index] == _tree.TREE_UNDEFINED:
            class_index = int(np.argmax(tree.value[node_index][0]))
            return {"type": "leaf", "value": int(estimator.classes_[class_index])}
        return {
            "type": "split",
            "feature_index": int(tree.feature[node_index]),
            "threshold": float(tree.threshold[node_index]),
            "left": serialize_node(tree.children_left[node_index]),
            "right": serialize_node(tree.children_right[node_index]),
        }

    return {"root": serialize_node(0)}


def atomic_write(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, delete=False
    ) as temporary:
        temporary.write(content)
        temporary.flush()
        os.fsync(temporary.fileno())
        temporary_path = Path(temporary.name)
    os.replace(temporary_path, path)


def main():
    parser = argparse.ArgumentParser(description="Entrena y cifra el bosque local de Aura.")
    parser.add_argument(
        "--dataset-root",
        type=Path,
        default=Path(os.environ.get("AURA_DATASET_DIR", ROOT / "data")),
        help="Directorio recursivo de CSV con columnas de dominio y etiqueta.",
    )
    parser.add_argument(
        "--max-csv-rows",
        type=int,
        default=0,
        help="Límite opcional de filas CSV; 0 procesa todas las filas compatibles.",
    )
    args = parser.parse_args()
    if args.max_csv_rows < 0:
        parser.error("--max-csv-rows debe ser 0 o mayor.")

    csv_files = discover_csv_files(args.dataset_root)
    csv_samples = read_csv_samples(csv_files, args.max_csv_rows)
    samples = SEED_DATASET + csv_samples
    if len({label for _, label in samples}) != 2:
        raise RuntimeError("El conjunto debe contener dominios benignos y maliciosos.")

    features = np.asarray([extract_maximum_features(domain) for domain, _ in samples])
    labels = np.asarray([label for _, label in samples], dtype=np.int64)
    print(
        f"Entrenando bosque local: 500 árboles, profundidad máxima 12, "
        f"{len(csv_samples)} filas CSV y {len(SEED_DATASET)} muestras base."
    )
    forest = RandomForestClassifier(
        n_estimators=500,
        max_depth=12,
        n_jobs=-1,
        random_state=42,
        class_weight="balanced_subsample",
    )
    forest.fit(features, labels)

    model = {
        "model_name": "Aura Lexical Threat Forest",
        "model_version": "3.0.0",
        "model_type": "random_forest",
        "training_status": "heuristic_seed_with_csv" if csv_samples else "heuristic_seed",
        "training_samples": len(samples),
        "csv_files": [str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path) for path in csv_files],
        "training_config": {
            "n_estimators": 500,
            "max_depth": 12,
            "n_jobs": -1,
            "random_state": 42,
        },
        "feature_order": FEATURE_ORDER,
        "classes": {"0": "safe", "1": "threat"},
        "trees": [serialize_tree(estimator) for estimator in forest.estimators_],
    }
    if len(model["trees"]) != 500:
        raise RuntimeError("El bosque serializado no contiene exactamente 500 árboles.")

    json_bytes = (json.dumps(model, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    encrypted_hex = encrypt_model(json_bytes)
    atomic_write(ROOT / "assets/model/aura_brain_model.json", json_bytes.decode("utf-8"))
    atomic_write(ROOT / "assets/model/aura_brain_model.enc", encrypted_hex + "\n")
    print("Modelo JSON y artefacto AES-CBC generados; se serializaron 500 árboles.")


if __name__ == "__main__":
    main()
