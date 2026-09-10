import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../widgets/ohlc_chart.dart';

class SignalChartScreen extends StatelessWidget {
  final Map<String, dynamic> windows;
  const SignalChartScreen({super.key, required this.windows});

  @override
  Widget build(BuildContext context) {
    final current = (windows['current_candles'] as List<dynamic>?) ?? [];
    final patterns = (windows['patterns'] as List<dynamic>?) ?? [];
    final symbol = windows['symbol']?.toString() ?? '';

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: Text('$symbol · График сигнала')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _section('Текущий паттерн'),
            SizedBox(
              height: 280,
              child: OhlcChart(candles: current),
            ),
            const SizedBox(height: 24),
            _section('Похожие исторические паттерны'),
            const SizedBox(height: 8),
            ...patterns.asMap().entries.map((e) => _patternCard(e.key, e.value as Map<String, dynamic>)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) {
    return Text(title, style: AppTheme.title());
  }

  Widget _patternCard(int index, Map<String, dynamic> p) {
    final candles = (p['candles'] as List<dynamic>?) ?? [];
    final forecastPct = (p['forecast_pct'] as num?)?.toDouble() ?? 0.0;
    final isUp = p['direction'].toString().contains('Рост');
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(12),
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
              Text('Паттерн #${index + 1}', style: AppTheme.body()),
              Text('${p['date']}', style: AppTheme.small()),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Похожесть: ${((p['similarity'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(1)}%'),
              Text('Прогноз: ${forecastPct.toStringAsFixed(2)}%',
                  style: AppTheme.body(color: isUp ? AppTheme.up : AppTheme.down)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: OhlcChart(candles: candles),
          ),
        ],
      ),
    );
  }
}
