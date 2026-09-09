import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../core/core_call.dart';

class PatternSearchScreen extends StatefulWidget {
  const PatternSearchScreen({super.key});

  @override
  State<PatternSearchScreen> createState() => _PatternSearchScreenState();
}

class _PatternSearchScreenState extends State<PatternSearchScreen> {
  final _symbolCtrl = TextEditingController(text: "BTCUSDT");
  String _interval = "15m";
  int _patternLength = 60;
  int _forecastHorizon = 5;
  int _topN = 5;
  double _threshold = 0.0;
  String _exchange = "Binance Futures";

  bool _busy = false;
  Map<String, dynamic>? _result;
  String _status = "";

  final _intervals = ["1m", "3m", "5m", "15m", "30m", "1h", "2h", "4h", "1d"];

  Future<void> _run() async {
    final symbol = _symbolCtrl.text.trim().toUpperCase();
    if (symbol.isEmpty) {
      setState(() => _status = "Введите символ");
      return;
    }
    setState(() {
      _busy = true;
      _status = "Загрузка и анализ...";
      _result = null;
    });
    try {
      final res = await coreCall("search_pattern", {
        "exchange": _exchange,
        "symbol": symbol,
        "interval": _interval,
        "pattern_length": _patternLength,
        "forecast_horizon": _forecastHorizon,
        "top_n": _topN,
        "min_signal_threshold": _threshold,
      });
      if (res["ok"] == true) {
        setState(() {
          _result = res;
          _status = "";
        });
      } else {
        setState(() => _status = "Ошибка: ${res['error']}");
      }
    } catch (e) {
      setState(() => _status = "Ошибка канала: $e");
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text("Поиск по паттернам")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Настройки", style: AppTheme.title()),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _symbolCtrl,
                    decoration: const InputDecoration(labelText: "Символ (BTCUSDT)"),
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _interval,
                    dropdownColor: AppTheme.card,
                    style: const TextStyle(color: AppTheme.text),
                    decoration: const InputDecoration(labelText: "Интервал"),
                    items: _intervals
                        .map((i) => DropdownMenuItem(value: i, child: Text(i)))
                        .toList(),
                    onChanged: (v) => setState(() => _interval = v!),
                  ),
                  const SizedBox(height: 12),
                  _intField("Длина паттерна", _patternLength, (v) => _patternLength = v),
                  _intField("Горизонт прогноза", _forecastHorizon, (v) => _forecastHorizon = v),
                  _intField("TOP-N похожих", _topN, (v) => _topN = v),
                  _doubleField("Порог сигнала (%)", _threshold, (v) => _threshold = v),
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
                          : const Text("Запустить анализ"),
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
    final signal = _result!["signal"] ?? "-";
    final strength = _result!["strength"] ?? 0;
    final Color signalColor;
    if (signal == "LONG") {
      signalColor = AppTheme.up;
    } else if (signal == "SHORT") {
      signalColor = AppTheme.down;
    } else {
      signalColor = AppTheme.muted;
    }
    final matches = (_result!["matches"] as List<dynamic>?) ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Результат", style: AppTheme.title()),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text("Сигнал: ", style: AppTheme.body()),
                  Text(signal, style: AppTheme.title(color: signalColor)),
                  const SizedBox(width: 20),
                  Text("Сила: $strength/100", style: AppTheme.body()),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                "Текущая цена: ${_result!['current_price']} -> прогноз: ${_result!['forecast_price']} (${_result!['forecast_return_pct']}%)",
                style: AppTheme.body(),
              ),
              Text("Win-rate топа: ${_result!['win_rate']}", style: AppTheme.small()),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text("Топ совпадений:", style: AppTheme.title()),
        const SizedBox(height: 8),
        ...matches.map((m) => _matchCard(m as Map<String, dynamic>)),
      ],
    );
  }

  Widget _matchCard(Map<String, dynamic> m) {
    final futurePct = (m["future_return_pct"] as num?)?.toDouble() ?? 0.0;
    final isLong = futurePct > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m["time"] ?? "", style: AppTheme.small()),
                Text(
                  "Дистанция: ${m['distance']}",
                  style: AppTheme.body(),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${m['future_return_pct']}%",
                style: AppTheme.title(color: isLong ? AppTheme.up : AppTheme.down),
              ),
              Text("${m['start_price']} -> ${m['end_price']}", style: AppTheme.small()),
            ],
          ),
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
    return TextField(
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      controller: TextEditingController(text: value.toString()),
      onChanged: (s) {
        final v = int.tryParse(s);
        if (v != null) onChanged(v);
      },
    );
  }

  Widget _doubleField(String label, double value, ValueChanged<double> onChanged) {
    return TextField(
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      controller: TextEditingController(text: value.toString()),
      onChanged: (s) {
        final v = double.tryParse(s.replaceAll(",", "."));
        if (v != null) onChanged(v);
      },
    );
  }

  @override
  void dispose() {
    _symbolCtrl.dispose();
    super.dispose();
  }
}
