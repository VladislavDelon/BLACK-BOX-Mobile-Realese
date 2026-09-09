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

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  String _version = '';
  String _status = 'Загрузка';
  String _dots = '';
  Timer? _dotTimer;

  late final AnimationController _logoController;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _logoController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );
    _startDots();
    _logoController.forward();
    _init();
  }

  @override
  void dispose() {
    _dotTimer?.cancel();
    _logoController.dispose();
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
    await Future.delayed(const Duration(milliseconds: 1200));
    await _loadVersion();
    await _checkUpdate();
    if (!mounted) return;
    await _checkAuth();
  }

  Future<void> _checkUpdate() async {
    setState(() => _status = 'Проверка обновлений');
    try {
      final res = await coreCallTimeout('check_update', timeout: const Duration(seconds: 12));
      final current = res['current_version']?.toString() ?? _version;

      if (res['ok'] != true) {
        setState(() {
          _version = 'v$current';
          _status = 'Не удалось проверить обновления';
        });
        await Future.delayed(const Duration(seconds: 1));
        return;
      }

      if (res['has_update'] == true) {
        final newVersion = res['new_version']?.toString() ?? 'новая';
        final url = res['download_url']?.toString() ?? '';
        setState(() {
          _version = 'v$current → v$newVersion';
          _status = 'Доступна $newVersion';
        });
        if (url.isNotEmpty) {
          await _startDownload(newVersion, url);
        } else {
          setState(() => _status = 'Нет ссылки на обновление');
          await Future.delayed(const Duration(seconds: 2));
        }
      } else {
        setState(() {
          _version = 'v$current (актуальная)';
          _status = 'Актуальная';
        });
        await Future.delayed(const Duration(seconds: 1));
      }
    } catch (e) {
      setState(() => _status = 'Ошибка проверки обновлений');
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Future<void> _startDownload(String newVersion, String url) async {
    if (!mounted) return;
    final shouldDownload = await _showUpdateSheet(newVersion, url);
    if (shouldDownload == true && mounted) {
      setState(() => _status = 'Начинается скачивание v$newVersion');
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      setState(() => _status = 'Скачивание открыто в браузере');
      await Future.delayed(const Duration(seconds: 2));
    } else if (shouldDownload == false) {
      setState(() => _status = 'Обновление отложено');
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Future<bool?> _showUpdateSheet(String version, String url) {
    bool autoConfirmed = false;
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        Future.delayed(const Duration(seconds: 1), () {
          if (ctx.mounted && !autoConfirmed) {
            autoConfirmed = true;
            Navigator.of(ctx).pop(true);
          }
        });
        return AlertDialog(
          backgroundColor: AppTheme.card,
          title: Text('Доступна v$version', style: AppTheme.title()),
          content: Text(
            'Новая версия уже готова.\n\nСкачивание начнётся автоматически через 1 секунду.',
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
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 2),
              FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Image.asset(
                    'assets/logo.png',
                    width: 160,
                    height: 160,
                    fit: BoxFit.contain,
                    errorBuilder: (c, e, s) => const Icon(
                      Icons.analytics,
                      size: 120,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text('BLACK BOX', style: AppTheme.header()),
              const Spacer(flex: 1),
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
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}
