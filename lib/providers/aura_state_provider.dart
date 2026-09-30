import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

enum AuraSecurityLevel { safe, warning, critical }

typedef AuraCriticalAlert = Future<void> Function(String message);

class AuraStateProvider extends ChangeNotifier {
  static const int maxTelemetryEvents = 500;
  static const String _criticalAlertMessage =
      'Alerta crítica. Aura está mitigando una amenaza de seguridad.';

  final List<Map<String, dynamic>> _telemetryEvents = [];
  final AuraCriticalAlert? _onCriticalAlert;
  String _liveConsoleLogs = 'SISTEMA AURA: Núcleo defensivo activo e íntegro.';
  bool _isVpnActive = false;
  bool _isScanning = false;
  bool _isAiProcessing = false;
  bool _isVoiceListening = false;
  AuraSecurityLevel _securityLevel = AuraSecurityLevel.safe;

  AuraStateProvider({AuraCriticalAlert? onCriticalAlert})
      : _onCriticalAlert = onCriticalAlert;

  bool get isVpnActive => _isVpnActive;
  bool get isScanning => _isScanning;
  bool get isAiProcessing => _isAiProcessing;
  bool get isVoiceListening => _isVoiceListening;
  String get liveConsoleLogs => _liveConsoleLogs;
  AuraSecurityLevel get securityLevel => _securityLevel;
  String get avatarAnimation => switch (_securityLevel) {
        AuraSecurityLevel.safe => 'idle_friendly',
        AuraSecurityLevel.warning => 'scanning_active',
        AuraSecurityLevel.critical => 'threat_mitigation_mode',
      };
  UnmodifiableListView<Map<String, dynamic>> get telemetryEvents =>
      UnmodifiableListView(_telemetryEvents);

  void setVpnActive(bool active) {
    if (_isVpnActive == active) return;
    _isVpnActive = active;
    notifyListeners();
  }

  void setScanning(bool scanning) {
    if (_isScanning == scanning) return;
    _isScanning = scanning;
    notifyListeners();
  }

  void updatePresentation({
    String? liveConsoleLogs,
    bool? isAiProcessing,
    bool? isVoiceListening,
  }) {
    var changed = false;
    if (liveConsoleLogs != null && liveConsoleLogs != _liveConsoleLogs) {
      _liveConsoleLogs = liveConsoleLogs;
      changed = true;
    }
    if (isAiProcessing != null && isAiProcessing != _isAiProcessing) {
      _isAiProcessing = isAiProcessing;
      changed = true;
    }
    if (isVoiceListening != null && isVoiceListening != _isVoiceListening) {
      _isVoiceListening = isVoiceListening;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void setSecurityLevel(AuraSecurityLevel level) {
    if (_securityLevel == level) return;
    _securityLevel = level;
    notifyListeners();
    if (level == AuraSecurityLevel.critical) {
      unawaited(_onCriticalAlert?.call(_criticalAlertMessage));
    }
  }

  void addTelemetryEvent(Map<String, dynamic> event) {
    _telemetryEvents.add(Map<String, dynamic>.unmodifiable(event));
    if (_telemetryEvents.length > maxTelemetryEvents) {
      _telemetryEvents.removeRange(
        0,
        _telemetryEvents.length - maxTelemetryEvents,
      );
    }
    final action = event['action'];
    if (action == 'DGA_ALERT' || action == 'BLOCKED') {
      _securityLevel = AuraSecurityLevel.warning;
    }
    notifyListeners();
  }
}