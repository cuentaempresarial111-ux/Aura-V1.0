import 'dart:convert';
import 'dart:io';

import '../lib/agent/aura_crypto_layer.dart';
import '../lib/secure_vault.dart';

Future<void> main() async {
  final source = File('assets/model/aura_brain_model.json');
  final destination = File('assets/model/aura_brain_model.enc');
  final plaintext = await source.readAsString();
  final decoded = jsonDecode(plaintext);
  if (decoded is! Map || decoded['trees'] is! List || decoded['trees'].isEmpty) {
    throw const FormatException('El archivo fuente no contiene un bosque válido.');
  }

  final encryptedHex = AuraCryptoLayer.encryptModel(
    plaintext,
    AuraSecureVault.defaultModelMasterKey,
  );
  await destination.writeAsString(encryptedHex, flush: true);
}