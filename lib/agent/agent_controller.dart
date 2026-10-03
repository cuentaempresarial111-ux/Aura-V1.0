import 'dart:async';

import '../ai_brain.dart';
import '../providers/aura_state_provider.dart';
import '../voice_engine.dart';
import 'aura_intent_parser.dart';
import 'aura_tools.dart';
import 'agent_event.dart';

class AgentController {
  AgentController._() {
    AuraAIBrain.onModelIntegrityFailure = reportCriticalError;
  }

  static final AgentController instance = AgentController._();

  static const int maxHistoryLength = 500;
  static final AuraVoiceEngine _voiceEngine = AuraVoiceEngine();

  final StreamController<AgentEvent> _eventController =
      StreamController<AgentEvent>.broadcast();

  final List<AgentEvent> history = <AgentEvent>[];
  AuraStateProvider? _securityState;

  Stream<AgentEvent> get events => _eventController.stream;
  Stream<AgentEvent> get stream => _eventController.stream;

  void bindSecurityState(AuraStateProvider state) {
    _securityState = state;
    if (history.any(
      (event) => event.data?['critical_integrity_failure'] == true,
    )) {
      state.setSecurityLevel(AuraSecurityLevel.critical);
    }
  }

  Future<void> run(String instruction) async {
    _emit(
      AgentEvent(
        kind: AgentEventKind.thought,
        message: 'Inicio del análisis sintáctico léxico.',
        data: <String, dynamic>{'instruction': instruction},
      ),
    );
    try {
      final intent = await AuraIntentParser.parse(instruction);
      if (intent.kind == AuraIntentKind.unknown) {
        _securityState?.setSecurityLevel(AuraSecurityLevel.warning);
        _emit(
          AgentEvent(
            kind: AgentEventKind.warning,
            message: 'No se reconoció una acción local segura.',
            data: <String, dynamic>{'instruction': instruction},
          ),
        );
        return;
      }

      if (intent.kind == AuraIntentKind.status) {
        final level = _securityState?.securityLevel;
        _emit(
          AgentEvent(
            kind: AgentEventKind.success,
            message: 'Estado de seguridad: ${level?.name ?? 'no disponible'}.',
            data: <String, dynamic>{'security_level': level?.name},
          ),
        );
        return;
      }

      _emit(intent.toEvent());
      final result = await AuraTools.execute(
        ToolStep(name: intent.name, arguments: intent.entities),
        onProgress: intent.kind == AuraIntentKind.updateDefenses
            ? (message) => _emit(
                  AgentEvent(
                    kind: AgentEventKind.thought,
                    message: message,
                    data: <String, dynamic>{'tool': intent.name},
                  ),
                )
            : null,
      );
      final succeeded = result.data['ok'] == true;
      final integrityCheckFailed =
          result.data['critical_integrity_failure'] == true ||
              result.data['security_level'] == 'critical';
      if (intent.kind == AuraIntentKind.cryptographicPurge && succeeded) {
        history.clear();
        AuraIntentParser.clearHistory();
        _securityState?.clearTelemetryHistory();
      }
      final userActionRequired = result.data['user_action_required'] == true;
      final securityLevel = switch (result.data['security_level']) {
        'critical' => AuraSecurityLevel.critical,
        'warning' => AuraSecurityLevel.warning,
        'safe' => AuraSecurityLevel.safe,
        _ => succeeded && !userActionRequired
            ? AuraSecurityLevel.safe
            : AuraSecurityLevel.warning,
      };
      _securityState?.setSecurityLevel(securityLevel);
      _emit(
        AgentEvent(
          kind: integrityCheckFailed
              ? AgentEventKind.error
              : succeeded && !userActionRequired
                  ? AgentEventKind.success
                  : AgentEventKind.warning,
          message: result.summary,
          data: result.data,
        ),
      );
      if (intent.kind == AuraIntentKind.updateDefenses && succeeded) {
        try {
          await _voiceEngine.speak(
            'Actualización completada. El modelo local de 500 árboles fue renovado.',
          );
        } on Object catch (error) {
          _emit(
            AgentEvent(
              kind: AgentEventKind.warning,
              message:
                  'Actualización completada, pero falló la narración por voz: $error',
              data: <String, dynamic>{'tool': intent.name},
            ),
          );
        }
      }
    } on Object catch (error) {
      _securityState?.setSecurityLevel(AuraSecurityLevel.warning);
      _emit(
        AgentEvent(
          kind: AgentEventKind.error,
          message: error.toString(),
          data: <String, dynamic>{'instruction': instruction},
        ),
      );
    }
  }

  void reportError(String message) {
    _emit(
      AgentEvent(
        kind: AgentEventKind.error,
        message: message,
      ),
    );
  }

  void reportCriticalError(String message) {
    _securityState?.setSecurityLevel(AuraSecurityLevel.critical);
    _emit(
      AgentEvent(
        kind: AgentEventKind.error,
        message: message,
        data: const <String, dynamic>{
          'critical_integrity_failure': true,
          'security_level': 'critical',
        },
      ),
    );
  }

  void _emit(AgentEvent event) {
    history.add(event);
    if (history.length > maxHistoryLength) {
      history.removeRange(0, history.length - maxHistoryLength);
    }
    _eventController.add(event);
  }
}
