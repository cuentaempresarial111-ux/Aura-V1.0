// voice_engine.dart - Motor de Voz Nativo de Aura
import 'package:flutter_tts/flutter_tts.dart';

class AuraVoiceEngine {
  final FlutterTts _flutterTts = FlutterTts();

  AuraVoiceEngine() {
    _initializeVoice();
  }

  void _initializeVoice() async {
    await _flutterTts.setLanguage("es-ES"); // Configura a Aura en español estándar
    await _flutterTts.setSpeechRate(0.55);   // Velocidad cibernética, sofisticada y fluida
    await _flutterTts.setVolume(1.0);        // Volumen de alerta al máximo
    await _flutterTts.setPitch(1.05);        // Tonalidad de voz robótica femenina estilizada
  }

  // Ejecuta la síntesis de voz en tiempo real
  Future<void> speak(String text) async {
    if (text.isNotEmpty) {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    }
  }

  Future<void> announceToolExecution(
    String toolName,
    Map<String, Object?> arguments,
  ) {
    switch (toolName) {
      case 'mitigate_network_threat':
        final domain = arguments['domain'] as String? ?? 'dominio detectado';
        final appPackage =
            arguments['app_package'] as String? ?? 'aplicación observada';
        return speak(
          'Analizando telemetría. Amenaza de red detectada para $appPackage. '
          'Bloqueando $domain en el DNS local para todo el dispositivo.',
        );
      case 'isolate_malicious_app':
        final packageName =
            arguments['package_name'] as String? ?? 'aplicación identificada';
        return speak(
          'Alerta crítica. Abriendo los ajustes de $packageName para que '
          'revises la aplicación y decidas las acciones necesarias.',
        );
      default:
        return speak('Aura está ejecutando una acción de ciberdefensa.');
    }
  }

  Future<void> announceToolResult(
    String toolName,
    Map<String, Object?> result,
  ) {
    if (result['ok'] == true && toolName == 'mitigate_network_threat') {
      return speak('La regla DNS global fue aplicada correctamente.');
    }
    if (result['ok'] == true && toolName == 'isolate_malicious_app') {
      return speak('Ajustes abiertos. La decisión final queda en tus manos.');
    }
    final error = result['error'] as String? ?? 'acción no confirmada';
    return speak('No se confirmó la contramedida: $error');
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }
}
