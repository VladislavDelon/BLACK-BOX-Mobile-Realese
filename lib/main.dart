import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const BlackBoxApp());
}

const _channel = MethodChannel('bb/core');

/// Вызов метода Python-ядра. Возвращает Map, декодированный из JSON.
Future<Map<String, dynamic>> coreCall(String method,
    [Map<String, dynamic> args = const {}]) async {
  final String out = await _channel.invokeMethod<String>(
        method,
        {'argsJson': jsonEncode(args)},
      ) ??
      '{"ok": false, "error": "no result"}';
  return jsonDecode(out) as Map<String, dynamic>;
}

class BlackBoxApp extends StatelessWidget {
  const BlackBoxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BLACK BOX',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2ECC71),
          surface: Color(0xFF1A1A1A),
        ),
        cardColor: const Color(0xFF1A1A1A),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A1A1A),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      home: const ExchangeScreen(),
    );
  }
}

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
      appBar: AppBar(
        title: const Text('BLACK BOX', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFF0F0F0F),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Подключение биржи',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _exchange,
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
                                height: 18, width: 18,
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
}
