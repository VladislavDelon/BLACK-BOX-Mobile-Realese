import 'dart:async';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../core/core_call.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _version = '';
  String _status = 'Загрузка';
  String _dots = '';
  Timer? _dotTimer;

  @override
  void initState() {
    super.initState();
    _startDots();
    _init();
  }

  @override
  void dispose() {
    _dotTimer?.cancel();
    super.dispose();
  }

  void _startDots() {
    _dotTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      setState(() {
        _dots = '.' * ((_dots.length + 1) % 4);
      });
    });
  }

  Future<void> _init() async {
    await Future.delayed(const Duration(milliseconds: 800));
    await _loadVersion();
    await _checkAuth();
  }

  Future<void> _loadVersion() async {
    try {
      final res = await coreCall('get_version');
      setState(() => _version = res['version']?.toString() ?? '1.0.0');
    } catch (e) {
      setState(() => _version = '1.0.0');
    }
  }

  Future<void> _checkAuth() async {
    setState(() => _status = 'Проверка подключения');
    try {
      final res = await coreCall('get_auth_state');
      final registered = res['registered'] == true;
      if (!mounted) return;
      if (registered) {
        Navigator.pushReplacementNamed(context, '/launcher');
      } else {
        Navigator.pushReplacementNamed(context, '/auth');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Ошибка: $e');
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pushReplacementNamed(context, '/auth');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('BLACK BOX', style: AppTheme.header()),
            const SizedBox(height: 12),
            Text(
              'Pattern Analysis System',
              style: AppTheme.title(color: AppTheme.accent),
            ),
            const SizedBox(height: 60),
            Text(
              '$_status$_dots',
              style: AppTheme.small(),
            ),
            const SizedBox(height: 16),
            if (_version.isNotEmpty)
              Text(
                'v$_version',
                style: AppTheme.small(),
              ),
          ],
        ),
      ),
    );
  }
}
