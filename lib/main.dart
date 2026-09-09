import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/launcher_screen.dart';
import 'screens/exchange_screen.dart';
import 'screens/pattern_search_screen.dart';
import 'screens/multi_pattern_search_screen.dart';
import 'screens/multi_trading_screen.dart';

void main() {
  runApp(const BlackBoxApp());
}

class BlackBoxApp extends StatelessWidget {
  const BlackBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLACK BOX',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      initialRoute: '/',
      routes: {
        '/': (_) => const SplashScreen(),
        '/auth': (_) => const AuthScreen(),
        '/launcher': (_) => const LauncherScreen(),
        '/exchange': (_) => const ExchangeScreen(),
        '/pattern': (_) => const PatternSearchScreen(),
        '/multi_pattern': (_) => const MultiPatternSearchScreen(),
        '/multi_trading': (_) => const MultiTradingScreen(),
      },
    );
  }
}
