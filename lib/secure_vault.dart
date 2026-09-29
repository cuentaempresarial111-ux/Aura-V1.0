import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuraSecureVault {
  static const String _entryPrefix = 'aura_threat_log_';
  static const String _geminiApiKeyStorageKey = 'aura_gemini_api_key';
  static const int _maxEntries = 500;

  // EncryptedSharedPreferences uses Android Keystore; hardware backing is device-dependent.
  static const AndroidOptions _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: false,
  );

  final FlutterSecureStorage _storage;

  AuraSecureVault({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(aOptions: _androidOptions);

  Future<void> saveGeminiApiKey(String apiKey) async {
    final normalizedApiKey = apiKey.trim();
    if (normalizedApiKey.isEmpty) {
      throw ArgumentError.value(apiKey, 'apiKey', 'La clave no puede estar vacía.');
    }
    await _storage.write(key: _geminiApiKeyStorageKey, value: normalizedApiKey);
  }

  Future<String?> readGeminiApiKey() =>
      _storage.read(key: _geminiApiKeyStorageKey);

  Future<void> deleteGeminiApiKey() =>
      _storage.delete(key: _geminiApiKeyStorageKey);

  Future<void> writeLogSecurely(String logText) async {
    final key = '$_entryPrefix${DateTime.now().microsecondsSinceEpoch}';
    final value = jsonEncode({
      'event': logText,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });

    await _storage.write(key: key, value: value);
    await _pruneOldEntries();
  }

  Future<List<Map<String, dynamic>>> readLogsSecurely() async {
    final entries = await _storage.readAll();
    final keys = entries.keys
        .where((key) => key.startsWith(_entryPrefix))
        .toList()
      ..sort();

    return [
      for (final key in keys)
        if (entries[key] case final String value)
          Map<String, dynamic>.from(jsonDecode(value) as Map),
    ];
  }

  Future<void> clearLogsSecurely() async {
    final entries = await _storage.readAll();
    for (final key
        in entries.keys.where((key) => key.startsWith(_entryPrefix))) {
      await _storage.delete(key: key);
    }
  }

  Future<void> _pruneOldEntries() async {
    final entries = await _storage.readAll();
    final keys = entries.keys
        .where((key) => key.startsWith(_entryPrefix))
        .toList()
      ..sort();
    final excess = keys.length - _maxEntries;
    for (final key in keys.take(excess > 0 ? excess : 0)) {
      await _storage.delete(key: key);
    }
  }
}
