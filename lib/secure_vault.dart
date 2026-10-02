import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuraSecureVault {
  static const String _auditLogsKey = 'aura_audit_logs_v1';
  static const String _modelMasterKeyStorageKey = 'aura_model_master_key_v1';
  static const String defaultModelMasterKey =
      'AuraMobileDefens::ModelMasterKey::2026::v1';
  static const int maxAuditLogs = 500;
  static const AndroidOptions _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
    resetOnError: true,
  );
  static Future<void> _writeQueue = Future<void>.value();

  final FlutterSecureStorage _storage;

  AuraSecureVault({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(aOptions: _androidOptions);

  Future<String> getOrCreateModelMasterKey() async {
    final existingKey = await _storage.read(key: _modelMasterKeyStorageKey);
    if (existingKey != null && existingKey.isNotEmpty) return existingKey;

    await _storage.write(
      key: _modelMasterKeyStorageKey,
      value: defaultModelMasterKey,
    );
    final persistedKey = await _storage.read(key: _modelMasterKeyStorageKey);
    if (persistedKey != defaultModelMasterKey) {
      throw StateError('No se pudo inicializar la clave del modelo en SecureVault.');
    }
    return persistedKey!;
  }

  Future<void> saveAuditLogs(List<Map<String, dynamic>> newLogs) {
    final completion = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        final history = await getAuditLogs();
        final combined = <Map<String, dynamic>>[
          ...history,
          ...newLogs.map((log) => Map<String, dynamic>.from(log)),
        ];
        final bounded = combined.length > maxAuditLogs
            ? combined.sublist(combined.length - maxAuditLogs)
            : combined;
        await _storage.write(
          key: _auditLogsKey,
          value: jsonEncode(bounded),
        );
        completion.complete();
      } catch (error, stackTrace) {
        completion.completeError(error, stackTrace);
      }
    });
    return completion.future;
  }

  Future<List<Map<String, dynamic>>> getAuditLogs() async {
    final encoded = await _storage.read(key: _auditLogsKey);
    if (encoded == null || encoded.isEmpty) return <Map<String, dynamic>>[];
    final decoded = jsonDecode(encoded);
    if (decoded is! List || decoded.any((entry) => entry is! Map)) {
      throw const FormatException('El historial de auditoría almacenado no es válido.');
    }
    final records = decoded
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .toList(growable: false);
    return records.length > maxAuditLogs
        ? records.sublist(records.length - maxAuditLogs)
        : records;
  }

  Future<void> writeLogSecurely(String logText) => writeLogsSecurely([logText]);

  Future<void> writeLogsSecurely(Iterable<String> logTexts) {
    final now = DateTime.now().toUtc().toIso8601String();
    return saveAuditLogs([
      for (final text in logTexts) {'event': text, 'timestamp': now},
    ]);
  }

  Future<List<Map<String, dynamic>>> readLogsSecurely() => getAuditLogs();

  Future<void> clearLogsSecurely() => _storage.delete(key: _auditLogsKey);
}
