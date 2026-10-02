import 'dart:async';

import 'package:flutter/material.dart';

import '../ai_brain.dart';
import '../secure_vault.dart';
import '../theme/aura_tokens.dart';
import 'aura_core_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final AuraSecureVault _secureVault;
  late final AuraAIBrain _aiBrain;
  double _loadingProgress = 0;
  String _bootStatusText = 'INICIALIZANDO BÓVEDA SEGURA...';
  bool _bootFailed = false;

  @override
  void initState() {
    super.initState();
    _secureVault = AuraSecureVault();
    _aiBrain = AuraAIBrain(secureVault: _secureVault);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    unawaited(_initializeSystem());
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initializeSystem() async {
    setState(() {
      _bootFailed = false;
      _loadingProgress = 0.12;
      _bootStatusText = 'INICIALIZANDO BÓVEDA SEGURA...';
    });

    try {
      await _secureVault.getOrCreateModelMasterKey();
      if (!mounted) return;
      setState(() {
        _loadingProgress = 0.42;
        _bootStatusText = 'DESCIFRANDO Y VALIDANDO BOSQUE LOCAL...';
      });

      await _aiBrain.preloadModel();
      if (!mounted) return;
      setState(() {
        _loadingProgress = 0.78;
        _bootStatusText = 'BOSQUE LOCAL VALIDADO: 20 ÁRBOLES.';
      });

      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      setState(() {
        _loadingProgress = 0.92;
        _bootStatusText = 'VPN DISPONIBLE; ANDROID REQUIERE CONSENTIMIENTO.';
      });

      await Future<void>.delayed(const Duration(milliseconds: 450));
      if (!mounted) return;
      setState(() {
        _loadingProgress = 1;
        _bootStatusText = 'AURA MOBILE DEFENS ACTIVA.';
      });
      await Future<void>.delayed(const Duration(milliseconds: 350));
      _navigateToCore();
    } on Object {
      if (!mounted) return;
      setState(() {
        _bootFailed = true;
        _bootStatusText = 'FALLO DE INICIALIZACIÓN. REINTENTA EL ARRANQUE.';
      });
    }
  }

  void _navigateToCore() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const AuraCoreScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.fastOutSlowIn,
          ),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuraTokens.bg,
      body: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.035,
              child: GridPaper(
                color: AuraTokens.accent,
                interval: 30,
                divisions: 1,
                subdivisions: 1,
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AuraTokens.s4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        final pulse = _animationController.value;
                        return Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AuraTokens.accent.withValues(
                                alpha: 0.2 + pulse * 0.3,
                              ),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AuraTokens.accent.withValues(
                                  alpha: 0.1 + pulse * 0.25,
                                ),
                                blurRadius: 40 + pulse * 25,
                                spreadRadius: 2 + pulse * 6,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Icon(
                              Icons.shield_moon_rounded,
                              size: 72,
                              color: AuraTokens.accent.withValues(
                                alpha: 0.7 + pulse * 0.3,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: AuraTokens.s8),
                    const Text(
                      'AURA',
                      style: TextStyle(
                        color: AuraTokens.textPrimary,
                        fontSize: 38,
                        fontWeight: FontWeight.w200,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: AuraTokens.s1),
                    const Text(
                      'SOVEREIGN MOBILE DEFENSE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AuraTokens.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: AuraTokens.s8),
                    SizedBox(
                      width: 220,
                      child: Column(
                        children: [
                          LinearProgressIndicator(
                            value: _loadingProgress,
                            minHeight: 2,
                            backgroundColor: AuraTokens.surfaceAlt,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              AuraTokens.accent,
                            ),
                          ),
                          const SizedBox(height: AuraTokens.s3),
                          Text(
                            _bootStatusText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AuraTokens.accent,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                          if (_bootFailed) ...[
                            const SizedBox(height: AuraTokens.s2),
                            IconButton(
                              tooltip: 'Reintentar inicialización',
                              onPressed: _initializeSystem,
                              icon: const Icon(
                                Icons.refresh,
                                color: AuraTokens.warning,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}