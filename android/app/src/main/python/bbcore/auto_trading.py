# auto_trading.py — мобильная мульти-торговля по сигналам паттернов.
# В одном проходе анализирует список монет и открывает сделки,
# если прогноз превышает заданный порог.

import time

from bbcore import analysis, exchange_api, logutil


_STOP = False


def _stop():
    global _STOP
    _STOP = True


def _compute_qty(api, symbol, current_price, position_size, leverage,
                 amount_mode="fixed", balance=0.0, split_count=1):
    """Возвращает размер позиции в базовой монете."""
    if amount_mode == "percent":
        budget = balance * (position_size / 100.0)
    elif amount_mode == "split":
        budget = position_size / max(1, split_count)
    else:
        budget = position_size

    qty = budget * leverage / current_price if current_price else 0
    return qty


def _place_trade(api, symbol, direction, current_price, forecast_pct,
                 position_size, leverage, amount_mode, balance,
                 split_count,
                 tp_mode, tp_pct, sl_mode, sl_pct):
    """Открывает рыночный ордер с TP/SL. Возвращает dict с результатом."""
    try:
        # Определяем TP/SL цены.
        if tp_mode == "signal":
            tp_pct_use = abs(forecast_pct)
        else:
            tp_pct_use = float(tp_pct or 0)

        if sl_mode == "signal":
            sl_pct_use = abs(forecast_pct)
        else:
            sl_pct_use = float(sl_pct or 0)

        if direction == "LONG":
            tp_price = current_price * (1 + tp_pct_use / 100)
            sl_price = current_price * (1 - sl_pct_use / 100)
            side = "BUY"
            close_side = "SELL"
        else:  # SHORT
            tp_price = current_price * (1 - tp_pct_use / 100)
            sl_price = current_price * (1 + sl_pct_use / 100)
            side = "SELL"
            close_side = "BUY"

        qty = _compute_qty(
            api, symbol, current_price, position_size, leverage,
            amount_mode=amount_mode, balance=balance, split_count=split_count,
        )

        # Устанавливаем плечо.
        try:
            api.set_leverage(symbol, int(leverage))
        except Exception:
            pass

        qty = api.round_qty(symbol, qty)
        if qty <= 0:
            return {"ok": False, "error": "слишком маленький размер позиции"}

        tp_price = api.round_price(symbol, tp_price)
        sl_price = api.round_price(symbol, sl_price)

        if getattr(api, "supports_embedded_tp_sl", False):
            order = api.place_market_order(
                symbol, side, qty,
                leverage=int(leverage),
                stop_loss=sl_price,
                take_profit=tp_price,
            )
        else:
            order = api.place_market_order(symbol, side, qty)
            if tp_pct_use > 0:
                api.place_take_profit_order(symbol, close_side, tp_price)
            if sl_pct_use > 0:
                api.place_stop_order(symbol, close_side, sl_price)

        return {
            "ok": True,
            "symbol": symbol,
            "direction": direction,
            "side": side,
            "qty": qty,
            "leverage": leverage,
            "tp_price": tp_price,
            "tp_pct": tp_pct_use,
            "sl_price": sl_price,
            "sl_pct": sl_pct_use,
            "order": order,
        }
    except Exception as e:
        return {"ok": False, "error": str(e)}


def run_trading_cycle(symbols, exchange, api_key, api_secret, testnet=False,
                      interval="15m", pattern_length=60, forecast_horizon=5,
                      top_n=5, min_signal_threshold=0.0,
                      trade_threshold=1.5, position_size=100.0, leverage=10,
                      amount_mode="fixed", tp_mode="signal", tp_pct=0.0,
                      sl_mode="signal", sl_pct=0.0, max_trades=None):
    """
    Один торговый цикл: анализирует symbols и открывает сделки по сигналам.
    amount_mode: 'fixed', 'percent', 'split'.
    tp_mode/sl_mode: 'signal' (как прогноз) или 'fixed' (tp_pct/sl_pct).
    """
    global _STOP
    _STOP = False

    trades = []
    skipped = []
    errors = []

    if not symbols:
        return {"ok": False, "error": "Не выбраны монеты"}

    try:
        api = exchange_api.get_api(exchange, api_key, api_secret, testnet=testnet)
    except Exception as e:
        logutil.log(f"торговый цикл: не удалось создать API биржи: {e}")
        return {"ok": False, "error": f"Не удалось создать API биржи: {e}"}

    try:
        balance = api.get_balance("USDT")
    except Exception:
        balance = 0.0

    split_count = len(symbols)
    opened = 0
    for symbol in symbols:
        if _STOP:
            break
        if max_trades is not None and opened >= max_trades:
            break
        try:
            res = analysis.search_pattern(
                exchange, symbol, interval,
                pattern_length=pattern_length,
                forecast_horizon=forecast_horizon,
                top_n=top_n,
                min_signal_threshold=min_signal_threshold,
                api_key=api_key,
                api_secret=api_secret,
                testnet=testnet,
            )
        except Exception as e:
            logutil.log(f"[{symbol}] торговый цикл: {type(e).__name__}: {e}")
            errors.append({"symbol": symbol, "error": str(e)})
            continue

        if not res.get("ok"):
            errors.append({"symbol": symbol, "error": res.get("error", "unknown")})
            continue

        signal = res.get("signal", "NEUTRAL")
        forecast_pct = res.get("forecast_return_pct", 0.0)
        current_price = res.get("current_price", 0.0)

        if signal in ("LONG", "SHORT") and abs(forecast_pct) >= trade_threshold:
            trade = _place_trade(
                api, symbol, signal, current_price, forecast_pct,
                position_size, leverage, amount_mode, balance,
                split_count,
                tp_mode, tp_pct, sl_mode, sl_pct,
            )
            if trade.get("ok"):
                opened += 1
                trades.append(trade)
                logutil.log(f"[{symbol}] открыта сделка {signal} qty={trade.get('qty')} плечо={leverage}x")
            else:
                errors.append({"symbol": symbol, "error": trade.get("error")})
                logutil.log(f"[{symbol}] ошибка открытия сделки: {trade.get('error')}")
        else:
            skipped.append({
                "symbol": symbol,
                "signal": signal,
                "forecast_pct": forecast_pct,
            })

    return {
        "ok": True,
        "trades": trades,
        "skipped": skipped,
        "errors": errors,
        "balance": balance,
        "generated_at": time.time(),
    }
