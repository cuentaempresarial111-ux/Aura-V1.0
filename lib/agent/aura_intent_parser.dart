import 'agent_event.dart';

enum AuraIntentKind { block, isolate, status, unknown }

class AuraIntent {
  const AuraIntent({
    required this.name,
    required this.kind,
    required this.entities,
    required this.confidence,
  });

  final String name;
  final AuraIntentKind kind;
  final Map<String, dynamic> entities;
  final double confidence;

  AgentEvent toEvent() => AgentEvent(
        kind: switch (kind) {
          AuraIntentKind.block || AuraIntentKind.isolate => AgentEventKind.action,
          AuraIntentKind.status => AgentEventKind.thought,
          AuraIntentKind.unknown => AgentEventKind.warning,
        },
        message: name,
        data: <String, dynamic>{
          'entities': Map<String, dynamic>.from(entities),
          'confidence': confidence,
        },
      );
}

class AuraIntentParser {
  AuraIntentParser._();

  static const int historyCapacity = 5;
  static final List<AuraIntent?> _historyBuffer =
      List<AuraIntent?>.filled(historyCapacity, null);
  static int _nextHistoryIndex = 0;
  static int _historySize = 0;

  static final RegExp _blockCommand = RegExp(
    r'\b(?:bloquea|bloquear|bloquee|bloqueo|block|blockear|deniega|denegar)\b',
    caseSensitive: false,
  );
  static final RegExp _isolateCommand = RegExp(
    r'\b(?:a[ií]sla|a[ií]slar|aislamiento|isolate)\b',
    caseSensitive: false,
  );
  static final RegExp _statusCommand = RegExp(
    r'\b(?:estado|status|salud|state|health|cómo está|como esta)\b',
    caseSensitive: false,
  );
  static final RegExp _ipv4Pattern = RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}\b');
  static final RegExp _hostPattern = RegExp(
    r'\b(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\b',
    caseSensitive: false,
  );
  static final RegExp _packageLabelPattern = RegExp(
    r'\b(?:paquete|package|aplicación|aplicacion|app)\s*[:=]?\s*([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+)\b',
    caseSensitive: false,
  );
  static final RegExp _androidPackagePattern = RegExp(
    r'\b(?:com|org|net|io|dev|app|co|es|gov|edu)(?:\.[a-z][a-z0-9_]*){1,}\b',
    caseSensitive: false,
  );

  static List<AuraIntent> get history {
    final oldestIndex = (_nextHistoryIndex - _historySize + historyCapacity) %
        historyCapacity;
    return List<AuraIntent>.unmodifiable(
      List<AuraIntent>.generate(
        _historySize,
        (index) => _historyBuffer[(oldestIndex + index) % historyCapacity]!,
      ),
    );
  }

  static Future<AuraIntent> parse(String text) {
    final host = _extractHost(text);
    final isBlockCommand = _blockCommand.hasMatch(text);
    final isIsolateCommand = _isolateCommand.hasMatch(text);

    late final AuraIntent intent;
    if (isBlockCommand && host != null) {
      intent = AuraIntent(
        name: 'block_domain',
        kind: AuraIntentKind.block,
        entities: <String, dynamic>{'domain': host},
        confidence: 0.96,
      );
    } else if (isIsolateCommand) {
      final packageName = _extractPackageName(text);
      intent = AuraIntent(
        name: 'isolate_app',
        kind: AuraIntentKind.isolate,
        entities: <String, dynamic>{
          if (packageName != null) 'package_name': packageName,
        },
        confidence: packageName == null ? 0.62 : 0.96,
      );
    } else if (_statusCommand.hasMatch(text)) {
      intent = AuraIntent(
        name: 'status',
        kind: AuraIntentKind.status,
        entities: <String, dynamic>{},
        confidence: 0.88,
      );
    } else {
      intent = AuraIntent(
        name: 'unknown',
        kind: AuraIntentKind.unknown,
        entities: <String, dynamic>{},
        confidence: 0.0,
      );
    }

    _remember(intent);
    return Future<AuraIntent>.value(intent);
  }

  static String? _extractHost(String text) {
    for (final match in _ipv4Pattern.allMatches(text)) {
      final value = match.group(0)!;
      final octets = value.split('.');
      if (octets.every((octet) {
        final number = int.tryParse(octet);
        return number != null && number >= 0 && number <= 255;
      })) {
        return value;
      }
    }
    return _hostPattern.firstMatch(text)?.group(0)?.toLowerCase();
  }

  static String? _extractPackageName(String text) {
    final labeledPackage = _packageLabelPattern.firstMatch(text)?.group(1);
    if (labeledPackage != null) return labeledPackage;
    return _androidPackagePattern.firstMatch(text)?.group(0);
  }

  static void _remember(AuraIntent intent) {
    _historyBuffer[_nextHistoryIndex] = intent;
    _nextHistoryIndex = (_nextHistoryIndex + 1) % historyCapacity;
    if (_historySize < historyCapacity) _historySize++;
  }
}
