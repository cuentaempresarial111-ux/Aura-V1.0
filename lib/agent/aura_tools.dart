import 'package:flutter/services.dart';

class ToolStep {
  const ToolStep({
    required this.name,
    required this.arguments,
  });

  final String name;
  final Map<String, dynamic> arguments;
}

class ToolResult {
  const ToolResult({
    required this.summary,
    required this.data,
  });

  final String summary;
  final Map<String, dynamic> data;
}

abstract class AuraTools {
  static const MethodChannel _engineChannel =
      MethodChannel('com.aura.cyberdefense/engine');

  static Future<ToolResult> execute(ToolStep step) async {
    try {
      switch (step.name) {
        case 'block_domain':
          final domain = step.arguments['domain'];
          final blocked = await _engineChannel.invokeMethod<bool>(
            'addDnsBlockRule',
            {'domain': domain},
          );
          final confirmed = blocked == true;
          return ToolResult(
            summary: confirmed
                ? 'Dominio bloqueado por el motor DNS local.'
                : 'El motor DNS no confirmó el bloqueo del dominio.',
            data: <String, dynamic>{
              'ok': confirmed,
              if (domain != null) 'domain': domain,
            },
          );
        case 'isolate_app':
          final packageName = step.arguments['package_name'];
          final reason = step.arguments['reason'];
          final nativeResult = await _engineChannel.invokeMapMethod<String, dynamic>(
            'openAppDetails',
            <String, dynamic>{
              'package_name': packageName,
              if (reason is String) 'reason': reason,
            },
          );
          if (nativeResult == null) {
            return const ToolResult(
              summary: 'Android no devolvió el resultado de Ajustes.',
              data: <String, dynamic>{'ok': false},
            );
          }
          return ToolResult(
            summary: nativeResult['message'] as String? ??
                nativeResult['error'] as String? ??
                'Android devolvió el resultado de la solicitud.',
            data: Map<String, dynamic>.from(nativeResult),
          );
        default:
          return ToolResult(
            summary: 'Herramienta no reconocida: ${step.name}.',
            data: <String, dynamic>{'ok': false, 'tool': step.name},
          );
      }
    } on PlatformException catch (error) {
      return ToolResult(
        summary: error.message ?? 'Android rechazó la operación solicitada.',
        data: <String, dynamic>{
          'ok': false,
          'code': error.code,
          if (error.details != null) 'details': error.details,
        },
      );
    } on MissingPluginException catch (error) {
      return ToolResult(
        summary: error.message ?? 'El canal nativo de Aura no está disponible.',
        data: <String, dynamic>{'ok': false, 'error': 'missing_plugin'},
      );
    }
  }
}
