import 'package:flutter/material.dart';
import 'package:candlesticks/candlesticks.dart';
import '../app_theme.dart';

class OhlcChart extends StatelessWidget {
  final List<dynamic> candles;

  const OhlcChart({super.key, required this.candles});

  static Candle _toCandle(Map<String, dynamic> c) {
    final ts = c['timestamp'] ?? c['date'] ?? '';
    final date = DateTime.tryParse(ts) ?? DateTime.now();
    return Candle(
      date: date,
      open: (c['open'] as num).toDouble(),
      high: (c['high'] as num).toDouble(),
      low: (c['low'] as num).toDouble(),
      close: (c['close'] as num).toDouble(),
      volume: (c['volume'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = candles
        .cast<Map<String, dynamic>>()
        .map(_toCandle)
        .toList();
    // candlesticks требует: новейшая свеча с индекса 0.
    final newestFirst = list.reversed.toList();
    return Candlesticks(
      candles: newestFirst,
      style: CandleSticksStyle.dark(
        chartBackgroundColor: AppTheme.bg,
        gridLineColor: AppTheme.muted.withOpacity(0.2),
        axisTextColor: AppTheme.muted,
        candleBullColor: AppTheme.up,
        candleBearColor: AppTheme.down,
        volumeBullColor: AppTheme.up.withOpacity(0.3),
        volumeBearColor: AppTheme.down.withOpacity(0.3),
        crosshairLineColor: AppTheme.muted,
        crosshairLabelBackgroundColor: AppTheme.card,
        crosshairLabelTextColor: AppTheme.text,
        ohlcInfoTextColor: AppTheme.text,
        ohlcInfoBullColor: AppTheme.up,
        ohlcInfoBearColor: AppTheme.down,
        priceIndicatorBullBackgroundColor: AppTheme.up,
        priceIndicatorBearBackgroundColor: AppTheme.down,
        priceIndicatorTextColor: AppTheme.text,
        scaleButtonActiveBackgroundColor: AppTheme.accent,
        scaleButtonActiveTextColor: Colors.black,
        scaleButtonInactiveBackgroundColor: AppTheme.card,
        scaleButtonInactiveTextColor: AppTheme.text,
        loadingIndicatorColor: AppTheme.accent,
      ),
    );
  }
}
