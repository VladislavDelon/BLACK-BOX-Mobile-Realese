import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../core/core_call.dart';
import '../services/symbols_service.dart';
import '../widgets/symbol_picker.dart';
import '../widgets/help_button.dart';

class MultiTradingScreen extends StatefulWidget {
  const MultiTradingScreen({super.key});

  @override
  State<MultiTradingScreen> createState() => _MultiTradingScreenState();
}

class _MultiTradingScreenState extends State<MultiTradingScreen> {
  List<String> _symbols = ['BTCUSDT', 'ETHUSDT', 'SOLUSDT', 'DOGEUSDT'];
  String _interval = '1m';
  int _patternLength = 400;
  int _forecastHorizon = 60;
  int _topN = 10;
  double _minSignalThreshold = 7.0;
  double _tradeThreshold = 1.5;
  double _positionSize = 100.0;
  int _leverage = 10;
  String _amountMode = 'fixed';
  String _tpMode = 'signal';
  double _tpPct = 0.0;
  String _slMode = 'signal';
  double _slPct = 0.0;

  bool _busy = false;
  String _status = '';
  Map<String, dynamic>? _result;
  List<String> _allSymbols = [];
  bool _hasAccount = false;

  final _intervals = ['1m', '3m', '5m', '15m', '30m', '1h'];
  final _amountModes = ['fixed', 'percent', 'split'];
  final _tpSlModes = ['signal', 'fixed'];

  @override
  void initState() {
    super.initState();
    _loadSymbols();
    _checkAccount();
  }

  Future<void> _loadSymbols() async {
    final list = await SymbolsService.getSymbols();
    setState(() => _allSymbols = list);
  }

  Future<void> _checkAccount() async {
    final res = await coreCall('get_active');
    setState(() => _hasAccount = res['ok'] == true && res['account'] != null);
  }

  Future<void> _run() async {
    final acc = await coreCall('get_active');
    if (acc['ok'] != true) {
      setState(() => _status = 'Сначала подключите биржу');
      return;
    }

    final account = acc['account'] as Map<String, dynamic>;
    final exchange = account['exchange'] as String;
    final apiKey = account['api_key'] as String;
    final apiSecret = account['api_secret'] as String;
    final testnet = (account['testnet'] as bool?) ?? false;

    if (_symbols.isEmpty) {
      setState(() => _status = 'Выберите монеты');
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Торговый цикл...';
      _result = null;
    });

    try {
      final res = await coreCall('run_trading_cycle', {
        'symbols': _symbols,
        'exchange': exchange,
        'api_key': apiKey,
        'api_secret': apiSecret,
        'testnet': testnet,
        'interval': _interval,
        'pattern_length': _patternLength,
        'forecast_horizon': _forecastHorizon,
        'top_n': _topN,
        'min_signal_threshold': _minSignalThreshold,
        'trade_threshold': _tradeThreshold,
        'position_size': _positionSize,
        'leverage': _leverage,
        'amount_mode': _amountMode,
        'tp_mode': _tpMode,
        'tp_pct': _tpPct,
        'sl_mode': _slMode,
        'sl_pct': _slPct,
      });
      if (res['ok'] == true) {
        setState(() {
          _result = res;
          _status = 'Цикл завершён';
        });
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
    final trades = (_result?['trades'] as List<dynamic>?) ?? [];
    final errors = (_result?['errors'] as List<dynamic>?) ?? [];
    final skipped = (_result?['skipped'] as List<dynamic>?) ?? [];

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Мульти торговля')),
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
                    title: 'Мульти торговля',
                    text: '1. Подключите биржу (меню → Подключение биржи).\n'
                        '2. Выберите монеты и оставьте настройки по умолчанию — прогноз на 1 час.\n'
                        '3. Нажмите «Запустить торговый цикл».\n\n'
                        'Программа проанализирует паттерны и при достижении силы сигнала откроет позицию. '
                        'Стоп-лосс и тейк-профит настраиваются по режиму.',
                  ),
                  const SizedBox(height: 16),
                  if (!_hasAccount)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pushNamed(context, '/exchange').then((_) => _checkAccount()),
                          style: FilledButton.styleFrom(backgroundColor: AppTheme.accent2),
                          child: const Text('Подключить биржу'),
                        ),
                      ),
                    ),
                  MultiSymbolPicker(
                    selected: _symbols,
                    symbols: _allSymbols,
                    onChanged: (v) => setState(() => _symbols = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _interval,
                    dropdownColor: AppTheme.card,
                    style: TextStyle(color: AppTheme.text),
                    decoration: const InputDecoration(labelText: 'Интервал'),
                    items: _intervals
                        .map((i) => DropdownMenuItem(value: i, child: Text(i)))
                        .toList(),
                    onChanged: (v) => setState(() => _interval = v!),
                  ),
                  const SizedBox(height: 12),
                  _intField('Длина паттерна', _patternLength, (v) => _patternLength = v),
                  _intField('Горизонт', _forecastHorizon, (v) => _forecastHorizon = v),
                  _intField('TOP-N', _topN, (v) => _topN = v),
                  _doubleField('Порог сигнала (%)', _minSignalThreshold, (v) => _minSignalThreshold = v),
                  _doubleField('Порог открытия (%)', _tradeThreshold, (v) => _tradeThreshold = v),
                  _doubleField('Размер позиции', _positionSize, (v) => _positionSize = v),
                  _intField('Плечо', _leverage, (v) => _leverage = v),
                  DropdownButtonFormField<String>(
                    value: _amountMode,
                    dropdownColor: AppTheme.card,
                    style: TextStyle(color: AppTheme.text),
                    decoration: const InputDecoration(labelText: 'Режим суммы'),
                    items: {
                      'fixed': 'Фиксированная сумма',
                      'percent': '% от баланса',
                      'split': 'Разделить бюджет',
                    }
                        .entries
                        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                        .toList(),
                    onChanged: (v) => setState(() => _amountMode = v!),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _tpMode,
                          dropdownColor: AppTheme.card,
                          style: TextStyle(color: AppTheme.text),
                          decoration: const InputDecoration(labelText: 'TP режим'),
                          items: _tpSlModes
                              .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                              .toList(),
                          onChanged: (v) => setState(() => _tpMode = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _doubleField('TP %', _tpPct, (v) => _tpPct = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _slMode,
                          dropdownColor: AppTheme.card,
                          style: TextStyle(color: AppTheme.text),
                          decoration: const InputDecoration(labelText: 'SL режим'),
                          items: _tpSlModes
                              .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                              .toList(),
                          onChanged: (v) => setState(() => _slMode = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _doubleField('SL %', _slPct, (v) => _slPct = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _run,
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Text('Запустить торговый цикл'),
                    ),
                  ),
                ],
              ),
            ),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_status, style: AppTheme.body()),
              ),
            if (_result != null)
              Text('Баланс: ${_result?['balance']?.toStringAsFixed(2) ?? '-'} USDT',
                  style: AppTheme.small()),
            if (trades.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Открыты сделки:', style: AppTheme.title(color: AppTheme.up)),
              const SizedBox(height: 12),
              ...trades.map((t) => _tradeCard(t as Map<String, dynamic>))
            ],
            if (skipped.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Пропущено:', style: AppTheme.small()),
              const SizedBox(height: 8),
              ...skipped.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${s['symbol']}: ${s['signal']} ${s['forecast_pct']}%',
                  style: AppTheme.small(color: AppTheme.muted),
                ),
              )),
            ],
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Ошибки:', style: AppTheme.title(color: AppTheme.down)),
              const SizedBox(height: 8),
              ...errors.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('${e['symbol']}: ${e['error']}',
                    style: AppTheme.small(color: AppTheme.down)),
              )),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _tradeCard(Map<String, dynamic> t) {
    final isLong = t['direction'] == 'LONG';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  t['symbol'],
                  style: AppTheme.title(color: AppTheme.accent),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(t['direction'], style: AppTheme.title(color: isLong ? AppTheme.up : AppTheme.down)),
            ],
          ),
          const SizedBox(height: 12),
          Text('qty: ${t['qty']} | плечо: ${t['leverage']}x', style: AppTheme.body()),
          const SizedBox(height: 6),
          Text('TP: ${t['tp_price']} (${t['tp_pct']}%) | SL: ${t['sl_price']} (${t['sl_pct']}%)',
              style: AppTheme.small()),
        ],
      ),
    );
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

  Widget _intField(String label, int value, ValueChanged<int> onChanged) {
    final controller = TextEditingController(text: value.toString());
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        controller: controller,
        onChanged: (s) {
          final v = int.tryParse(s);
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  Widget _doubleField(String label, double value, ValueChanged<double> onChanged) {
    final controller = TextEditingController(text: value.toString());
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(labelText: label),
        controller: controller,
        onChanged: (s) {
          final v = double.tryParse(s.replaceAll(',', '.'));
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}
