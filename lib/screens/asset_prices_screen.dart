import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../core/core_call.dart';
import '../services/symbols_service.dart';
import '../widgets/symbol_picker.dart';
import '../widgets/help_button.dart';

class AssetPricesScreen extends StatefulWidget {
  const AssetPricesScreen({super.key});

  @override
  State<AssetPricesScreen> createState() => _AssetPricesScreenState();
}

class _AssetPricesScreenState extends State<AssetPricesScreen> {
  String _symbol = 'BTC';
  String _quote = 'USDT';
  bool _busy = false;
  String _status = '';
  List<Map<String, dynamic>> _prices = [];
  List<String> _symbols = [];

  final _quotes = ['USDT', 'BTC', 'ETH'];

  @override
  void initState() {
    super.initState();
    _loadSymbols();
  }

  Future<void> _loadSymbols() async {
    final list = await SymbolsService.getSymbols();
    final bases = list.map((s) {
      if (s.endsWith('USDT')) return s.substring(0, s.length - 4);
      if (s.endsWith('BTC')) return s.substring(0, s.length - 3);
      if (s.endsWith('ETH')) return s.substring(0, s.length - 3);
      return s;
    }).toSet().toList();
    setState(() => _symbols = bases);
  }

  Future<void> _load() async {
    final base = _symbol.trim().toUpperCase();
    final quote = _quote.toUpperCase();
    if (base.isEmpty) {
      setState(() => _status = 'Введите базовую монету');
      return;
    }
    setState(() {
      _busy = true;
      _status = '';
      _prices = [];
    });

    try {
      final res = await coreCall('get_all_prices', {'base': base, 'quote': quote});
      if (res['ok'] == true) {
        setState(() {
          _prices = (res['prices'] as List<dynamic>)
              .map((p) => p as Map<String, dynamic>)
              .toList();
        });
      } else {
        setState(() => _status = 'Ошибка: ${res['error']}');
      }
    } catch (e) {
      setState(() => _status = 'Ошибка: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Стоимость валют')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Настройки', style: AppTheme.title()),
                  const SizedBox(height: 8),
                  HelpButton(
                    title: 'Стоимость валют',
                    text: '1. Выберите базовую монету (например, BTC).\n'
                        '2. Выберите котировку (USDT, BTC или ETH).\n'
                        '3. Нажмите «Получить цены».\n\n'
                        'Программа запросит цены сразу с нескольких бирж и покажет разброс. '
                        'Если биржа не отвечает, будет написано «Временно данных нет».',
                  ),
                  const SizedBox(height: 16),
                  SymbolDropdownField(
                    label: 'Монета',
                    value: _symbol,
                    symbols: _symbols,
                    onSelected: (s) => setState(() => _symbol = s),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _quote,
                    dropdownColor: AppTheme.card,
                    style: TextStyle(color: AppTheme.text),
                    decoration: const InputDecoration(labelText: 'Котировка'),
                    items: _quotes
                        .map((q) => DropdownMenuItem(value: q, child: Text(q)))
                        .toList(),
                    onChanged: (v) => setState(() => _quote = v!),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _load,
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Text('Получить цены'),
                    ),
                  ),
                ],
              ),
            ),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_status, style: AppTheme.body(color: AppTheme.down)),
              ),
            if (_prices.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Результаты:', style: AppTheme.title()),
              const SizedBox(height: 12),
            ],
            ..._prices.map(_priceCard),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _priceCard(Map<String, dynamic> p) {
    final ok = p['ok'] == true;
    final exchange = p['exchange'] ?? '-';
    final market = p['market'] ?? '';
    final last = (p['price'] as num?)?.toDouble() ?? 0.0;
    final chg = (p['change_pct'] as num?)?.toDouble() ?? 0.0;
    final changeColor = chg >= 0 ? AppTheme.up : AppTheme.down;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ok
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('$exchange $market', style: AppTheme.title(color: AppTheme.accent)),
                    Text('${p['symbol']}', style: AppTheme.small()),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Цена', style: AppTheme.small()),
                    Text(_fmtPrice(last), style: AppTheme.title()),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Изменение 24ч', style: AppTheme.small()),
                    Text('${chg.toStringAsFixed(2)}%', style: AppTheme.body(color: changeColor)),
                  ],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$exchange $market', style: AppTheme.title(color: AppTheme.accent)),
                const SizedBox(height: 8),
                Text('Временно данных нет', style: AppTheme.body(color: AppTheme.muted)),
              ],
            ),
    );
  }

  String _fmtPrice(double x) {
    if (x >= 10000) return x.toStringAsFixed(2);
    if (x >= 100) return x.toStringAsFixed(4);
    if (x >= 1) return x.toStringAsFixed(6);
    return x.toStringAsFixed(8).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(AppTheme.cornerRadius),
      ),
      child: child,
    );
  }
}
