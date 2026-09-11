import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../core/core_call.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  bool _loading = true;
  String _logs = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await coreCall('get_logs');
      if (mounted) {
        setState(() {
          _logs = res['logs']?.toString() ?? '';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _logs = 'Ошибка загрузки логов: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _clear() async {
    try {
      await coreCall('clear_logs');
    } catch (_) {}
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Логи'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AppTheme.text),
            onPressed: _load,
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, color: AppTheme.text),
            onPressed: _clear,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _logs.isEmpty
                ? Center(
                    child: Text('Логов пока нет', style: AppTheme.small()),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      _logs,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: AppTheme.text,
                      ),
                    ),
                  ),
      ),
    );
  }
}
