import 'package:flutter/services.dart';

import '../ai_brain.dart';
import '../secure_vault.dart';

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
  static final AuraSecureVault _secureVault = AuraSecureVault();

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
        case 'panic_isolation':
          final isolated = await _engineChannel.invokeMethod<bool>(
                'panicIsolation',
              ) ??
              false;
          return ToolResult(
            summary: isolated
                ? 'Forwarding del túnel detenido; la interfaz VPN queda en modo de descarte.'
                : 'No se confirmó el aislamiento: el túnel VPN no estaba activo.',
            data: <String, dynamic>{
              'ok': isolated,
              'isolation_active': isolated,
              'scope': 'active_vpn_tun',
              'security_level': isolated ? 'critical' : 'warning',
            },
          );
        case 'resume_network':
          final resumed = await _engineChannel.invokeMethod<bool>(
                'resumeTunnel',
              ) ??
              false;
          return ToolResult(
            summary: resumed
                ? 'Forwarding del túnel restablecido.'
                : 'No se pudo restablecer el forwarding del túnel.',
            data: <String, dynamic>{
              'ok': resumed,
              'security_level': resumed ? 'safe' : 'warning',
            },
          );
        case 'cryptographic_purge':
          await AuraAIBrain.purgeAllInMemoryModels();
          final nativeAuditPurged = await _engineChannel.invokeMethod<bool>(
                'purgeAuditMemory',
              ) ??
              false;
          await _secureVault.purgeSensitiveData();
          return const ToolResult(
            summary:
                'Cachés de modelos y datos de SecureVault eliminados. No hay una API key registrada en este almacenamiento.',
            data: <String, dynamic>{
              'ok': true,
              'model_cache_purged': true,
              'secure_storage_purged': true,
              'native_audit_memory_purged': nativeAuditPurged,
              'api_key_present': false,
            },
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
