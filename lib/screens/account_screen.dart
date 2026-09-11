import 'dart:async';
import 'package:flutter/material.dart';
import '../app_theme.dart';
import '../core/core_call.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool _loading = true;
  String _error = '';
  String _exchange = '';
  String _name = '';
  bool _testnet = false;
  double _balance = 0.0;
  List<dynamic> _positions = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final res = await coreCall('get_account_overview');
      if (!mounted) return;
      if (res['ok'] == true) {
        setState(() {
          _error = '';
          _exchange = res['exchange']?.toString() ?? '';
          _name = res['name']?.toString() ?? _exchange;
          _testnet = res['testnet'] == true;
          _balance = (res['balance'] as num?)?.toDouble() ?? 0.0;
          _positions = res['positions'] as List<dynamic>? ?? [];
          _loading = false;
        });
      } else {
        setState(() {
          _error = res['error']?.toString() ?? 'Не удалось загрузить данные';
          _exchange = res['exchange']?.toString() ?? '';
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Ошибка канала: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Аккаунт'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AppTheme.text),
            onPressed: _load,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading && _exchange.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_error.isNotEmpty) ...[
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_error, style: AppTheme.body(color: AppTheme.down)),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => Navigator.pushNamed(context, '/exchange'),
                              child: const Text('Подключить биржу'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(_name, style: AppTheme.title(color: AppTheme.accent)),
                              ),
                              if (_testnet)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: AppTheme.down.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('TESTNET', style: AppTheme.small(color: AppTheme.down)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(_exchange, style: AppTheme.small()),
                          const SizedBox(height: 16),
                          Text('Баланс USDT', style: AppTheme.small()),
                          const SizedBox(height: 4),
                          Text(
                            _balance.toStringAsFixed(2),
                            style: AppTheme.title(color: AppTheme.up),
                          ),
                          if (_loading)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: SizedBox(
                                height: 14, width: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Внешний вид', style: AppTheme.title()),
                          const SizedBox(height: 8),
                          ValueListenableBuilder<bool>(
                            valueListenable: AppTheme.themeNotifier,
                            builder: (_, light, __) => SwitchListTile(
                              value: light,
                              onChanged: (v) => AppTheme.setLight(v),
                              title: const Text('Светлая тема'),
                              subtitle: const Text('Переключить оформление приложения'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text('Открытые позиции', style: AppTheme.title()),
                        const SizedBox(width: 8),
                        Text('(${_positions.length})', style: AppTheme.small()),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_positions.isEmpty)
                      Text('Нет открытых позиций.', style: AppTheme.small())
                    else
                      ..._positions.map((p) => _positionCard(p as Map<String, dynamic>)),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
      ),
    );
  }

  Widget _positionCard(Map<String, dynamic> p) {
    final side = p['side']?.toString() ?? '';
    final isLong = side == 'LONG';
    final pnl = (p['pnl'] as num?)?.toDouble() ?? 0.0;
    final pnlColor = pnl >= 0 ? AppTheme.up : AppTheme.down;
    final qty = (p['qty'] as num?)?.toDouble() ?? 0.0;
    final entry = (p['entry_price'] as num?)?.toDouble() ?? 0.0;
    final mark = (p['mark_price'] as num?)?.toDouble() ?? 0.0;
    final leverage = (p['leverage'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  p['symbol']?.toString() ?? '',
                  style: AppTheme.title(color: AppTheme.accent),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isLong ? AppTheme.up : AppTheme.down).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$side${leverage > 0 ? ' x$leverage' : ''}',
                  style: AppTheme.small(color: isLong ? AppTheme.up : AppTheme.down),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Объём: $qty', style: AppTheme.body()),
          const SizedBox(height: 4),
          Text('Вход: $entry  →  Марк: $mark', style: AppTheme.body()),
          const SizedBox(height: 4),
          Text(
            'PnL: ${pnl >= 0 ? '+' : ''}${pnl.toStringAsFixed(4)} USDT',
            style: AppTheme.body(color: pnlColor),
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
}
