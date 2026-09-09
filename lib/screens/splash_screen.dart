import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
    await _checkUpdate();
    await _checkAuth();
  }

  Future<void> _checkUpdate() async {
    setState(() => _status = 'Проверка обновлений');
    try {
      final res = await coreCallTimeout('check_update', timeout: const Duration(seconds: 7));
      final current = _version;

      if (res['ok'] == true && res['has_update'] == true && res['download_url'] != null) {
        final newVersion = res['new_version']?.toString() ?? 'новая';
        setState(() {
          _version = '$current → v$newVersion';
          _status = 'Доступна $newVersion';
        });
        if (!mounted) return;
        await _handleUpdate(newVersion, res['download_url'].toString());
      } else if (res['ok'] == true) {
        setState(() {
          _version = '$current (актуальная)';
          _status = 'Актуальная';
        });
        await Future.delayed(const Duration(seconds: 1));
      } else {
        setState(() {
          _version = '$current';
          _status = 'Не удалось проверить обновления';
        });
        await Future.delayed(const Duration(seconds: 1));
      }
    } catch (e) {
      setState(() => _status = 'Ошибка проверки обновлений');
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Future<void> _handleUpdate(String newVersion, String url) async {
    if (!mounted) return;
    final go = await _showUpdateDialog(newVersion, url);
    if (go == true && mounted) {
      setState(() => _status = 'Открытие загрузки');
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      setState(() => _status = 'Загрузка началась');
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  Future<bool> _showUpdateDialog(String version, String url) {
    bool autoConfirmed = false;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        // Авто-скачивание через 3 секунды, если пользователь не нажал кнопку.
        Future.delayed(const Duration(seconds: 3), () {
          if (ctx.mounted && !autoConfirmed) {
            autoConfirmed = true;
            Navigator.of(ctx).pop(true);
          }
        });
        return AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text('Доступна новая версия', style: AppTheme.title()),
          content: Text(
            'Версия $version уже выложена.\n\nСкачивание начнётся автоматически через 3 секунды.',
            style: AppTheme.body(),
          ),
          actions: [
            TextButton(
              onPressed: () {
                autoConfirmed = true;
                Navigator.of(ctx).pop(false);
              },
              child: const Text('Позже'),
            ),
            FilledButton(
              onPressed: () {
                autoConfirmed = true;
                Navigator.of(ctx).pop(true);
              },
              child: const Text('Скачать сейчас'),
            ),
          ],
        );
      },
    ).then((v) => v == true || autoConfirmed);
  }

  Future<void> _loadVersion() async {
    try {
      final res = await coreCallTimeout('get_version', timeout: const Duration(seconds: 3));
      setState(() => _version = 'v${res['version']?.toString() ?? '1.0.0'}');
    } catch (e) {
      setState(() => _version = 'v1.0.0');
    }
  }

  Future<void> _checkAuth() async {
    setState(() => _status = 'Проверка подключения');
    try {
      final res = await coreCallTimeout('get_auth_state', timeout: const Duration(seconds: 5));
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
                _version,
                style: AppTheme.small(),
              ),
          ],
        ),
      ),
    );
  }
}
