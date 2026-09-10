import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../core/core_call.dart';
import '../services/symbols_service.dart';
import '../widgets/symbol_picker.dart';

class MultiPatternSearchScreen extends StatefulWidget {
  const MultiPatternSearchScreen({super.key});

  @override
  State<MultiPatternSearchScreen> createState() => _MultiPatternSearchScreenState();
}

class _MultiPatternSearchScreenState extends State<MultiPatternSearchScreen> {
  List<String> _symbols = ['SOLUSDT', 'BTCUSDT', 'ETHUSDT'];
  String _interval = '1m';
  int _patternLength = 600;
  int _forecastHorizon = 15;
  int _topN = 16;
  double _threshold = 12.0;
  double _soundThreshold = 1.5;
  String _exchange = 'Binance Futures';
  bool _skipNeutral = false;

  bool _busy = false;
  List<dynamic>? _results;
  List<dynamic>? _errors;
  String _status = '';
  List<String> _allSymbols = [];

  final _intervals = ['1m (1 минута)', '5m (5 минут)', '15m (15 минут)', '30m (30 минут)', '1h (1 час)', '2h (2 часа)', '4h (4 часа)', '1d (1 день)'];

  @override
  void initState() {
    super.initState();
    _loadSymbols();
  }

  Future<void> _loadSymbols() async {
    final list = await SymbolsService.getSymbols();
    setState(() => _allSymbols = list);
  }

  String _parseInterval(String label) {
    return label.split(' ').first;
  }

  Future<void> _run() async {
    if (_symbols.isEmpty) {
      setState(() => _status = 'Выберите символы');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Анализ по ${_symbols.length} парам...';
      _results = null;
      _errors = null;
    });
    _openProgressSheet();
    try {
      final results = <Map<String, dynamic>>[];
      final errors = <Map<String, dynamic>>[];
      for (final symbol in _symbols) {
        if (!mounted) break;
        _updateProgress(symbol, 'Загрузка...', null);
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
          results.add(res);
          final forecast = (res['forecast_return_pct'] as num?)?.toDouble() ?? 0.0;
          if (forecast.abs() >= _soundThreshold) {
            SystemSound.play(SystemSoundType.alert);
          }
          _updateProgress(
            symbol,
            '${res['signal']} ${res['forecast_return_pct']}%',
            res['signal']?.toString() ?? '',
          );
        } else {
          errors.add({'symbol': symbol, 'error': res['error']});
          _updateProgress(symbol, 'Ошибка: ${res['error']}', 'ERROR');
        }
      }
      results.sort((a, b) {
        final as_ = (a['strength'] as num?)?.toDouble() ?? 0.0;
        final bs = (b['strength'] as num?)?.toDouble() ?? 0.0;
        if (as_ != bs) return bs.compareTo(as_);
        final af = (a['forecast_return_pct'] as num?)?.toDouble().abs() ?? 0.0;
        final bf = (b['forecast_return_pct'] as num?)?.toDouble().abs() ?? 0.0;
        return bf.compareTo(af);
      });
      if (_skipNeutral) {
        results.removeWhere((r) => r['signal'] == 'NEUTRAL');
      }
      setState(() {
        _results = results;
        _errors = errors;
        _status = '';
      });
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _status = 'Ошибка канала: $e');
      if (mounted) Navigator.of(context).pop();
    } finally {
      setState(() => _busy = false);
    }
  }

  final List<Map<String, dynamic>> _progressLog = [];

  void _updateProgress(String symbol, String status, String? signal) {
    setState(() {
      final idx = _progressLog.indexWhere((e) => e['symbol'] == symbol);
      if (idx >= 0) {
        _progressLog[idx] = {'symbol': symbol, 'status': status, 'signal': signal};
      } else {
        _progressLog.add({'symbol': symbol, 'status': status, 'signal': signal});
      }
    });
    _progressSheetKey.currentState?.refresh();
  }

  final GlobalKey<_ProgressSheetState> _progressSheetKey = GlobalKey();

  void _openProgressSheet() {
    _progressLog.clear();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.card,
      builder: (ctx) => _ProgressSheet(key: _progressSheetKey, log: _progressLog),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Мульти поиск по паттернам')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Настройки', style: AppTheme.title()),
                  const SizedBox(height: 16),
                  MultiSymbolPicker(
                    selected: _symbols,
                    symbols: _allSymbols,
                    onChanged: (v) => setState(() => _symbols = v),
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
                  _doubleField('Процент срабатывания сигнала (%)', _soundThreshold, (v) => _soundThreshold = v),
                  CheckboxListTile(
                    value: _skipNeutral,
                    onChanged: (v) => setState(() => _skipNeutral = v ?? true),
                    title: const Text('Пропускать NEUTRAL'),
                    subtitle: const Text('Не показывать пары без сильного сигнала (LONG/SHORT)'),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
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
                          : const Text('Запустить мульти-поиск'),
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
            if (_errors != null && _errors!.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Ошибки:', style: AppTheme.title(color: AppTheme.down)),
              const SizedBox(height: 12),
              ..._errors!.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${e['symbol']}: ${e['error']}', style: AppTheme.small(color: AppTheme.down)),
              )),
            ],
            if (_results != null && _results!.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Результаты:', style: AppTheme.title()),
              const SizedBox(height: 12),
              ..._results!.map((r) => _resultCard(r as Map<String, dynamic>)),
            ] else if (_results != null && _results!.isEmpty) ...[
              const SizedBox(height: 20),
              Text('Нет сигналов по выбранным парам.', style: AppTheme.small()),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(Map<String, dynamic> r) {
    final signal = r['signal'] ?? '-';
    final Color signalColor;
    if (signal == 'LONG') {
      signalColor = AppTheme.up;
    } else if (signal == 'SHORT') {
      signalColor = AppTheme.down;
    } else {
      signalColor = AppTheme.muted;
    }
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
                  r['symbol'] ?? '',
                  style: AppTheme.title(color: AppTheme.accent),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(signal, style: AppTheme.title(color: signalColor)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${r['current_price']} -> ${r['forecast_price']} (${r['forecast_return_pct']}%)',
            style: AppTheme.body(),
          ),
          const SizedBox(height: 6),
          Text('Сила: ${r['strength']} / Win-rate: ${r['win_rate']}', style: AppTheme.small()),
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

class _ProgressSheet extends StatefulWidget {
  final List<Map<String, dynamic>> log;
  const _ProgressSheet({super.key, required this.log});

  @override
  State<_ProgressSheet> createState() => _ProgressSheetState();
}

class _ProgressSheetState extends State<_ProgressSheet> {
  void refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, scrollCtrl) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text('Анализ пар', style: AppTheme.title()),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: widget.log.length,
                itemBuilder: (_, i) {
                  final e = widget.log[i];
                  final signal = e['signal']?.toString() ?? '';
                  Color c = AppTheme.muted;
                  if (signal == 'LONG') c = AppTheme.up;
                  if (signal == 'SHORT') c = AppTheme.down;
                  if (signal == 'ERROR') c = AppTheme.down;
                  return ListTile(
                    dense: true,
                    title: Text(e['symbol']?.toString() ?? '', style: AppTheme.body()),
                    subtitle: Text(e['status']?.toString() ?? '', style: AppTheme.small(color: c)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
