import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/aura_state_provider.dart';
import 'screens/splash_screen.dart';
import 'theme/aura_tokens.dart';

void main() {
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuraStateProvider()),
      ],
      child: const AuraApp(),
    ),
  );
}

class AuraApp extends StatelessWidget {
  const AuraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aura Mobile Defens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AuraTokens.bg,
        fontFamily: 'monospace',
      ),
      home: const SplashScreen(),
    );
  }
}