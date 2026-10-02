enum AgentEventKind { thought, action, success, warning, error }

class AgentEvent {
  AgentEvent({
    required this.kind,
    required this.message,
    DateTime? ts,
    this.data,
  }) : ts = ts ?? DateTime.now();

  final AgentEventKind kind;
  final String message;
  final DateTime ts;
  final Map<String, dynamic>? data;
}
