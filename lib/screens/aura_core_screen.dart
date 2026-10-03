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
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _cursorBlink;
  bool _isListening = false;
  bool _isRunning = false;
  int _lastRenderedEventCount = -1;

  @override
  void initState() {
    super.initState();
    _cursorBlink = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
      lowerBound: 0.15,
      upperBound: 1,
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = AgentController.instance;
      controller.bindSecurityState(context.read<AuraStateProvider>());
      controller.initGreeting();
    });
  }

  @override
  void dispose() {
    _cursorBlink.dispose();
    _scrollController.dispose();
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

  void _scrollToLatest(int eventCount) {
    if (eventCount == _lastRenderedEventCount) return;
    _lastRenderedEventCount = eventCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final security = context.watch<AuraStateProvider>();

    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            _TerminalHeader(
              securityLevel: security.securityLevel,
            ),
            const Divider(height: 1, color: Color(0xFF17352B)),
            Expanded(
              child: StreamBuilder<AgentEvent>(
                stream: AgentController.instance.events,
                builder: (context, snapshot) {
                  final events = List<AgentEvent>.of(
                    AgentController.instance.history,
                    growable: false,
                  );
                  _scrollToLatest(events.length);
                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                    itemCount: events.length,
                    itemBuilder: (context, index) =>
                        _SyslogLine(event: events[index]),
                  );
                },
              ),
            ),
            _TerminalInput(
              controller: _inputController,
              cursorAnimation: _cursorBlink,
              isListening: _isListening,
              isRunning: _isRunning,
              onSubmitted: _dispatch,
              onVoice: _captureVoice,
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalHeader extends StatelessWidget {
  const _TerminalHeader({
    required this.securityLevel,
  });

  final AuraSecurityLevel securityLevel;

  @override
  Widget build(BuildContext context) {
    final (status, color) = switch (securityLevel) {
      AuraSecurityLevel.safe => ('LOCAL / READY', AuraTokens.success),
      AuraSecurityLevel.warning => ('LOCAL / REVIEW', AuraTokens.warning),
      AuraSecurityLevel.critical => ('LOCAL / CRITICAL', AuraTokens.danger),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Row(
        children: [
          const Icon(Icons.terminal, color: AuraTokens.accent, size: 19),
          const SizedBox(width: 9),
          const Expanded(
            child: Text(
              'AURA // TACTICAL CONSOLE',
              style: TextStyle(
                color: AuraTokens.success,
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Text(
            status,
            style: TextStyle(
              color: color,
              fontFamily: 'monospace',
              fontSize: 9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyslogLine extends StatelessWidget {
  const _SyslogLine({required this.event});

  final AgentEvent event;

  @override
  Widget build(BuildContext context) {
    final (prefix, color) = switch (event.kind) {
      AgentEventKind.thought => ('[  INF  ] ', AuraTokens.textMuted),
      AgentEventKind.action => ('[  NET  ] ', AuraTokens.accent),
      AgentEventKind.success => ('[  OK   ] ', AuraTokens.success),
      AgentEventKind.warning => ('[  WARN ] ', AuraTokens.warning),
      AgentEventKind.error => ('[  CRIT ] ', AuraTokens.danger),
    };
    final timestamp =
        '${event.ts.hour.toString().padLeft(2, '0')}:'
        '${event.ts.minute.toString().padLeft(2, '0')}:'
        '${event.ts.second.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: SelectableText.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$timestamp ',
              style: const TextStyle(color: AuraTokens.textMuted),
            ),
            TextSpan(
              text: prefix,
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
            TextSpan(
              text: event.message,
              style: TextStyle(color: color),
            ),
          ],
        ),
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.45,
        ),
      ),
    );
  }
}

class _TerminalInput extends StatelessWidget {
  const _TerminalInput({
    required this.controller,
    required this.cursorAnimation,
    required this.isListening,
    required this.isRunning,
    required this.onSubmitted,
    required this.onVoice,
  });

  final TextEditingController controller;
  final Animation<double> cursorAnimation;
  final bool isListening;
  final bool isRunning;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 10, 8),
      decoration: const BoxDecoration(
        color: Colors.black,
        border: Border(top: BorderSide(color: Color(0xFF17352B))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'aura@cyberdefense:~# ',
            style: TextStyle(
              color: AuraTokens.accent,
              fontFamily: 'monospace',
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !isRunning,
              autofocus: true,
              textInputAction: TextInputAction.send,
              onSubmitted: onSubmitted,
              cursorColor: AuraTokens.accent,
              style: const TextStyle(
                color: AuraTokens.success,
                fontFamily: 'monospace',
                fontSize: 12,
              ),
              decoration: const InputDecoration(
                hintText: 'comando o consulta táctica',
                hintStyle: TextStyle(
                  color: AuraTokens.textMuted,
                  fontFamily: 'monospace',
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 9),
              ),
            ),
          ),
          AnimatedBuilder(
            animation: cursorAnimation,
            builder: (context, child) => Opacity(
              opacity: cursorAnimation.value,
              child: child,
            ),
            child: const Text(
              '█',
              style: TextStyle(
                color: AuraTokens.accent,
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 3),
          IconButton(
            tooltip: isListening ? 'Escuchando' : 'Dictar consulta',
            onPressed: isRunning || isListening ? null : onVoice,
            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
            padding: EdgeInsets.zero,
            icon: Icon(
              isListening ? Icons.hearing : Icons.mic_none,
              color: isListening ? AuraTokens.warning : AuraTokens.accent,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }
}
