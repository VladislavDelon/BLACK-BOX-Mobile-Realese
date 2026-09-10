import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../core/core_call.dart';
import '../widgets/help_button.dart';

class ExchangeScreen extends StatefulWidget {
  const ExchangeScreen({super.key});

  @override
  State<ExchangeScreen> createState() => _ExchangeScreenState();
}

class _ExchangeScreenState extends State<ExchangeScreen> {
  final _keyController = TextEditingController();
  final _secretController = TextEditingController();
  final _nameController = TextEditingController();

  String _exchange = 'Binance Futures';
  String _status = 'Проверка ядра...';
  double? _balance;
  bool _busy = false;
  bool _saveKeys = true;

  static const _exchanges = ['Binance Futures', 'MEXC'];

  @override
  void initState() {
    super.initState();
    _ping();
  }

  Future<void> _ping() async {
    try {
      final res = await coreCall('ping');
      setState(() {
        _status = res['ok'] == true ? 'Ядро готово' : 'Ошибка ядра';
      });
      await _loadSaved();
    } catch (e) {
      setState(() => _status = 'Ядро не отвечает: $e');
    }
  }

  Future<void> _loadSaved() async {
    try {
      final res = await coreCall('get_active');
      if (res['ok'] == true) {
        final acc = res['account'] as Map<String, dynamic>;
        setState(() {
          _exchange = acc['exchange'] ?? _exchange;
          _nameController.text = acc['name'] ?? '';
          _keyController.text = acc['api_key'] ?? '';
          _secretController.text = acc['api_secret'] ?? '';
        });
      }
    } catch (_) {}
  }

  Future<void> _connect() async {
    final key = _keyController.text.trim();
    final secret = _secretController.text.trim();
    if (key.isEmpty || secret.isEmpty) {
      setState(() => _status = 'Введите API Key и Secret');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Проверка подключения...';
    });
    try {
      final res = await coreCall('test_exchange', {
        'exchange': _exchange,
        'api_key': key,
        'api_secret': secret,
        'testnet': false,
      });
      if (res['ok'] == true) {
        final bal = (res['balance'] as num).toDouble();
        setState(() {
          _balance = bal;
          _status = 'Подключено';
        });
        if (_saveKeys) {
          await coreCall('save_account', {
            'exchange': _exchange,
            'name': _nameController.text.trim(),
            'api_key': key,
            'api_secret': secret,
          });
        }
      } else {
        setState(() => _status = 'Ошибка: ${res['error']}');
      }
    } catch (e) {
      setState(() => _status = 'Ошибка канала: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('BLACK BOX', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: AppTheme.bg,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              color: AppTheme.card,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Подключение биржи',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    HelpButton(
                      title: 'Подключение биржи',
                      text: '1. Выберите биржу.\n'
                          '2. Введите API Key и API Secret.\n'
                          '3. Нажмите «Подключить».\n\n'
                          'Ключи сохраняются только на устройстве (если включена галочка). '
                          'Рекомендуется использовать тестовые ключи при первом знакомстве.',
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _exchange,
                      dropdownColor: AppTheme.card,
                      style: const TextStyle(color: AppTheme.text),
                      items: _exchanges
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setState(() => _exchange = v!),
                      decoration: const InputDecoration(labelText: 'Биржа'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(labelText: 'Название (метка)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _keyController,
                      decoration: const InputDecoration(labelText: 'API Key'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _secretController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'API Secret'),
                    ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: _saveKeys,
                      onChanged: (v) => setState(() => _saveKeys = v ?? true),
                      title: const Text('Сохранить API-ключи локально'),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _busy ? null : _connect,
                        child: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Подключить'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: AppTheme.card,
              child: ListTile(
                title: Text(_status),
                subtitle: _balance != null
                    ? Text('Баланс: ${_balance!.toStringAsFixed(2)} USDT')
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _keyController.dispose();
    _secretController.dispose();
    _nameController.dispose();
    super.dispose();
  }
}
