import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../core/core_call.dart';
import '../services/symbols_service.dart';
import '../widgets/symbol_picker.dart';
import '../widgets/help_button.dart';
import 'signal_chart_screen.dart';
import 'signal_movement_screen.dart';

class PatternSearchScreen extends StatefulWidget {
  const PatternSearchScreen({super.key});

  @override
  State<PatternSearchScreen> createState() => _PatternSearchScreenState();
}

class _PatternSearchScreenState extends State<PatternSearchScreen> {
  String _symbol = 'SOLUSDT';
  String _interval = '1m (1 минута)';
  int _patternLength = 400;
  int _forecastHorizon = 60;
  int _topN = 10;
  double _threshold = 7.0;
  double _soundThreshold = 1.5;
  int _autoAnalysisInterval = 60;
  String _exchange = 'Binance Futures';

  bool _busy = false;
  Map<String, dynamic>? _result;
  String _status = '';
  List<String> _symbols = [];

  final _intervals = ['1m (1 минута)', '5m (5 минут)', '15m (15 минут)', '30m (30 минут)', '1h (1 час)', '2h (2 часа)', '4h (4 часа)', '1d (1 день)'];
  final _soundThresholds = ['0.5', '1.0', '1.5', '2.0', '2.5', '3.0', '4.0', '5.0'];

  @override
  void initState() {
    super.initState();
    _loadSymbols();
  }

  Future<void> _loadSymbols() async {
    final list = await SymbolsService.getSymbols();
    setState(() => _symbols = list);
  }

  String _parseInterval(String label) {
    return label.split(' ').first;
  }

  Future<void> _run() async {
    final symbol = _symbol.trim().toUpperCase();
    if (symbol.isEmpty) {
      setState(() => _status = 'Введите символ');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Загрузка и анализ...';
      _result = null;
    });
    try {
      final res = await coreCall('search_pattern', {
        'exchange': _exchange,
        'symbol': symbol,
        'interval': _parseInterval(_interval),
        'pattern_length': _patternLength,
        'forecast_horizon': _forecastHorizon,
        'top_n': _topN,
        'min_signal_threshold': _threshold,
      });
      if (res['ok'] == true) {
        setState(() {
          _result = res;
          _status = '';
        });
        final forecast = (res['forecast_return_pct'] as num?)?.toDouble() ?? 0.0;
        if (forecast.abs() >= _soundThreshold) {
          SystemSound.play(SystemSoundType.alert);
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
      appBar: AppBar(title: const Text('Поиск по паттернам')),
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
                    title: 'Поиск по паттернам',
                    text: '1. Выберите монету.\n'
                        '2. Оставьте настройки по умолчанию — прогноз на 1 час.\n'
                        '3. Нажмите «Запустить анализ».\n\n'
                        'Сила сигнала — сколько паттернов совпало по направлению. '
                        'Сигнал считается сильным, если количество совпадений ≥ «Порог сильного сигнала».',
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
                    value: _interval,
                    dropdownColor: AppTheme.card,
                    style: const TextStyle(color: AppTheme.text),
                    decoration: const InputDecoration(labelText: 'Интервал свечей'),
                    items: _intervals
                        .map((i) => DropdownMenuItem(value: i, child: Text(i)))
                        .toList(),
                    onChanged: (v) => setState(() => _interval = v!),
                  ),
                  const SizedBox(height: 12),
                  _intField('Длина паттерна (свечей)', _patternLength, (v) => _patternLength = v),
                  _intField('Время прогноза (свечей)', _forecastHorizon, (v) => _forecastHorizon = v),
                  _intField('Количество паттернов', _topN, (v) => _topN = v),
                  _doubleField('Порог сильного сигнала (%)', _threshold, (v) => _threshold = v),
                  const SizedBox(height: 12),
                  _doubleField('Процент срабатывания сигнала (%)', _soundThreshold, (v) => _soundThreshold = v),
                  _intField('Интервал автоанализа (сек)', _autoAnalysisInterval, (v) => _autoAnalysisInterval = v),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _run,
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Text('Запустить анализ'),
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
            if (_result != null) _buildResult(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildResult() {
    final signal = _result!['signal'] ?? '-';
    final strength = _result!['strength'] ?? 0;
    final strengthMax = _result!['strength_max'] ?? _topN;
    final windows = _result!['windows'] as Map<String, dynamic>?;
    final hasWindows = windows != null && windows.isNotEmpty;

    final Color signalColor;
    if (signal == 'LONG') {
      signalColor = AppTheme.up;
    } else if (signal == 'SHORT') {
      signalColor = AppTheme.down;
    } else {
      signalColor = AppTheme.muted;
    }
    final matches = (_result!['matches'] as List<dynamic>?) ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Результат', style: AppTheme.title()),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Сигнал: ', style: AppTheme.body()),
                  Text(signal, style: AppTheme.title(color: signalColor)),
                  Text('Сила: $strength/$strengthMax', style: AppTheme.body()),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Текущая цена: ${_result!['current_price']} -> прогноз: ${_result!['forecast_price']} (${_result!['forecast_return_pct']}%)',
                style: AppTheme.body(),
              ),
              const SizedBox(height: 6),
              Text('Win-rate топа: ${_result!['win_rate']}', style: AppTheme.small()),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: hasWindows
                          ? () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => SignalChartScreen(windows: windows),
                                fullscreenDialog: true,
                              ))
                          : null,
                      icon: const Icon(Icons.candlestick_chart),
                      label: const Text('График'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: hasWindows
                          ? () => Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => SignalMovementScreen(windows: windows),
                                fullscreenDialog: true,
                              ))
                          : null,
                      icon: const Icon(Icons.trending_up),
                      label: const Text('Движение'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text('Топ совпадений:', style: AppTheme.title()),
        const SizedBox(height: 12),
        ...matches.map((m) => _matchCard(m as Map<String, dynamic>)),
      ],
    );
  }

  Widget _matchCard(Map<String, dynamic> m) {
    final futurePct = (m['future_return_pct'] as num?)?.toDouble() ?? 0.0;
    final isLong = futurePct > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
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
              Expanded(child: Text(m['time'] ?? '', style: AppTheme.small(), overflow: TextOverflow.ellipsis)),
              Text('${m['future_return_pct']}%', style: AppTheme.title(color: isLong ? AppTheme.up : AppTheme.down)),
            ],
          ),
          const SizedBox(height: 8),
          Text('Дистанция: ${m['distance']}', style: AppTheme.body()),
          const SizedBox(height: 6),
          Text('${m['start_price']} -> ${m['end_price']}', style: AppTheme.small()),
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
