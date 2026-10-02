import 'dart:convert';

import '../ai_brain.dart';

class AiBrain {
  final AuraAIBrain _delegate;

  AiBrain() : _delegate = AuraAIBrain();

  Future<String> analizarAmenazaReal({
    required String tipoEvento,
    required List<Map<String, dynamic>> logsDispositivo,
  }) async {
    final payload = jsonEncode({
      'tipoEvento': tipoEvento,
      'logsDispositivo': logsDispositivo,
    });
    return _delegate.analyzeCyberThreat(payload);
  }
}
