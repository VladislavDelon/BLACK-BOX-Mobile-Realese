import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../core/core_call.dart';

class AssetPricesScreen extends StatefulWidget {
  const AssetPricesScreen({super.key});

  @override
  State<AssetPricesScreen> createState() => _AssetPricesScreenState();
}

class _AssetPricesScreenState extends State<AssetPricesScreen> {
  final _symbolCtrl = TextEditingController(text: "BTCUSDT");
  bool _busy = false;
  String _status = "";
  List<Map<String, dynamic>> _prices = [];

  Future<void> _load() async {
    final symbol = _symbolCtrl.text.trim().toUpperCase();
    if (symbol.isEmpty) {
      setState(() => _status = "Введите символ");
      return;
    }
    setState(() {
      _busy = true;
      _status = "";
      _prices = [];
    });

    final exchanges = ["Binance Futures", "MEXC"];
    for (final ex in exchanges) {
      try {
        final res = await coreCall("get_price", {
          "exchange": ex,
          "symbol": symbol,
        });
        setState(() => _prices.add({
          "exchange": ex,
          ...res,
        }));
      } catch (e) {
        setState(() => _prices.add({
          "exchange": ex,
          "ok": false,
          "error": e.toString(),
        }));
      }
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text("Стоимость валют")),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _card(
              child: Column(
                children: [
                  TextField(
                    controller: _symbolCtrl,
                    decoration: const InputDecoration(
                      labelText: "Символ",
                      hintText: "BTCUSDT",
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _load,
                      child: _busy
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Text("Получить цены"),
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
            ..._prices.map(_priceCard),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _priceCard(Map<String, dynamic> p) {
    final ok = p["ok"] == true;
    final exchange = p["exchange"] ?? "-";
    final last = p["last"] ?? 0.0;
    final bid = p["bid"] ?? 0.0;
    final ask = p["ask"] ?? 0.0;
    final change = p["change_pct"] ?? 0.0;
    final changeColor = change >= 0 ? AppTheme.up : AppTheme.down;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ok
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exchange, style: AppTheme.title(color: AppTheme.accent)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Last", style: AppTheme.small()),
                    Text(last.toStringAsFixed(4), style: AppTheme.title()),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Bid / Ask", style: AppTheme.small()),
                    Text("${bid.toStringAsFixed(4)} / ${ask.toStringAsFixed(4)}",
                        style: AppTheme.body()),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("Изменение 24ч", style: AppTheme.small()),
                    Text("${change.toStringAsFixed(2)}%", style: AppTheme.body(color: changeColor)),
                  ],
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(exchange, style: AppTheme.title(color: AppTheme.accent)),
                const SizedBox(height: 8),
                Text("Ошибка: ${p['error']}", style: AppTheme.body(color: AppTheme.down)),
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

  @override
  void dispose() {
    _symbolCtrl.dispose();
    super.dispose();
  }
}
