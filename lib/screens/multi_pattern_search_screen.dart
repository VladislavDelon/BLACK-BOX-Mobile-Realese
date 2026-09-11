import 'dart:async';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../core/core_call.dart';
import '../services/symbols_service.dart';
import '../widgets/symbol_picker.dart';
import '../widgets/help_button.dart';

class MultiPatternSearchScreen extends StatefulWidget {
  const MultiPatternSearchScreen({super.key});

  @override
  State<MultiPatternSearchScreen> createState() => _MultiPatternSearchScreenState();
}

class _MultiPatternSearchScreenState extends State<MultiPatternSearchScreen> {
  List<String> _symbols = ['SOLUSDT', 'BTCUSDT', 'ETHUSDT'];
  String _interval = '1m (1 минута)';
  int _patternLength = 400;
  int _forecastHorizon = 60;
  int _topN = 10;
  double _threshold = 7.0;
  double _soundThreshold = 1.5;
  String _exchange = 'Binance Futures';
  bool _skipNeutral = false;

  bool _busy = false;
  List<dynamic>? _results;
  List<dynamic>? _errors;
  String _status = '';
  List<String> _allSymbols = [];

  final _intervals = ['1m (1 минута)', '5m (5 минут)', '15m (15 минут)', '30m (30 минут)', '1h (1 час)', '2h (2 часа)', '4h (4 часа)', '1d (1 день)'];

  final List<Map<String, dynamic>> _progressLog = [];
  Timer? _pollTimer;
  int _jobTotal = 0;

  int get _doneCount =>
      _progressLog.where((e) => (e['state'] ?? '') != 'loading').length;

  @override
  void initState() {
    super.initState();
    _loadSymbols();
    _attachToJob();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSymbols() async {
    final list = await SymbolsService.getSymbols();
    setState(() => _allSymbols = list);
  }

  String _parseInterval(String label) {
    return label.split(' ').first;
  }

  /// Подключаемся к уже идущей задаче (если пользователь вернулся на экран)
  /// или восстанавливаем результаты завершённой.
  Future<void> _attachToJob() async {
    Map<String, dynamic> prog;
    try {
      prog = await coreCall('get_analysis_progress');
    } catch (_) {
      return;
    }
    if (!mounted || prog['ok'] != true) return;
    final status = prog['status'] as String?;
    _jobTotal = (prog['total'] as num?)?.toInt() ?? _jobTotal;
    final log = (prog['progress'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
    if (status == 'running') {
      setState(() {
        _busy = true;
        _progressLog
          ..clear()
          ..addAll(log);
        _status = 'Анализ идёт в фоне — можно перейти в другой раздел';
      });
      _startPolling();
    } else if (status == 'done' || status == 'error' || status == 'cancelled') {
      final fin = prog['final'] as Map<String, dynamic>?;
      setState(() {
        _progressLog
          ..clear()
          ..addAll(log);
        if (fin != null) {
          _results = fin['results'] as List<dynamic>?;
          _errors = fin['errors'] as List<dynamic>?;
        }
        if (status == 'cancelled') {
          _status = 'Анализ остановлен';
        } else if (status == 'error') {
          _status = 'Ошибка: ${prog['error'] ?? 'неизвестная'}';
        }
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollOnce());
  }

  Future<void> _pollOnce() async {
    Map<String, dynamic> prog;
    try {
      prog = await coreCall('get_analysis_progress');
    } catch (_) {
      return;
    }
    if (!mounted || prog['ok'] != true) return;
    final status = prog['status'] as String?;
    _jobTotal = (prog['total'] as num?)?.toInt() ?? _jobTotal;
    final log = (prog['progress'] as List<dynamic>?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        [];
    setState(() {
      _progressLog
        ..clear()
        ..addAll(log);
    });
    if (status == 'done' || status == 'error' || status == 'cancelled') {
      _pollTimer?.cancel();
      final fin = prog['final'] as Map<String, dynamic>?;
      setState(() {
        _busy = false;
        _results = fin?['results'] as List<dynamic>?;
        _errors = fin?['errors'] as List<dynamic>?;
        _status = status == 'cancelled'
            ? 'Анализ остановлен'
            : status == 'error'
                ? 'Ошибка: ${prog['error'] ?? 'неизвестная'}'
                : '';
      });
    }
  }

  Future<void> _run() async {
    if (_symbols.isEmpty) {
      setState(() => _status = 'Выберите символы');
      return;
    }
    setState(() {
      _busy = true;
      _jobTotal = _symbols.length;
      _status = 'Анализ по ${_symbols.length} парам — можно перейти в другой раздел';
      _results = null;
      _errors = null;
      _progressLog.clear();
    });
    try {
      await startAnalysisService({
        'symbols': _symbols,
        'exchange': _exchange,
        'interval': _parseInterval(_interval),
        'pattern_length': _patternLength,
        'forecast_horizon': _forecastHorizon,
        'top_n': _topN,
        'min_signal_threshold': _threshold,
        'skip_neutral': _skipNeutral,
      }, soundThreshold: _soundThreshold);
      _startPolling();
    } catch (e) {
      setState(() {
        _status = 'Ошибка канала: $e';
        _busy = false;
      });
    }
  }

  Future<void> _stop() async {
    try {
      await coreCall('cancel_analysis');
    } catch (_) {}
    try {
      await stopAnalysisService();
    } catch (_) {}
    _pollTimer?.cancel();
    setState(() {
      _busy = false;
      _status = 'Анализ остановлен';
    });
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
                  const SizedBox(height: 8),
                  HelpButton(
                    title: 'Мульти поиск по паттернам',
                    text: '1. Выберите несколько монет.\n'
                        '2. Оставьте настройки по умолчанию — прогноз на 1 час.\n'
                        '3. Нажмите «Запустить мульти-поиск».\n\n'
                        'Анализ работает в фоне: можно перейти в другой раздел, '
                        'задача продолжится, а прогресс виден в уведомлении. '
                        'Кнопка «Остановить анализ» прерывает поиск.\n\n'
                        'Звуковой сигнал сработает, если прогноз превысит «Процент срабатывания сигнала». '
                        '«Пропускать NEUTRAL» скрывает пары без явного LONG/SHORT.',
                  ),
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
                    style: TextStyle(color: AppTheme.text),
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
                    child: _busy
                        ? FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: AppTheme.down),
                            onPressed: _stop,
                            child: const Text('Остановить анализ'),
                          )
                        : FilledButton(
                            onPressed: _run,
                            child: const Text('Запустить мульти-поиск'),
                          ),
                  ),
                ],
              ),
            ),
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _status,
                  style: AppTheme.body(
                    color: _status.startsWith('Ошибка') ? AppTheme.down : AppTheme.muted,
                  ),
                ),
              ),
            if (_busy || _progressLog.isNotEmpty) ...[
              const SizedBox(height: 8),
              _card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (_busy)
                          const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        if (_busy) const SizedBox(width: 10),
                        Text(
                          _jobTotal > 0 ? 'Анализ $_doneCount/$_jobTotal' : 'Анализ пар',
                          style: AppTheme.title(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._progressLog.map((e) => _progressRow(e)),
                  ],
                ),
              ),
            ],
            if (_errors != null && _errors!.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('${_errors!.length} пар временно недоступны', style: AppTheme.small(color: AppTheme.muted)),
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

  Widget _progressRow(Map<String, dynamic> e) {
    final signal = e['signal']?.toString() ?? '';
    Color c = AppTheme.muted;
    if (signal == 'LONG') c = AppTheme.up;
    if (signal == 'SHORT') c = AppTheme.down;
    if (signal == 'ERROR') c = AppTheme.down;
    if (signal == 'CANCELLED' || signal == 'FLAT' || signal == 'START') c = AppTheme.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(e['symbol']?.toString() ?? '', style: AppTheme.body()),
          ),
          Text(e['status']?.toString() ?? '', style: AppTheme.small(color: c)),
        ],
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
            '${r['current_price']} -> ${r['future_price']} (${r['avg_pct']}%)',
            style: AppTheme.body(),
          ),
          const SizedBox(height: 6),
          Text('Сила: ${r['strength']}/${r['strength_max']} | Win-rate: ${r['win_rate']}', style: AppTheme.small()),
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
