import 'dart:async';

import '../providers/aura_state_provider.dart';
import 'aura_intent_parser.dart';
import 'aura_tools.dart';
import 'agent_event.dart';

class AgentController {
  AgentController._();

  static final AgentController instance = AgentController._();

  static const int maxHistoryLength = 500;

  final StreamController<AgentEvent> _eventController =
      StreamController<AgentEvent>.broadcast();

  final List<AgentEvent> history = <AgentEvent>[];
  AuraStateProvider? _securityState;

  Stream<AgentEvent> get events => _eventController.stream;
  Stream<AgentEvent> get stream => _eventController.stream;

  void bindSecurityState(AuraStateProvider state) {
    _securityState = state;
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
      );
      final succeeded = result.data['ok'] == true;
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
          kind: succeeded && !userActionRequired
              ? AgentEventKind.success
              : AgentEventKind.warning,
          message: result.summary,
          data: result.data,
        ),
      );
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

  void _emit(AgentEvent event) {
    history.add(event);
    if (history.length > maxHistoryLength) {
      history.removeRange(0, history.length - maxHistoryLength);
    }
    _eventController.add(event);
  }
}
