import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'core/core_call.dart';
import 'screens/splash_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/launcher_screen.dart';
import 'screens/exchange_screen.dart';
import 'screens/pattern_search_screen.dart';
import 'screens/multi_pattern_search_screen.dart';
import 'screens/multi_trading_screen.dart';
import 'screens/asset_prices_screen.dart';
import 'screens/news_screen.dart';
import 'screens/account_screen.dart';
import 'screens/logs_screen.dart';

void main() {
  runApp(const BlackBoxApp());
}

class BlackBoxApp extends StatefulWidget {
  const BlackBoxApp({super.key});

  @override
  State<BlackBoxApp> createState() => _BlackBoxAppState();
}

class _BlackBoxAppState extends State<BlackBoxApp> {
  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final res = await coreCall('get_setting', {'key': 'theme'});
      if (res['ok'] == true) {
        AppTheme.applySaved(res['value']?.toString());
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppTheme.themeNotifier,
      builder: (_, __, ___) => MaterialApp(
        title: 'BLACK BOX',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme(),
        initialRoute: '/',
        routes: {
          '/': (_) => const SplashScreen(),
          '/auth': (_) => const AuthScreen(),
          '/launcher': (_) => const LauncherScreen(),
          '/exchange': (_) => const ExchangeScreen(),
          '/pattern': (_) => const PatternSearchScreen(),
          '/multi_pattern': (_) => const MultiPatternSearchScreen(),
          '/multi_trading': (_) => const MultiTradingScreen(),
          '/asset_prices': (_) => const AssetPricesScreen(),
          '/news': (_) => const NewsScreen(),
          '/account': (_) => const AccountScreen(),
          '/logs': (_) => const LogsScreen(),
        },
      ),
    );
  }
}
