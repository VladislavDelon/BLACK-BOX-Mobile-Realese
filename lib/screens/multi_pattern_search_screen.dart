import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../core/core_call.dart';

class MultiPatternSearchScreen extends StatefulWidget {
  const MultiPatternSearchScreen({super.key});

  @override
  State<MultiPatternSearchScreen> createState() => _MultiPatternSearchScreenState();
}

class _MultiPatternSearchScreenState extends State<MultiPatternSearchScreen> {
  final _symbolsCtrl = TextEditingController(text: "BTCUSDT, ETHUSDT, SOLUSDT");
  String _interval = "15m";
  int _patternLength = 60;
  int _forecastHorizon = 5;
  int _topN = 5;
  double _threshold = 0.0;
  String _exchange = "Binance Futures";
  bool _skipNeutral = true;

  bool _busy = false;
  List<dynamic>? _results;
  List<dynamic>? _errors;
  String _status = "";

  final _intervals = ["1m", "3m", "5m", "15m", "30m", "1h", "2h", "4h", "1d"];

  Future<void> _run() async {
    final symbols = _symbolsCtrl.text.trim();
    if (symbols.isEmpty) {
      setState(() => _status = "Введите символы");
      return;
    }
    setState(() {
      _busy = true;
      _status = "Анализ по ${_symbolsCtrl.text}...";
      _results = null;
      _errors = null;
    });
    try {
      final res = await coreCall("multi_pattern_search", {
        "symbols": [for (final s in symbols.split(",")) if (s.trim().isNotEmpty) s.trim().toUpperCase()],
        "exchange": _exchange,
        "interval": _interval,
        "pattern_length": _patternLength,
        "forecast_horizon": _forecastHorizon,
        "top_n": _topN,
        "min_signal_threshold": _threshold,
        "skip_neutral": _skipNeutral,
      });
      if (res["ok"] == true) {
        setState(() {
          _results = res["results"] as List<dynamic>?;
          _errors = res["errors"] as List<dynamic>?;
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
      appBar: AppBar(title: const Text("Мульти поиск по паттернам")),
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
                    controller: _symbolsCtrl,
                    decoration: const InputDecoration(
                      labelText: "Символы через запятую",
                      hintText: "BTCUSDT, ETHUSDT, SOLUSDT",
                    ),
                    minLines: 2,
                    maxLines: 3,
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
                  CheckboxListTile(
                    value: _skipNeutral,
                    onChanged: (v) => setState(() => _skipNeutral = v ?? true),
                    title: const Text("Пропускать NEUTRAL"),
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
                          : const Text("Запустить мульти-поиск"),
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
              const SizedBox(height: 16),
              Text("Ошибки:", style: AppTheme.title(color: AppTheme.down)),
              ..._errors!.map((e) => Text("${e['symbol']}: ${e['error']}", style: AppTheme.small(color: AppTheme.down))),
            ],
            if (_results != null && _results!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text("Результаты:", style: AppTheme.title()),
              const SizedBox(height: 8),
              ..._results!.map((r) => _resultCard(r as Map<String, dynamic>)),
            ] else if (_results != null && _results!.isEmpty) ...[
              const SizedBox(height: 16),
              Text("Нет сигналов по выбранным парам.", style: AppTheme.small()),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _resultCard(Map<String, dynamic> r) {
    final signal = r["signal"] ?? "-";
    final Color signalColor;
    if (signal == "LONG") {
      signalColor = AppTheme.up;
    } else if (signal == "SHORT") {
      signalColor = AppTheme.down;
    } else {
      signalColor = AppTheme.muted;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
              Text(r["symbol"] ?? "", style: AppTheme.title(color: AppTheme.accent)),
              Text(signal, style: AppTheme.title(color: signalColor)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "${r['current_price']} -> ${r['forecast_price']} (${r['forecast_return_pct']}%)",
            style: AppTheme.body(),
          ),
          Text("Сила: ${r['strength']} / Win-rate: ${r['win_rate']}", style: AppTheme.small()),
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
    _symbolsCtrl.dispose();
    super.dispose();
  }
}
