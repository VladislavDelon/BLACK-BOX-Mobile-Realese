import '../core/core_call.dart';

class SymbolsService {
  static List<String>? _symbols;
  static bool _loading = false;

  static Future<List<String>> getSymbols() async {
    if (_symbols != null) return _symbols!;
    if (_loading) {
      while (_loading) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      return _symbols ?? [];
    }
    _loading = true;
    try {
      final res = await coreCall('get_symbols', {'exchange': 'Binance Futures'});
      if (res['ok'] == true && res['symbols'] is List) {
        _symbols = (res['symbols'] as List<dynamic>).map((s) => s.toString().toUpperCase()).toList();
      } else {
        _symbols = _defaultSymbols;
      }
    } catch (e) {
      _symbols = _defaultSymbols;
    } finally {
      _loading = false;
    }
    return _symbols ?? _defaultSymbols;
  }

  static final List<String> _defaultSymbols = [
    'BTCUSDT',
    'ETHUSDT',
    'SOLUSDT',
    'DOGEUSDT',
    'TRXUSDT',
    'XRPUSDT',
    'LTCUSDT',
    'BNBUSDT',
    'ADAUSDT',
    'AVAXUSDT',
    'LINKUSDT',
    'DOTUSDT',
    'MATICUSDT',
    'UNIUSDT',
    'ATOMUSDT',
    'ETCUSDT',
    'FILUSDT',
    'ALGOUSDT',
    'NEARUSDT',
  ];
}
