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
  // Replace with the PEM public key that matches the offline signing key.
  // ignore: non_constant_identifier_names
  static const String AURA_PUBLIC_KEY = '';
  static const List<int> _sha256DigestInfoPrefix = <int>[
    0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65,
    0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20,
  ];
  static const String _derivationSalt = 'Aura Mobile Defens model key v1';
  static const String _derivationInfo = 'aura-model-aes-256-cbc-pkcs7';

  static bool verifySignature(
    Uint8List fileBytes,
    Uint8List signatureBytes,
  ) {
    try {
      if (AURA_PUBLIC_KEY.trim().isEmpty || fileBytes.isEmpty) return false;
      final publicKey = _parseRsaPublicKey(AURA_PUBLIC_KEY);
      final modulus = publicKey.$1;
      final exponent = publicKey.$2;
      final modulusLength = (modulus.bitLength + 7) ~/ 8;
      if (signatureBytes.length != modulusLength) return false;

      final signatureInteger = _bigIntFromBytes(signatureBytes);
      if (signatureInteger >= modulus) return false;
      final encodedMessage = _bigIntToBytes(
        signatureInteger.modPow(exponent, modulus),
        modulusLength,
      );
      final digest = sha256.convert(fileBytes).bytes;
      final digestInfo = <int>[
        ..._sha256DigestInfoPrefix,
        ...digest,
      ];
      final paddingLength = modulusLength - digestInfo.length - 3;
      if (paddingLength < 8 ||
          encodedMessage.length != modulusLength ||
          encodedMessage[0] != 0x00 ||
          encodedMessage[1] != 0x01) {
        return false;
      }
      for (var index = 2; index < 2 + paddingLength; index++) {
        if (encodedMessage[index] != 0xff) return false;
      }
      final separatorIndex = 2 + paddingLength;
      if (encodedMessage[separatorIndex] != 0x00) return false;
      final expectedMessage = <int>[
        ...encodedMessage.sublist(0, separatorIndex + 1),
        ...digestInfo,
      ];
      if (expectedMessage.length != encodedMessage.length) return false;

      var difference = 0;
      for (var index = 0; index < encodedMessage.length; index++) {
        difference |= encodedMessage[index] ^ expectedMessage[index];
      }
      return difference == 0;
    } on Object {
      return false;
    }
  }

  static (BigInt, BigInt) _parseRsaPublicKey(String pem) {
    final normalizedPem = pem.trim();
    final header = RegExp(r'^-----BEGIN (PUBLIC KEY|RSA PUBLIC KEY)-----')
        .firstMatch(normalizedPem);
    if (header == null) {
      throw const FormatException('El PEM de clave pública RSA no es válido.');
    }
    final footer = '-----END ${header.group(1)}-----';
    if (!normalizedPem.endsWith(footer)) {
      throw const FormatException('El PEM de clave pública está incompleto.');
    }
    final encoded = normalizedPem
        .substring(header.end, normalizedPem.length - footer.length)
        .replaceAll(RegExp(r'\s'), '');
    final der = Uint8List.fromList(base64.decode(encoded));
    final sequence = _readDerElement(der, 0);
    if (sequence.$1 != 0x30 || sequence.$3 != der.length) {
      throw const FormatException('La clave RSA no contiene una secuencia DER.');
    }

    var offset = 0;
    final first = _readDerElement(sequence.$2, offset);
    if (first.$1 == 0x30) {
      final algorithm = first.$2;
      final algorithmOid = _readDerElement(algorithm, 0);
      const rsaEncryptionOid = <int>[
        0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01,
      ];
      final actualOidDer = _encodeDerElement(algorithmOid.$1, algorithmOid.$2);
      if (!_bytesEqual(actualOidDer, rsaEncryptionOid)) {
        throw const FormatException('El algoritmo PEM no es RSA.');
      }
      if (algorithmOid.$3 < algorithm.length) {
        final parameters = _readDerElement(algorithm, algorithmOid.$3);
        if (parameters.$1 != 0x05 ||
            parameters.$2.isNotEmpty ||
            parameters.$3 != algorithm.length) {
          throw const FormatException(
            'Los parámetros de la clave pública RSA no son válidos.',
          );
        }
      }
      offset = first.$3;
      final bitString = _readDerElement(sequence.$2, offset);
      if (bitString.$1 != 0x03 ||
          bitString.$2.isEmpty ||
          bitString.$2.first != 0 ||
          bitString.$3 != sequence.$2.length) {
        throw const FormatException('El SubjectPublicKeyInfo RSA no es válido.');
      }
      final rsaSequence = Uint8List.sublistView(bitString.$2, 1);
      final innerSequence = _readDerElement(rsaSequence, 0);
      if (innerSequence.$1 != 0x30 ||
          innerSequence.$3 != rsaSequence.length) {
        throw const FormatException('La clave RSA embebida no es válida.');
      }
      return _readRsaIntegers(innerSequence.$2);
    }
    return _readRsaIntegers(sequence.$2);
  }

  static (BigInt, BigInt) _readRsaIntegers(Uint8List sequence) {
    final modulus = _readDerElement(sequence, 0);
    final exponent = _readDerElement(sequence, modulus.$3);
    if (modulus.$1 != 0x02 || exponent.$1 != 0x02 ||
        exponent.$3 != sequence.length ||
        modulus.$2.isEmpty ||
        exponent.$2.isEmpty) {
      throw const FormatException('Los componentes de la clave RSA no son válidos.');
    }
    final modulusValue = _bigIntFromBytes(modulus.$2);
    final exponentValue = _bigIntFromBytes(exponent.$2);
    if (modulusValue.bitLength != 2048 ||
        exponentValue <= BigInt.one ||
        exponentValue.isEven) {
      throw const FormatException('La clave pública RSA no cumple los parámetros.');
    }
    return (modulusValue, exponentValue);
  }

  static (int, Uint8List, int) _readDerElement(
    Uint8List bytes,
    int offset,
  ) {
    if (offset < 0 || offset + 2 > bytes.length) {
      throw const FormatException('La estructura DER está truncada.');
    }
    final tag = bytes[offset];
    var cursor = offset + 1;
    final firstLengthByte = bytes[cursor++];
    int contentLength;
    if ((firstLengthByte & 0x80) == 0) {
      contentLength = firstLengthByte;
    } else {
      final lengthByteCount = firstLengthByte & 0x7f;
      if (lengthByteCount == 0 ||
          lengthByteCount > 4 ||
          cursor + lengthByteCount > bytes.length) {
        throw const FormatException('La longitud DER no es válida.');
      }
      contentLength = 0;
      for (var index = 0; index < lengthByteCount; index++) {
        contentLength = (contentLength << 8) | bytes[cursor++];
      }
      if (contentLength < 128) {
        throw const FormatException('La longitud DER no usa codificación mínima.');
      }
    }
    final contentEnd = cursor + contentLength;
    if (contentEnd > bytes.length) {
      throw const FormatException('El contenido DER está truncado.');
    }
    return (
      tag,
      Uint8List.sublistView(bytes, cursor, contentEnd),
      contentEnd,
    );
  }

  static Uint8List _encodeDerElement(int tag, Uint8List value) {
    final lengthBytes = <int>[];
    if (value.length < 128) {
      lengthBytes.add(value.length);
    } else {
      var remaining = value.length;
      final encodedLength = <int>[];
      while (remaining > 0) {
        encodedLength.insert(0, remaining & 0xff);
        remaining >>= 8;
      }
      lengthBytes
        ..add(0x80 | encodedLength.length)
        ..addAll(encodedLength);
    }
    return Uint8List.fromList(<int>[tag, ...lengthBytes, ...value]);
  }

  static BigInt _bigIntFromBytes(Uint8List bytes) {
    var value = BigInt.zero;
    for (final byte in bytes) {
      value = (value << 8) | BigInt.from(byte);
    }
    return value;
  }

  static Uint8List _bigIntToBytes(BigInt value, int length) {
    final bytes = Uint8List(length);
    var remaining = value;
    for (var index = length - 1; index >= 0; index--) {
      bytes[index] = (remaining & BigInt.from(0xff)).toInt();
      remaining >>= 8;
    }
    if (remaining != BigInt.zero) {
      throw const FormatException('El mensaje RSA excede la longitud esperada.');
    }
    return bytes;
  }

  static bool _bytesEqual(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var index = 0; index < left.length; index++) {
      difference |= left[index] ^ right[index];
    }
    return difference == 0;
  }

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
