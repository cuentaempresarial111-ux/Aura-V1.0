import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math' as math;
import 'security_engine.dart';
import 'voice_engine.dart';
import 'ai_brain.dart';
import 'radar_waves.dart';
import 'secure_vault.dart';
import 'network_auditor.dart';

void main() => runApp(const AuraApp());

class AuraApp extends StatelessWidget {
  const AuraApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aura Cyberdefense',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF020617),
      ),
      home: const AuraCoreScreen(),
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
  late AnimationController _pulseController;
  late StreamSubscription<Map<String, dynamic>> _integritySubscription;
  final AuraSecurityEngine _securityEngine = AuraSecurityEngine();
  final AuraVoiceEngine _voiceEngine = AuraVoiceEngine();
  final AuraAIBrain _aiBrain = AuraAIBrain();
  final AuraSecureVault _secureVault = AuraSecureVault();
  final AuraNetworkAuditor _networkAuditor = AuraNetworkAuditor();
  final TextEditingController _inputController = TextEditingController();

  String _securityStatus = "SECURE";
  String _liveConsoleLogs = "SISTEMA AURA: Núcleo defensivo activo e íntegro.";
  bool _shieldActive = false;
  bool _aiProcessing = false;
  String? _lastRecordedIntegrityLog;

  String get _faceState =>
      _shieldActive || _securityStatus == "THREAT" ? "THREAT" : _securityStatus;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _integritySubscription =
        _securityEngine.monitorDeviceIntegrity().listen((event) {
      if (!mounted || _securityStatus == "SCANNING") return;

      final level = event["level"] as SystemThreatLevel;
      final logs = event["logs"] as String;
      setState(() {
        _liveConsoleLogs = logs;
        _securityStatus = level == SystemThreatLevel.critical
            ? "THREAT"
            : level == SystemThreatLevel.warning
                ? "WARNING"
                : "SECURE";
      });

      if (level != SystemThreatLevel.secure &&
          logs != _lastRecordedIntegrityLog) {
        _lastRecordedIntegrityLog = logs;
        _writeSecureLog(logs);
      }
      if (level == SystemThreatLevel.critical) {
        _voiceEngine.speak("Alerta crítica de integridad detectada.");
      }
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _integritySubscription.cancel();
    _voiceEngine.stop();
    _inputController.dispose();
    unawaited(_networkAuditor.dispose());
    super.dispose();
  }

  Color _getCoreColor() {
    if (_securityStatus == "SCANNING") return const Color(0xFF06B6D4);
    if (_securityStatus == "THREAT" || _shieldActive)
      return const Color(0xFFEF4444);
    if (_securityStatus == "WARNING") return const Color(0xFFF59E0B);
    return const Color(0xFF10B981);
  }

  void _triggerLocalScan() async {
    setState(() {
      _securityStatus = "SCANNING";
      _aiProcessing = true;
      _liveConsoleLogs =
          "INICIANDO AUDITORÍA INTERNA: Analizando firmas criptográficas y telemetría local...";
    });
    try {
      _voiceEngine.speak("Iniciando auditoría interna del sistema.");
      final response = await _analyzeWithStoredKey(
        'EjecutaEscaneoDispositivo ahora y resume únicamente los hallazgos devueltos por la telemetría.',
      );
      if (!mounted) return;

      setState(() {
        _securityStatus = "WARNING";
        _liveConsoleLogs = response;
      });

      await _writeSecureLog('Escaneo: $response');
      _voiceEngine.speak(response);
    } finally {
      if (mounted) setState(() => _aiProcessing = false);
    }
  }

  void _handleAIQuery() async {
    final query = _inputController.text.trim();
    if (query.isEmpty) return;

    _inputController.clear();
    setState(() {
      _aiProcessing = true;
      _liveConsoleLogs = "Aura procesando consulta analítica...";
    });

    try {
      final response = await _analyzeWithStoredKey(query);
      if (!mounted) return;

      setState(() {
        _liveConsoleLogs = response;
      });
      await _writeSecureLog('Consulta: $query\nRespuesta: $response');
      _voiceEngine.speak(response);
    } finally {
      if (mounted) setState(() => _aiProcessing = false);
    }
  }

  Future<String> _analyzeWithStoredKey(String prompt) async {
    var response = await _aiBrain.analyzeCyberThreat(prompt);
    if (!response.startsWith('CONFIGURACIÓN REQUERIDA:')) return response;

    final apiKey = await _requestGeminiApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      return 'Consulta cancelada: no se configuró la clave de Gemini.';
    }

    try {
      await _aiBrain.saveApiKey(apiKey);
    } catch (_) {
      return 'No se pudo guardar la clave de Gemini en el almacenamiento seguro.';
    }
    response = await _aiBrain.analyzeCyberThreat(prompt);
    return response;
  }

  Future<String?> _requestGeminiApiKey() async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Configurar Gemini'),
          content: TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'API key',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Guardar cifrada'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _toggleNetworkShield() async {
    final requestedState = !_shieldActive;
    setState(() {
      _securityStatus = "SCANNING";
      _liveConsoleLogs = requestedState
          ? "Solicitando autorización y arranque del escudo..."
          : "Deteniendo el escudo...";
    });

    try {
      final active = await _aiBrain.setShieldActive(requestedState);
      if (!mounted) return;
      setState(() {
        if (active) _shieldActive = requestedState;
        _securityStatus = active ? "SECURE" : "THREAT";
        _liveConsoleLogs = !active
            ? "No se pudo cambiar el estado del escudo."
            : requestedState
                ? "Escudo VPN activo."
                : "Escudo detenido.";
      });
      await _writeSecureLog(_liveConsoleLogs);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _securityStatus = "THREAT";
        _liveConsoleLogs = "No se pudo cambiar el estado del escudo.";
      });
      await _writeSecureLog('Error de escudo: $error');
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
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'AURA AI • SISTEMA DE CIBERDEFENSA',
                style: TextStyle(
                    letterSpacing: 3,
                    fontWeight: FontWeight.bold,
                    color: _getCoreColor().withValues(alpha: 0.9),
                    fontSize: 13),
              ),
            ),
            Expanded(
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_securityStatus == "SCANNING")
                      RepaintBoundary(
                        child: AuraRadarWaves(
                          animation: _pulseController,
                          themeColor: _getCoreColor(),
                        ),
                      ),
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: RobotFacePainter(
                          animation: _pulseController,
                          themeColor: _getCoreColor(),
                          state: _faceState,
                          aiProcessing: _aiProcessing,
                        ),
                        size: const Size(290, 350),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _getCoreColor().withValues(alpha: 0.15)),
                ),
                child: Text(
                  _liveConsoleLogs,
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            // Consola de entrada de texto interactiva para hablar con Aura
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      decoration: const InputDecoration(
                        hintText: "Consulta de ciberdefensa...",
                        hintStyle:
                            TextStyle(fontSize: 12, color: Colors.white38),
                        border: InputBorder.none,
                      ),
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.send, color: _getCoreColor()),
                    onPressed: _handleAIQuery,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _getCoreColor().withValues(alpha: 0.15),
                      width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildActionButton(
                        "ESCANEAR", _triggerLocalScan, const Color(0xFF06B6D4)),
                    IconButton(
                      tooltip: 'Analizar eventos DNS recientes',
                      icon: Icon(Icons.analytics_outlined,
                          color: _getCoreColor()),
                      onPressed: _triggerNetworkAnalysis,
                    ),
                    _buildShieldButton(),
                  ],
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
      String label, VoidCallback action, Color buttonColor) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: buttonColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: buttonColor.withValues(alpha: 0.4)),
        ),
      ),
      onPressed: _securityStatus == "SCANNING" ? null : action,
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  void _triggerNetworkAnalysis() async {
    if (_networkAuditor.recentEventCount == 0) {
      setState(() => _liveConsoleLogs = 'Todavía no hay eventos DNS para analizar.');
      return;
    }

    setState(() {
      _aiProcessing = true;
      _liveConsoleLogs = 'Aura está analizando la telemetría DNS reciente...';
    });
    try {
      final payload = _networkAuditor.buildTelemetryPayload(limit: 100);
      final response = await _analyzeWithStoredKey(
        'Analiza estos eventos DNS. Distingue eventos bloqueados y permitidos, '
        'y advierte que source_app puede ser uid-unavailable. JSON: $payload',
      );
      if (!mounted) return;
      setState(() => _liveConsoleLogs = response);
      await _writeSecureLog('Análisis DNS: $response');
      _voiceEngine.speak(response);
    } finally {
      if (mounted) setState(() => _aiProcessing = false);
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
    final bool isScanning = state == "SCANNING";
    final bool isThreat = state == "THREAT";

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
