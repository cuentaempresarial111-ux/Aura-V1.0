import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

class AuraCryptoException implements Exception {
  const AuraCryptoException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'AuraCryptoException: $message';
}

abstract class AuraCryptoLayer {
  static const int _ivLength = 16;
  static const int _aesBlockLength = 16;
  static const String _derivationSalt = 'Aura Mobile Defens model key v1';
  static const String _derivationInfo = 'aura-model-aes-256-cbc-pkcs7';

  static String encryptModel(
    String plaintext,
    String secureKey, {
    IV? iv,
  }) {
    try {
      if (secureKey.isEmpty) {
        throw const AuraCryptoException('La clave segura está vacía.');
      }
      if (jsonDecode(plaintext) is! Map) {
        throw const AuraCryptoException(
          'El plaintext no es un objeto JSON de modelo.',
        );
      }

      final initializationVector = iv ?? IV.fromSecureRandom(_ivLength);
      if (initializationVector.bytes.length != _ivLength) {
        throw const AuraCryptoException('El vector IV AES debe tener 16 bytes.');
      }
      final ciphertext = Encrypter(
        AES(Key(_deriveKey(secureKey)), mode: AESMode.cbc, padding: 'PKCS7'),
      ).encrypt(plaintext, iv: initializationVector);
      return <int>[
        ...initializationVector.bytes,
        ...ciphertext.bytes,
      ].map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    } on AuraCryptoException {
      rethrow;
    } on Object catch (error) {
      throw AuraCryptoException('No se pudo cifrar el modelo.', error);
    }
  }

  static String decryptModel(String encryptedHex, String secureKey) {
    try {
      if (secureKey.isEmpty) {
        throw const AuraCryptoException('La clave segura está vacía.');
      }
      if (encryptedHex.isEmpty ||
          encryptedHex.length.isOdd ||
          !RegExp(r'^[0-9a-fA-F]+$').hasMatch(encryptedHex)) {
        throw const AuraCryptoException('El payload hexadecimal no es válido.');
      }

      final payload = Uint8List.fromList(
        List<int>.generate(
          encryptedHex.length ~/ 2,
          (index) => int.parse(
            encryptedHex.substring(index * 2, index * 2 + 2),
            radix: 16,
          ),
          growable: false,
        ),
      );
      final ciphertextLength = payload.length - _ivLength;
      if (ciphertextLength < _aesBlockLength ||
          ciphertextLength % _aesBlockLength != 0) {
        throw const AuraCryptoException('La longitud del ciphertext AES no es válida.');
      }

      final iv = IV(Uint8List.sublistView(payload, 0, _ivLength));
      final ciphertext = Encrypted(
        Uint8List.sublistView(payload, _ivLength),
      );
      final key = Key(_deriveKey(secureKey));
      final plaintext = Encrypter(
        AES(key, mode: AESMode.cbc, padding: 'PKCS7'),
      ).decrypt(ciphertext, iv: iv);
      if (jsonDecode(plaintext) is! Map) {
        throw const AuraCryptoException(
          'El plaintext descifrado no es un objeto JSON de modelo.',
        );
      }
      return plaintext;
    } on AuraCryptoException {
      rethrow;
    } on Object catch (error) {
      throw AuraCryptoException('No se pudo descifrar el modelo.', error);
    }
  }

  static Uint8List _deriveKey(String secureKey) {
    final inputKeyMaterial = utf8.encode(secureKey);
    final salt = utf8.encode(_derivationSalt);
    final info = utf8.encode(_derivationInfo);
    final pseudoRandomKey = Hmac(sha256, salt).convert(inputKeyMaterial).bytes;
    final derivedKey = Hmac(sha256, pseudoRandomKey).convert(<int>[...info, 1]).bytes;
    return Uint8List.fromList(derivedKey);
  }
}
