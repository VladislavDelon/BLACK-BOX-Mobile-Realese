import 'package:flutter/material.dart';
import '../app_theme.dart';

class SignalMovementScreen extends StatelessWidget {
  final Map<String, dynamic> windows;
  const SignalMovementScreen({super.key, required this.windows});

  @override
  Widget build(BuildContext context) {
    final signalType = windows['signal_type']?.toString() ?? 'flat';
    final isLong = signalType == 'long';
    final accent = isLong ? AppTheme.up : (signalType == 'short' ? AppTheme.down : AppTheme.muted);
    final action = isLong ? 'ПОКУПАТКУПАТЬ ▲' : (signalType == 'short' ? 'ПРОДАВАТЬ ▼' : 'НЕЙТРАЛ');

    final strength = (windows['strength'] as num?)?.toInt() ?? 0;
    final upCount = (windows['up_count'] as num?)?.toInt() ?? 0;
    final downCount = (windows['down_count'] as num?)?.toInt() ?? 0;
    final total = upCount + downCount;
    final upShare = total > 0 ? upCount / total * 100 : 0.0;

    final currentPrice = (windows['current_price'] as num?)?.toDouble() ?? 0.0;
    final target = (windows['target'] as num?)?.toDouble() ?? 0.0;
    final avgPct = (windows['avg_pct_change'] as num?)?.toDouble() ?? 0.0;
    final bestPct = (windows['best_pct'] as num?)?.toDouble() ?? 0.0;
    final worstPct = (windows['worst_pct'] as num?)?.toDouble() ?? 0.0;
    final avgSim = (windows['avg_sim'] as num?)?.toDouble() ?? 0.0;
    final avgVol = (windows['avg_vol'] as num?)?.toDouble() ?? 0.0;
    final stop = (windows['stop_loss'] as num?)?.toDouble() ?? 0.0;
    final take = (windows['take_profit'] as num?)?.toDouble() ?? 0.0;
    final atr = (windows['atr'] as num?)?.toDouble() ?? 0.0;
    final forecastLength = (windows['forecast_length'] as num?)?.toInt() ?? 0;

    final patterns = (windows['patterns'] as List<dynamic>?) ?? [];

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Движение сигнала')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(action, style: AppTheme.title(color: accent)),
                      Builder(builder: (context) {
                        final threshold = (windows['min_signal_threshold'] as num?)?.toInt() ?? 7;
                        final label = strength >= threshold
                            ? 'СИЛЬНЫЙ СИГНАЛ'
                            : (strength >= threshold ~/ 2 ? 'СРЕДНИЙ' : 'СЛАБЫЙ');
                        return Text(label, style: AppTheme.title(color: accent));
                      }),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Совпало $upCount вверх / $downCount вниз из ${patterns.length} похожих случаев',
                      style: AppTheme.small()),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _metric('Цена сейчас', currentPrice.toStringAsFixed(4), 'USDT')),
                const SizedBox(width: 8),
                Expanded(child: _metric('Ожидаемое движение', '${avgPct.toStringAsFixed(2)}%', '$forecastLength мин')),
                const SizedBox(width: 8),
                Expanded(child: _metric('Примерная цель', target.toStringAsFixed(4), 'USDT')),
              ],
            ),
            const SizedBox(height: 16),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Куда пошла цена в похожих ситуациях', style: AppTheme.small()),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      height: 24,
                      child: Row(
                        children: [
                          if (upShare > 0)
                            Expanded(
                              flex: upShare.round(),
                              child: Container(
                                color: AppTheme.up,
                                alignment: Alignment.center,
                                child: Text('вверх $upCount', style: const TextStyle(fontSize: 11, color: Colors.black)),
                              ),
                            ),
                          if (100 - upShare > 0)
                            Expanded(
                              flex: (100 - upShare).round(),
                              child: Container(
                                color: AppTheme.down,
                                alignment: Alignment.center,
                                child: Text('вниз $downCount', style: const TextStyle(fontSize: 11, color: Colors.black)),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _card(
              child: Text(
                'Программа нашла ${patterns.length} похожих моментов в истории. '
                'В ${upCount + downCount} случаях из ${patterns.length} после этого цена ${isLong ? 'выросла' : 'упала'}.\n\n'
                'В среднем цена ${isLong ? 'росла' : 'падала'} на ${avgPct.abs().toStringAsFixed(2)}% за следующие $forecastLength минут. '
                'Лучший случай ${bestPct.toStringAsFixed(2)}%, худший ${worstPct.toStringAsFixed(2)}%.\n\n'
                'Похожесть графиков — ${(avgSim * 100).toStringAsFixed(0)}%. Разброс цены внутри прогноза — около ${avgVol.toStringAsFixed(2)}%.\n\n'
                'Ориентир для защиты: стоп-лосс ${stop.toStringAsFixed(4)} USDT, тейк-профит ${take.toStringAsFixed(4)} USDT, ATR ${atr.toStringAsFixed(4)}.',
                style: AppTheme.body(),
              ),
            ),
            const SizedBox(height: 16),
            Text('Похожие случаи из истории', style: AppTheme.title()),
            const SizedBox(height: 12),
            ...patterns.asMap().entries.map((e) => _patternRow(e.key, e.value as Map<String, dynamic>)),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, String sub) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(label, style: AppTheme.small(), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(value, style: AppTheme.title(), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(sub, style: AppTheme.small(), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _patternRow(int index, Map<String, dynamic> p) {
    final pct = (p['forecast_pct'] as num?)?.toDouble() ?? 0.0;
    final isUp = p['direction'].toString().contains('Рост');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('#${index + 1} ${p['date']}', style: AppTheme.small()),
          Text('${(p['similarity'] as num?)?.toDouble().toStringAsFixed(1)}%'),
          Text('${isUp ? '▲' : '▼'} ${pct.toStringAsFixed(2)}%',
              style: AppTheme.body(color: isUp ? AppTheme.up : AppTheme.down)),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}
