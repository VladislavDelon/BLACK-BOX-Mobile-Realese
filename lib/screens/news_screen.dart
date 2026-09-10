import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../core/core_call.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  bool _loading = true;
  bool _error = false;
  String _errorText = '';
  String _version = '';
  String _currentVersion = '';
  String _name = '';
  String _body = '';
  String _publishedAt = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final res = await coreCallTimeout('get_news', timeout: const Duration(seconds: 15));
      if (res['ok'] == true) {
        setState(() {
          _version = res['version']?.toString() ?? '';
          _currentVersion = res['current_version']?.toString() ?? '';
          _name = res['name']?.toString() ?? '';
          _body = res['body']?.toString() ?? '';
          _publishedAt = res['published_at']?.toString() ?? '';
        });
      } else {
        setState(() {
          _error = true;
          _errorText = res['error']?.toString() ?? 'Не удалось загрузить новости';
        });
      }
    } catch (e) {
      setState(() {
        _error = true;
        _errorText = e.toString();
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  String _formatDate(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Новости'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _error
              ? _buildError()
              : _buildContent(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, color: AppTheme.muted, size: 48),
            const SizedBox(height: 16),
            Text('Не удалось загрузить новости', style: AppTheme.title()),
            const SizedBox(height: 8),
            Text(_errorText, style: AppTheme.small(), textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _load,
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          color: AppTheme.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
            side: const BorderSide(color: Color(0xFF2A2A2A)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _name.isNotEmpty ? _name : 'Обновление',
                        style: AppTheme.title(color: AppTheme.accent),
                      ),
                    ),
                    if (_version.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('v$_version', style: AppTheme.small(color: AppTheme.accent)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_publishedAt.isNotEmpty)
                  Text('Опубликовано: ${_formatDate(_publishedAt)}', style: AppTheme.small()),
                if (_currentVersion.isNotEmpty)
                  Text('Ваша версия: v$_currentVersion', style: AppTheme.small()),
                const SizedBox(height: 14),
                Text(
                  _body.isNotEmpty ? _body : 'Описание отсутствует.',
                  style: AppTheme.body(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Center(
          child: TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh, color: AppTheme.muted),
            label: const Text('Обновить'),
          ),
        ),
      ],
    );
  }
}
