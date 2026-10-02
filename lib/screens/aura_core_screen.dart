import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../agent/agent_controller.dart';
import '../agent/agent_event.dart';
import '../providers/aura_state_provider.dart';
import '../theme/aura_tokens.dart';

class AuraCoreScreen extends StatefulWidget {
  const AuraCoreScreen({super.key});

  @override
  State<AuraCoreScreen> createState() => _AuraCoreScreenState();
}

class _AuraCoreScreenState extends State<AuraCoreScreen>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _voiceChannel =
      MethodChannel('com.ciberdefensa.aura/voice');

  final TextEditingController _inputController = TextEditingController();
  late final AnimationController _floatController;
  bool _isListening = false;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    AgentController.instance.bindSecurityState(
      context.read<AuraStateProvider>(),
    );
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _floatController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _dispatch(String text) async {
    final instruction = text.trim();
    if (instruction.isEmpty || _isRunning) return;
    _inputController.clear();
    setState(() => _isRunning = true);
    try {
      await AgentController.instance.run(instruction);
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  Future<void> _captureVoice() async {
    if (_isListening || _isRunning) return;
    setState(() => _isListening = true);
    try {
      final transcript = await _voiceChannel.invokeMethod<String>(
        'startListening',
      );
      if (!mounted || transcript == null || transcript.trim().isEmpty) return;
      _inputController.text = transcript.trim();
      await _dispatch(transcript);
    } on PlatformException catch (error) {
      if (mounted) {
        context.read<AuraStateProvider>().setSecurityLevel(
              AuraSecurityLevel.warning,
            );
        AgentController.instance.reportError(
          error.message ?? 'No se pudo capturar el comando de voz.',
        );
      }
    } on MissingPluginException {
      if (mounted) {
        context.read<AuraStateProvider>().setSecurityLevel(
              AuraSecurityLevel.warning,
            );
        AgentController.instance.reportError(
          'El reconocimiento de voz no está disponible.',
        );
      }
    } finally {
      if (mounted) setState(() => _isListening = false);
    }
  }

  Color _avatarColor(AuraSecurityLevel level) => switch (level) {
        AuraSecurityLevel.safe => AuraTokens.accent,
        AuraSecurityLevel.warning => AuraTokens.warning,
        AuraSecurityLevel.critical => AuraTokens.danger,
      };

  @override
  Widget build(BuildContext context) {
    final security = context.watch<AuraStateProvider>();
    final avatarColor = _avatarColor(security.securityLevel);

    return Scaffold(
      backgroundColor: AuraTokens.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AuraTokens.s4),
          child: Column(
            children: [
              Expanded(
                flex: 52,
                child: _AvatarStage(
                  animation: _floatController,
                  color: avatarColor,
                  security: security.securityLevel,
                  isProcessing: _isRunning || security.isAiProcessing,
                ),
              ),
              const SizedBox(height: AuraTokens.s3),
              Expanded(
                flex: 48,
                child: _AgentConsole(
                  controller: AgentController.instance,
                  textController: _inputController,
                  isListening: _isListening,
                  isRunning: _isRunning,
                  onSubmit: _dispatch,
                  onVoice: _captureVoice,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarStage extends StatelessWidget {
  const _AvatarStage({
    required this.animation,
    required this.color,
    required this.security,
    required this.isProcessing,
  });

  final Animation<double> animation;
  final Color color;
  final AuraSecurityLevel security;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    final stateLabel = switch (security) {
      AuraSecurityLevel.safe => 'NÚCLEO ESTABLE',
      AuraSecurityLevel.warning => 'ATENCIÓN REQUERIDA',
      AuraSecurityLevel.critical => 'MITIGACIÓN ACTIVA',
    };

    return Column(
      children: [
        Row(
          children: [
            Icon(Icons.radar, color: color, size: 18),
            const SizedBox(width: AuraTokens.s2),
            Text(
              'AURA / DEFENSA LOCAL',
              style: TextStyle(
                color: AuraTokens.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Text(
              stateLabel,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = math.min(
                math.min(constraints.maxWidth * 0.86, constraints.maxHeight * 0.9),
                300.0,
              );
              return Center(
                child: AnimatedBuilder(
                  animation: animation,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(0, math.sin(animation.value * math.pi) * 5),
                    child: child,
                  ),
                  child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.12),
                          blurRadius: 48,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: CustomPaint(
                      painter: _AuraAvatarPainter(
                        animation: animation,
                        color: color,
                        isProcessing: isProcessing,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AgentConsole extends StatelessWidget {
  const _AgentConsole({
    required this.controller,
    required this.textController,
    required this.isListening,
    required this.isRunning,
    required this.onSubmit,
    required this.onVoice,
  });

  final AgentController controller;
  final TextEditingController textController;
  final bool isListening;
  final bool isRunning;
  final ValueChanged<String> onSubmit;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AuraTokens.surface,
        borderRadius: BorderRadius.circular(AuraTokens.rLg),
        border: Border.all(color: AuraTokens.surfaceAlt, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: AuraTokens.accent.withValues(alpha: 0.06),
            blurRadius: 24,
          ),
        ],
      ),
      padding: const EdgeInsets.all(AuraTokens.s3),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.terminal, color: AuraTokens.accent, size: 18),
              const SizedBox(width: AuraTokens.s2),
              const Text(
                'CONSOLA TÁCTICA',
                style: TextStyle(
                  color: AuraTokens.textPrimary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: isRunning ? AuraTokens.warning : AuraTokens.success,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AuraTokens.s1),
              Text(
                isRunning ? 'PROCESANDO' : 'EN LÍNEA',
                style: const TextStyle(
                  color: AuraTokens.textMuted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AuraTokens.s2),
          Expanded(
            child: StreamBuilder<AgentEvent>(
              stream: controller.events,
              builder: (context, snapshot) {
                final events = controller.history.reversed.toList(
                  growable: false,
                );
                if (events.isEmpty) {
                  return Center(
                    child: Text(
                      snapshot.connectionState == ConnectionState.waiting
                          ? 'Canal agéntico preparado.'
                          : 'Esperando una instrucción local.',
                      style: const TextStyle(
                        color: AuraTokens.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  itemCount: events.length,
                  itemBuilder: (context, index) => _EventBubble(
                    event: events[index],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: AuraTokens.s2),
          Container(
            decoration: BoxDecoration(
              color: AuraTokens.bg,
              borderRadius: BorderRadius.circular(AuraTokens.rMd),
              border: Border.all(color: AuraTokens.surfaceAlt),
            ),
            padding: const EdgeInsets.symmetric(horizontal: AuraTokens.s1),
            child: Row(
              children: [
                IconButton(
                  tooltip: isListening ? 'Escuchando' : 'Dictar instrucción',
                  onPressed: isRunning ? null : onVoice,
                  icon: Icon(
                    isListening ? Icons.hearing : Icons.mic_none,
                    color: isListening ? AuraTokens.warning : AuraTokens.accent,
                    size: 20,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: textController,
                    enabled: !isRunning,
                    textInputAction: TextInputAction.send,
                    onSubmitted: onSubmit,
                    style: const TextStyle(
                      color: AuraTokens.textPrimary,
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Orden para Aura…',
                      hintStyle: TextStyle(color: AuraTokens.textMuted),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Enviar instrucción',
                  onPressed: isRunning
                      ? null
                      : () => onSubmit(textController.text),
                  icon: const Icon(
                    Icons.arrow_upward,
                    color: AuraTokens.accent,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventBubble extends StatelessWidget {
  const _EventBubble({required this.event});

  final AgentEvent event;

  @override
  Widget build(BuildContext context) {
    final color = switch (event.kind) {
      AgentEventKind.thought => AuraTokens.textMuted,
      AgentEventKind.action => AuraTokens.accent,
      AgentEventKind.success => AuraTokens.success,
      AgentEventKind.warning => AuraTokens.warning,
      AgentEventKind.error => AuraTokens.danger,
    };
    final icon = switch (event.kind) {
      AgentEventKind.thought => Icons.psychology_alt_outlined,
      AgentEventKind.action => Icons.bolt,
      AgentEventKind.success => Icons.verified_outlined,
      AgentEventKind.warning => Icons.warning_amber_rounded,
      AgentEventKind.error => Icons.error_outline,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: AuraTokens.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: AuraTokens.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.message,
                  style: TextStyle(color: color, fontSize: 11, height: 1.35),
                ),
                const SizedBox(height: 2),
                Text(
                  '${event.ts.hour.toString().padLeft(2, '0')}:'
                  '${event.ts.minute.toString().padLeft(2, '0')}:'
                  '${event.ts.second.toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: AuraTokens.textMuted,
                    fontSize: 8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AuraAvatarPainter extends CustomPainter {
  _AuraAvatarPainter({
    required this.animation,
    required this.color,
    required this.isProcessing,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final Color color;
  final bool isProcessing;

  @override
  void paint(Canvas canvas, Size size) {
    final pulse = animation.value;
    final face = Path()
      ..moveTo(size.width * 0.27, size.height * 0.16)
      ..lineTo(size.width * 0.73, size.height * 0.16)
      ..lineTo(size.width * 0.84, size.height * 0.47)
      ..lineTo(size.width * 0.55, size.height * 0.82)
      ..lineTo(size.width * 0.45, size.height * 0.82)
      ..lineTo(size.width * 0.16, size.height * 0.47)
      ..close();

    canvas.save();
    if (isProcessing) {
      canvas.translate(0, math.sin(pulse * math.pi * 2) * 2);
    }
    canvas.drawPath(
      face,
      Paint()
        ..color = color.withValues(alpha: 0.09 + pulse * 0.04)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawPath(
      face,
      Paint()
        ..color = color.withValues(alpha: 0.64)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    final eyePaint = Paint()
      ..color = color.withValues(alpha: 0.82 + pulse * 0.16)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.31,
          size.height * 0.42,
          size.width * 0.15,
          size.height * 0.035,
        ),
        Radius.circular(size.height * 0.02),
      ),
      eyePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.54,
          size.height * 0.42,
          size.width * 0.15,
          size.height * 0.035,
        ),
        Radius.circular(size.height * 0.02),
      ),
      eyePaint,
    );
    final mouth = Path()
      ..moveTo(size.width * 0.4, size.height * 0.65)
      ..quadraticBezierTo(
        size.width * 0.5,
        size.height * (0.67 + pulse * 0.025),
        size.width * 0.6,
        size.height * 0.65,
      );
    canvas.drawPath(
      mouth,
      Paint()
        ..color = color.withValues(alpha: 0.76)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AuraAvatarPainter oldDelegate) =>
      oldDelegate.animation != animation ||
      oldDelegate.color != color ||
      oldDelegate.isProcessing != isProcessing;
}

class AuraHolographicHud extends StatelessWidget {
  const AuraHolographicHud({
    required this.state,
    required this.tunnelActive,
    required this.accentColor,
    super.key,
  });

  final AuraStateProvider state;
  final bool tunnelActive;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AuraTokens.rSm),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(AuraTokens.s2),
          decoration: BoxDecoration(
            color: AuraTokens.surface.withValues(alpha: 0.78),
            border: Border.all(color: AuraTokens.surfaceAlt),
            borderRadius: BorderRadius.circular(AuraTokens.rSm),
          ),
          child: Row(
            children: [
              Expanded(child: _hudValue('TUN', _formatBytes(state.tunnelBytesProcessed))),
              Expanded(child: _hudValue('BOSQUE', '${state.localForestEvaluations}')),
              Expanded(
                child: _hudValue(
                  'DoH/DoT',
                  tunnelActive ? '${state.encryptedDnsBlocks} BLOQUEOS' : 'INACTIVO',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hudValue(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AuraTokens.textMuted, fontSize: 8)),
          Text(value, style: TextStyle(color: accentColor, fontSize: 10)),
        ],
      );

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}