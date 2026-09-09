import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_theme.dart';
import '../core/core_call.dart';
import 'module_placeholder_screen.dart';

class LauncherScreen extends StatefulWidget {
  const LauncherScreen({super.key});

  @override
  State<LauncherScreen> createState() => _LauncherScreenState();
}

class _LauncherScreenState extends State<LauncherScreen> {
  Map<String, dynamic>? _user;
  String _version = '';

  final List<_MenuCard> _cards = [
    _MenuCard(
      'Поиск по паттернам',
      'Ищет в истории моменты, похожие на текущий график, и показывает, что было дальше.',
      AppTheme.accent,
      'pattern',
    ),
    _MenuCard(
      'Мульти поиск по паттернам',
      'Тот же поиск сразу по нескольким монетам: цена, прогноз, процент сделки.',
      AppTheme.accent2,
      'multi_pattern',
    ),
    _MenuCard(
      'Мульти торговля',
      'Автоматическая торговля по сигналам паттернов сразу по нескольким монетам.',
      AppTheme.accent,
      'multi_trading',
    ),
    _MenuCard(
      'Стоимость валют',
      'Актуальная цена монеты на разных биржах в реальном времени.',
      AppTheme.accent2,
      'asset_prices',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final reg = await coreCall('load_registration');
      final ver = await coreCall('get_version');
      if (mounted) {
        setState(() {
          _user = reg['registration'] as Map<String, dynamic>?;
          _version = ver['version']?.toString() ?? '';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _version = '1.0.0');
    }
  }

  Future<void> _logout() async {
    try {
      await coreCall('logout');
    } catch (_) {}
    if (mounted) Navigator.pushReplacementNamed(context, '/auth');
  }

  void _openModule(String id) {
    final routes = {
      'pattern': '/pattern',
      'multi_pattern': '/multi_pattern',
      'multi_trading': '/multi_trading',
      'asset_prices': '/asset_prices',
    };
    final route = routes[id];
    if (route != null) {
      Navigator.pushNamed(context, route);
      return;
    }
    final titles = {
      'pattern': 'Поиск по паттернам',
      'multi_pattern': 'Мульти поиск по паттернам',
      'multi_trading': 'Мульти торговля',
      'asset_prices': 'Стоимость валют',
    };
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ModulePlaceholderScreen(
          moduleId: id,
          title: titles[id] ?? 'Модуль',
        ),
      ),
    );
  }

  void _openExchange() {
    Navigator.pushNamed(context, '/exchange');
  }

  Future<void> _checkUpdate() async {
    try {
      final res = await coreCallTimeout('check_update', timeout: const Duration(seconds: 10));
      if (res['ok'] != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось проверить обновления')),
          );
        }
        return;
      }
      if (res['has_update'] == true) {
        final version = res['new_version']?.toString() ?? 'новая';
        final url = res['download_url']?.toString() ?? '';
        if (mounted) {
          final go = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppTheme.card,
              title: Text('Доступно обновление', style: AppTheme.title()),
              content: Text(
                'Версия $version\n\nНачать скачивание?',
                style: AppTheme.body(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Позже'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Скачать'),
                ),
              ],
            ),
          );
          if (go == true && url.isNotEmpty) {
            final uri = Uri.parse(url);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Актуальная версия')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка проверки обновления: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('BLACK BOX'),
        actions: [
          IconButton(
            icon: const Icon(Icons.update, color: AppTheme.text),
            onPressed: _checkUpdate,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: AppTheme.text),
            onSelected: (value) {
              if (value == 'logout') _logout();
              if (value == 'exchange') _openExchange();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'exchange', child: Text('Подключение биржи')),
              const PopupMenuItem(value: 'logout', child: Text('Выйти')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (_user != null)
              Card(
                color: AppTheme.card,
                child: ListTile(
                  title: Text(_user?['name']?.toString() ?? '',
                      style: AppTheme.title(color: AppTheme.accent)),
                  subtitle: Text('Авторизован', style: AppTheme.small()),
                  trailing: TextButton(
                    onPressed: _logout,
                    child: const Text('Выйти'),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Text('Выберите, что запустить', style: AppTheme.small()),
            const SizedBox(height: 14),
            ..._cards.map((c) => _buildCard(c)),
            const SizedBox(height: 24),
            if (_version.isNotEmpty)
              Center(
                child: Text('v$_version', style: AppTheme.small()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(_MenuCard card) {
    return GestureDetector(
      onTap: () => _openModule(card.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
          border: Border.all(color: const Color(0xFF2A2A2A)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 6,
              height: 70,
              decoration: BoxDecoration(
                color: card.color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(card.title, style: AppTheme.title()),
                  const SizedBox(height: 6),
                  Text(card.desc, style: AppTheme.small()),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.muted),
          ],
        ),
      ),
    );
  }
}

class _MenuCard {
  final String title;
  final String desc;
  final Color color;
  final String id;
  _MenuCard(this.title, this.desc, this.color, this.id);
}
