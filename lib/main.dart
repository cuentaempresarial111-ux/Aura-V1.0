import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'security_engine.dart';
import 'voice_engine.dart';
import 'ai_brain.dart';
import 'radar_waves.dart';
import 'secure_vault.dart';
import 'network_auditor.dart';
import 'providers/aura_state_provider.dart';
import 'screens/aura_core_screen.dart' as holographic_screen;
import 'screens/splash_screen.dart';

enum AuraState { secure, scanning, warning, critical }

void main() {
  final voiceEngine = AuraVoiceEngine();
  runApp(
    MultiProvider(
      providers: [
        Provider<AuraVoiceEngine>.value(value: voiceEngine),
        ChangeNotifierProvider(
          create: (_) => AuraStateProvider(onCriticalAlert: voiceEngine.speak),
        ),
      ],
      child: const AuraApp(),
    ),
  );
}

class AuraApp extends StatelessWidget {
  const AuraApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aura Mobile Defens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF020617),
      ),
      home: const SplashScreen(),
    );
  }
}

class AuraCoreScreen extends StatefulWidget {
  const AuraCoreScreen({Key? key}) : super(key: key);

  @override
  State<AuraCoreScreen> createState() => _AuraCoreScreenState();
}

class _AuraCoreScreenState extends State<AuraCoreScreen>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _voiceChannel =
      MethodChannel('com.ciberdefensa.aura/voice');

  late AnimationController _pulseController;
  late StreamSubscription<Map<String, dynamic>> _integritySubscription;
  late StreamSubscription<NetworkAuditEvent> _networkThreatSubscription;
  Timer? _tunnelStatsTimer;
  late final AuraAIBrain _aiBrain;
  late final AuraNetworkAuditor _networkAuditor;
  final AuraSecurityEngine _securityEngine = AuraSecurityEngine();
  late final AuraVoiceEngine _voiceEngine;
  final AuraSecureVault _secureVault = AuraSecureVault();
  final TextEditingController _inputController = TextEditingController();

  bool _agentToolActionOccurred = false;
  String? _lastRecordedIntegrityLog;

  AuraStateProvider get _state => context.read<AuraStateProvider>();
  String get _liveConsoleLogs => _state.liveConsoleLogs;
  bool get _aiProcessing => _state.isAiProcessing;
  bool get _voiceListening => _state.isVoiceListening;
  bool get _shieldActive => context.read<AuraStateProvider>().isVpnActive;

  String get _securityStatus {
    final state = context.read<AuraStateProvider>();
    if (state.isScanning) return "SCANNING";
    return switch (state.securityLevel) {
      AuraSecurityLevel.safe => "SECURE",
      AuraSecurityLevel.warning => "WARNING",
      AuraSecurityLevel.critical => "THREAT",
    };
  }

  AuraState get _auraState {
    final state = context.read<AuraStateProvider>();
    if (state.isScanning) return AuraState.scanning;
    return switch (state.securityLevel) {
      AuraSecurityLevel.safe => AuraState.secure,
      AuraSecurityLevel.warning => AuraState.warning,
      AuraSecurityLevel.critical => AuraState.critical,
    };
  }

  String get _faceState =>
      context.read<AuraStateProvider>().avatarAnimation;

  @override
  void initState() {
    super.initState();
    _voiceEngine = context.read<AuraVoiceEngine>();
    _aiBrain = AuraAIBrain(
      stateProvider: context.read<AuraStateProvider>(),
      onToolStarted: _handleAgentToolStarted,
      onToolCompleted: _handleAgentToolCompleted,
    );
    _networkAuditor = AuraNetworkAuditor(aiBrain: _aiBrain);
    _networkThreatSubscription =
        _networkAuditor.eventStream.listen(_handleNetworkAuditEvent);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _tunnelStatsTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _refreshTunnelStats(),
    );
    unawaited(_refreshTunnelStats());

    _integritySubscription =
        _securityEngine.monitorDeviceIntegrity().listen((event) {
      if (!mounted || _securityStatus == "SCANNING") return;

      final level = event["level"] as SystemThreatLevel;
      final logs = event["logs"] as String;
      final critical =
          level == SystemThreatLevel.critical || _agentToolActionOccurred;
      if (!_agentToolActionOccurred) {
        _state.updatePresentation(liveConsoleLogs: logs);
      }
        context.read<AuraStateProvider>().setSecurityLevel(
          critical
            ? AuraSecurityLevel.critical
            : level == SystemThreatLevel.warning
              ? AuraSecurityLevel.warning
              : AuraSecurityLevel.safe,
          );

      if ((level != SystemThreatLevel.secure || _agentToolActionOccurred) &&
          logs != _lastRecordedIntegrityLog) {
        final message = _agentToolActionOccurred
            ? 'Acción defensiva local ejecutada; estado crítico retenido.'
            : logs;
        _lastRecordedIntegrityLog = message;
        _writeSecureLog(message);
      }
      if (critical) {
        _voiceEngine.speak("Alerta crítica de integridad detectada.");
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _tunnelStatsTimer?.cancel();
    _integritySubscription.cancel();
    _networkThreatSubscription.cancel();
    _voiceEngine.stop();
    _inputController.dispose();
    unawaited(_networkAuditor.dispose());
    super.dispose();
  }

  Future<void> _refreshTunnelStats() async {
    if (!mounted || !_state.isVpnActive) return;
    try {
      final stats = await const MethodChannel('com.aura.cyberdefense/engine')
          .invokeMethod<List<dynamic>>('getTunnelStats');
      if (!mounted || stats == null || stats.length < 4) return;
      final txBytes = (stats[1] as num).toInt();
      final rxBytes = (stats[3] as num).toInt();
      _state.updateTunnelBytesProcessed(txBytes + rxBytes);
    } on PlatformException {
      // The tunnel can stop between the timer tick and the native query.
    } on MissingPluginException {
      // Stats are unavailable on platforms without the Android tunnel.
    }
  }

  Color _getCoreColor() {
    final state = context.read<AuraStateProvider>();
    if (state.isScanning) return const Color(0xFF06B6D4);
    if (state.securityLevel == AuraSecurityLevel.critical) {
      return const Color(0xFFEF4444);
    }
    if (state.securityLevel == AuraSecurityLevel.warning) {
      return const Color(0xFFF59E0B);
    }
    if (state.lastNetworkAction == 'ALLOWED') {
      return const Color(0xFF70E1BB);
    }
    return const Color(0xFF38BDF8);
  }

  void _triggerLocalScan() async {
    var hostileEnvironment = false;
    _agentToolActionOccurred = false;
    context.read<AuraStateProvider>().setScanning(true);
    _state.updatePresentation(
      isAiProcessing: true,
      liveConsoleLogs:
          'INICIANDO AUDITORÍA INTERNA: Analizando firmas criptográficas y telemetría local...',
    );
    try {
      _voiceEngine.speak("Iniciando auditoría interna del sistema.");
      final environment = await _securityEngine.checkHostileEnvironment();
      hostileEnvironment = environment['isHostile'] == true;
      if (!mounted) return;
      if (hostileEnvironment) {
        context.read<AuraStateProvider>()
            .setSecurityLevel(AuraSecurityLevel.critical);
        _state.updatePresentation(
          liveConsoleLogs:
              'ALERTA MÁXIMA: ${environment['indicators'] ?? 'entorno hostil'}',
        );
        _voiceEngine.speak('Alerta máxima de entorno hostil detectado.');
        await _writeSecureLog(_liveConsoleLogs);
      }

      final genomeReport =
          await _securityEngine.scanActiveSensitiveServices();
      final rawApplications = genomeReport['applications'];
      final applications = rawApplications is List
          ? rawApplications.whereType<Map>().toList()
          : const <Map>[];
      final packageNames = applications
          .map((application) => application['package_name'])
          .whereType<String>()
          .join(', ');
        final environmentIndicators =
          (environment['indicators'] as List?)?.join(', ') ?? 'indicadores disponibles';
      final payload = jsonEncode({
        'app_genome_scan': genomeReport,
        'hostile_environment': environment,
      });
      if (!mounted) return;
      final scanSummary = applications.isEmpty
          ? 'App Genome: no hay servicios sensibles activos.'
          : 'App Genome: ${applications.length} apps con servicios sensibles: '
              '$packageNames';
      _state.updatePresentation(
        liveConsoleLogs: hostileEnvironment
            ? 'ALERTA MÁXIMA: $environmentIndicators. $scanSummary'
            : scanSummary,
      );
          context.read<AuraStateProvider>().setSecurityLevel(
            hostileEnvironment
              ? AuraSecurityLevel.critical
              : applications.isEmpty
                ? AuraSecurityLevel.safe
                : AuraSecurityLevel.warning,
            );
      await _writeSecureLog('App Genome Scanner: $payload');
      final response = await _analyzeWithStoredKey(
        'Analiza este informe local de App Genome Scanner y entorno. '
        'Resume solo evidencias incluidas, indica cuántas apps tienen servicios '
        'sensibles activos y no rebajes una alerta crítica. JSON: $payload',
      );
      if (!mounted) return;

      _state.updatePresentation(
        liveConsoleLogs: hostileEnvironment || _agentToolActionOccurred
            ? 'ALERTA CRÍTICA: $response'
            : response,
      );
      context.read<AuraStateProvider>().setSecurityLevel(
            hostileEnvironment || _agentToolActionOccurred
                ? AuraSecurityLevel.critical
                : applications.isEmpty
                    ? AuraSecurityLevel.safe
                    : AuraSecurityLevel.warning,
          );

      await _writeSecureLog('Escaneo: $response');
      _voiceEngine.speak(response);
    } catch (error) {
      if (!mounted) return;
      context.read<AuraStateProvider>().setSecurityLevel(
            hostileEnvironment || _agentToolActionOccurred
                ? AuraSecurityLevel.critical
                : AuraSecurityLevel.warning,
          );
      _state.updatePresentation(
        liveConsoleLogs: hostileEnvironment || _agentToolActionOccurred
          ? 'ALERTA CRÍTICA: falló una parte del escaneo local.'
          : 'No se pudo completar la auditoría local.',
      );
          context.read<AuraStateProvider>().setSecurityLevel(
            hostileEnvironment || _agentToolActionOccurred
                ? AuraSecurityLevel.critical
                : AuraSecurityLevel.warning,
              );
      await _writeSecureLog('Error de auditoría App Genome: $error');
    } finally {
      if (mounted) {
        context.read<AuraStateProvider>().setScanning(false);
        _state.updatePresentation(isAiProcessing: false);
      }
    }
  }

  void _handleAIQuery() async {
    final query = _inputController.text.trim();
    if (query.isEmpty) return;

    _inputController.clear();
    _agentToolActionOccurred = false;
    _state.updatePresentation(
      isAiProcessing: true,
      liveConsoleLogs: 'Aura procesando consulta analítica...',
    );

    try {
      final response = await _analyzeWithStoredKey(query);
      if (!mounted) return;

      _state.updatePresentation(
        liveConsoleLogs: _agentToolActionOccurred
            ? 'ALERTA CRÍTICA: Aura ejecutó una acción defensiva. $response'
        : response,
      );
      await _writeSecureLog('Consulta: $query\nRespuesta: $response');
      _voiceEngine.speak(response);
    } finally {
      if (mounted) _state.updatePresentation(isAiProcessing: false);
    }
  }

  Future<void> _startVoiceCommand() async {
    if (_voiceListening || _aiProcessing) return;
    _state.updatePresentation(isVoiceListening: true);
    try {
      final transcript = await _voiceChannel.invokeMethod<String>(
        'startListening',
      );
      if (!mounted || transcript == null || transcript.trim().isEmpty) return;
      _inputController.text = transcript.trim();
      _handleAIQuery();
    } on PlatformException catch (error) {
      if (!mounted) return;
      context.read<AuraStateProvider>()
          .setSecurityLevel(AuraSecurityLevel.warning);
      _state.updatePresentation(
        liveConsoleLogs: error.message ?? 'No se pudo reconocer la voz.',
      );
    } on MissingPluginException {
      if (!mounted) return;
      context.read<AuraStateProvider>()
          .setSecurityLevel(AuraSecurityLevel.warning);
      _state.updatePresentation(
        liveConsoleLogs: 'El reconocimiento de voz no está disponible.',
      );
    } finally {
      if (mounted) _state.updatePresentation(isVoiceListening: false);
    }
  }

  Future<void> _showWhitePaper() => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.86,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: const SelectableText(_whitePaperText),
            ),
          ),
        ),
      );

  static const String _whitePaperText = '''
AURA MOBILE DEFENS · LIBRO BLANCO OPERATIVO

COMANDOS
• “Activa todas las defensas”, “protección total” o “modo maestro”: solicita
  activate_master_defense. Aura inicia el VPN, escanea servicios sensibles y
  comprueba entorno e integridad en ese orden. Cada resultado es reportado; el
  consentimiento VPN de Android sigue siendo obligatorio.
• “Escanea aplicaciones” o “audita servicios”: consulta App Genome Scanner.
• “Bloquea [dominio]”: puede activar mitigate_network_threat si la telemetría
  aporta dominio y paquete. La regla afecta a todo el dispositivo, no solo a una
  aplicación.
• “Revisa/aisla [paquete]”: isolate_malicious_app abre los ajustes de Android.
  Aura no fuerza detención ni desinstalación.
• El motor local clasifica dominios mediante características léxicas y un bosque
  de reglas JSON. No interpreta consultas generales ni reemplaza una revisión
  humana; una predicción de amenaza solicita un bloqueo DNS global.

INSPECCIÓN DNS
El motor C analiza consultas UDP/53 en memoria. La heurística DGA actual marca
etiquetas de al menos 40 caracteres con 20 o más caracteres ASCII únicos y al
menos 4 dígitos. Las coincidencias reciben 127.0.0.1 para A o ::1 para AAAA.
Una regla explícita añade el dominio exacto a una lista global en memoria de
hasta 256 entradas y también descarta conexiones SOCKS que reutilicen IPs
sintéticas ya asignadas a ese dominio. No inspecciona DoH/DoT ni bloquea por UID.

APP GENOME
Solo informa servicios instalados que declaran exactamente
BIND_ACCESSIBILITY_SERVICE o BIND_NOTIFICATION_LISTENER_SERVICE y que están
habilitados por PackageManager y por el ajuste seguro correspondiente del
usuario. Un permiso declarado sin activación no cuenta como servicio activo.

ACCIONES Y LÍMITES
Las acciones DNS pasan por Android MethodChannel y sus respuestas reales quedan
registradas. El callback táctico eleva la UI a estado crítico y TTS anuncia el
resultado confirmado o el error. Android
puede denegar micrófono, VPN, visibilidad de paquetes o resolución de UID; Aura
lo informa y no afirma haber realizado acciones que el sistema no confirmó.
''';

  void _handleAgentToolStarted(
    String toolName,
    Map<String, Object?> arguments,
  ) {
    _agentToolActionOccurred = true;
    if (mounted) {
      context.read<AuraStateProvider>()
          .setSecurityLevel(AuraSecurityLevel.critical);
    }
    if (mounted) {
      _state.updatePresentation(
        liveConsoleLogs: 'ALERTA CRÍTICA: Aura está ejecutando $toolName.',
      );
    }
  }

  void _handleNetworkAuditEvent(NetworkAuditEvent event) {
    if (!mounted) return;
    context.read<AuraStateProvider>().addTelemetryEvent(event.toJson());
    if (event.action == NetworkAuditAction.dgaAlert) {
      _state.updatePresentation(
        liveConsoleLogs:
            'ALERTA DGA: ${event.requestedDomain}. Aura está analizando la amenaza.',
      );
    } else if (event.action == NetworkAuditAction.blocked) {
      _state.updatePresentation(
        liveConsoleLogs:
            'DNS bloqueado: ${event.requestedDomain}. Aura está analizando el evento.',
      );
    }
  }

  void _handleAgentToolCompleted(
    String toolName,
    Map<String, Object?> arguments,
    Map<String, Object?> result,
  ) {
    _agentToolActionOccurred = true;
    final success = result['ok'] == true;
    if (mounted) {
      context.read<AuraStateProvider>()
          .setSecurityLevel(AuraSecurityLevel.critical);
    }
    if (mounted) {
      final detail = result['message'] ?? result['error'] ?? 'sin detalle';
      _state.updatePresentation(
        liveConsoleLogs: success
            ? 'ALERTA CRÍTICA: $detail'
            : 'ALERTA CRÍTICA: acción no confirmada. $detail',
      );
    }
    unawaited(_writeSecureLog('Herramienta $toolName: ${jsonEncode(result)}'));
    unawaited(_voiceEngine.announceToolResult(toolName, result));
  }

  Future<String> _analyzeWithStoredKey(String prompt) =>
      _aiBrain.analyzeCyberThreat(prompt);

  Future<void> _toggleNetworkShield() async {
    final requestedState = !_shieldActive;
    context.read<AuraStateProvider>().setScanning(true);
    _state.updatePresentation(
      liveConsoleLogs: requestedState
          ? "Solicitando autorización y arranque del escudo..."
          : "Deteniendo el escudo...",
    );

    try {
      final active = await _aiBrain.setShieldActive(requestedState);
      if (!mounted) return;
      final operationSucceeded = active == requestedState;
      if (operationSucceeded) {
        context.read<AuraStateProvider>().setVpnActive(requestedState);
      }
      context.read<AuraStateProvider>().setSecurityLevel(
            operationSucceeded
                ? AuraSecurityLevel.safe
                : AuraSecurityLevel.critical,
          );
      _state.updatePresentation(
        liveConsoleLogs: !operationSucceeded
            ? "No se pudo cambiar el estado del escudo."
            : requestedState
                ? "Escudo VPN activo."
                : "Escudo detenido.",
      );
      await _writeSecureLog(_liveConsoleLogs);
    } catch (error) {
      if (!mounted) return;
      context.read<AuraStateProvider>()
          .setSecurityLevel(AuraSecurityLevel.critical);
      _state.updatePresentation(
        liveConsoleLogs: 'No se pudo cambiar el estado del escudo.',
      );
      await _writeSecureLog('Error de escudo: $error');
    } finally {
      if (mounted) {
        context.read<AuraStateProvider>().setScanning(false);
      }
    }
  }

  Future<void> _writeSecureLog(String message) async {
    try {
      await _secureVault.writeLogSecurely(message);
    } catch (error) {
      debugPrint('No se pudo persistir el registro seguro: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final providerState = context.watch<AuraStateProvider>();
    final statusLabel = providerState.isVoiceListening
        ? 'ESCUCHANDO'
      : providerState.isAiProcessing
            ? 'ANALIZANDO'
            : providerState.isScanning
              ? 'ESCANEANDO'
                : switch (providerState.securityLevel) {
                    AuraSecurityLevel.critical => 'PROTECCIÓN CRÍTICA',
                    AuraSecurityLevel.warning => 'REVISIÓN REQUERIDA',
                    AuraSecurityLevel.safe => 'AURA LISTA',
                  };

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 6, right: 12),
                child: IconButton(
                  tooltip: 'Libro Blanco',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.info_outline, size: 20),
                  color: Colors.white54,
                  onPressed: _showWhitePaper,
                ),
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final sceneSize = math.min(
                    math.min(constraints.maxWidth * 0.9, constraints.maxHeight * 0.88),
                    390.0,
                  );
                  return Center(
                    child: SizedBox.square(
                      dimension: sceneSize,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          RepaintBoundary(
                            child: AuraRadarWaves(
                              animation: _pulseController,
                              themeColor: _getCoreColor(),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: holographic_screen.AuraHolographicHud(
                              state: providerState,
                              tunnelActive: providerState.isVpnActive,
                              accentColor: _getCoreColor(),
                            ),
                          ),
                          RepaintBoundary(
                            child: CustomPaint(
                              painter: RobotFacePainter(
                                animation: _pulseController,
                                themeColor: _getCoreColor(),
                                state: _faceState,
                                aiProcessing: providerState.isAiProcessing ||
                                  providerState.isVoiceListening,
                              ),
                              size: Size(sceneSize * 0.72, sceneSize * 0.88),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                statusLabel,
                style: TextStyle(
                  color: _getCoreColor(),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
              child: Container(
                constraints: const BoxConstraints(minHeight: 58, maxHeight: 72),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0C1722),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _getCoreColor().withValues(alpha: 0.42),
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                        tooltip: providerState.isVoiceListening
                          ? 'Escuchando'
                          : 'Dictar comando',
                        onPressed: providerState.isAiProcessing
                          ? null
                          : _startVoiceCommand,
                      icon: Icon(
                        providerState.isVoiceListening
                          ? Icons.hearing
                          : Icons.mic_none,
                        color: providerState.isVoiceListening
                          ? _getCoreColor()
                          : Colors.white70,
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _inputController,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _handleAIQuery(),
                        decoration: const InputDecoration(
                          hintText: 'Habla o escribe a Aura',
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        style: const TextStyle(color: Colors.white, fontSize: 15),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Enviar comando',
                        onPressed:
                          providerState.isAiProcessing ? null : _handleAIQuery,
                      icon: Icon(Icons.arrow_upward, color: _getCoreColor()),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _triggerNetworkAnalysis() async {
    if (_networkAuditor.recentEventCount == 0) {
      _state.updatePresentation(
        liveConsoleLogs: 'Todavía no hay eventos DNS para analizar.',
      );
      return;
    }

    _state.updatePresentation(
      isAiProcessing: true,
      liveConsoleLogs: 'Aura está analizando la telemetría DNS reciente...',
    );
    try {
      final payload = _networkAuditor.buildTelemetryPayload(limit: 100);
      final response = await _analyzeWithStoredKey(
        'Analiza estos eventos DNS. Distingue eventos bloqueados y permitidos, '
        'y advierte que source_app puede ser uid-unavailable. JSON: $payload',
      );
      if (!mounted) return;
      _state.updatePresentation(liveConsoleLogs: response);
      await _writeSecureLog('Análisis DNS: $response');
      _voiceEngine.speak(response);
    } finally {
      if (mounted) _state.updatePresentation(isAiProcessing: false);
    }
  }

  Widget _buildShieldButton() {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor:
            _shieldActive ? const Color(0xFFEF4444) : const Color(0xFF1E293B),
        foregroundColor: _shieldActive ? Colors.white : const Color(0xFF10B981),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
              color: _shieldActive
                  ? Colors.transparent
                  : const Color(0xFF10B981).withValues(alpha: 0.4)),
        ),
      ),
      onPressed: _securityStatus == "SCANNING" ? null : _toggleNetworkShield,
      child: Text(_shieldActive ? "ESCUDO ACTIVO" : "ACTIVAR ESCUDO",
          style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }
}

class RobotFacePainter extends CustomPainter {
  final Animation<double> animation;
  final Color themeColor;
  final String state;
  final bool aiProcessing;

  RobotFacePainter({
    required this.animation,
    required this.themeColor,
    required this.state,
    required this.aiProcessing,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final pulseValue = animation.value;
    final bool isScanning =
      state == "SCANNING" || state == "scanning_active";
    final bool isThreat =
      state == "THREAT" || state == "threat_mitigation_mode";

    canvas.save();
    if (aiProcessing) {
      canvas.translate(0, math.sin(pulseValue * math.pi * 2) * 5);
    }

    final paint = Paint()
      ..color = themeColor.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final glowPaint = Paint()
      ..color = themeColor.withValues(alpha: 0.12 * (1.0 + pulseValue))
      ..style = PaintingStyle.fill;

    final facePath = Path()
      ..moveTo(size.width * 0.25, size.height * 0.15)
      ..lineTo(size.width * 0.75, size.height * 0.15)
      ..lineTo(size.width * 0.83, size.height * 0.48)
      ..lineTo(size.width * 0.53, size.height * 0.88)
      ..lineTo(size.width * 0.47, size.height * 0.88)
      ..lineTo(size.width * 0.17, size.height * 0.48)
      ..close();

    canvas.drawPath(facePath, glowPaint);
    canvas.drawPath(facePath, paint);
    canvas.drawLine(
      Offset(size.width * 0.38, size.height * 0.23),
      Offset(size.width * 0.62, size.height * 0.23),
      paint,
    );

    if (isScanning) {
      final double scanY =
          size.height * 0.15 + (size.height * 0.70 * pulseValue);
      final scanLine = Paint()
        ..color = themeColor
        ..strokeWidth = 2.5;
      canvas.drawLine(
        Offset(size.width * 0.18, scanY),
        Offset(size.width * 0.82, scanY),
        scanLine,
      );
    }

    final leftEye = Rect.fromLTWH(
      size.width * 0.30,
      size.height * 0.42,
      40,
      10 + (2 * pulseValue),
    );
    final rightEye = Rect.fromLTWH(
      size.width * 0.58,
      size.height * 0.42,
      40,
      10 + (2 * pulseValue),
    );

    paint.style = PaintingStyle.fill;
    canvas.drawOval(leftEye, paint);
    canvas.drawOval(rightEye, paint);

    paint.style = PaintingStyle.stroke;
    final mouthPath = Path();
    final double startX = size.width * 0.42;
    final double endX = size.width * 0.58;
    final double midY = size.height * 0.70;
    mouthPath.moveTo(startX, midY);

    for (double x = startX; x <= endX; x += 4) {
      final double wave = isThreat
          ? math.sin(x + pulseValue * 45) * 10
          : math.sin(x + pulseValue * 15) * (3 + pulseValue * 3);
      mouthPath.lineTo(x, midY + wave);
    }

    canvas.drawPath(mouthPath, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RobotFacePainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.themeColor != themeColor ||
      oldDelegate.state != state ||
      oldDelegate.aiProcessing != aiProcessing;
}
