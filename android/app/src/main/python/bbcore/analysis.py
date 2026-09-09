# analysis.py — мобильный поиск по паттернам (без numpy/pandas).
# Концептуально повторяет логику десктопа:
# 1. Берём последние pattern_length свечей как эталон.
# 2. Ищем похожие участки в истории по косинусному расстоянию.
# 3. Смотрим, что было дальше на forecast_horizon свечей.
# 4. Возвращаем сигнал, силу и статистику.

import json
import math
import time
from datetime import datetime

from bbcore import exchange_api

INTERVAL_MAP = {
    "1m": 60, "3m": 180, "5m": 300, "15m": 900,
    "30m": 1800, "1h": 3600, "2h": 7200, "4h": 14400,
    "6h": 21600, "8h": 28800, "12h": 43200, "1d": 86400,
    "1w": 604800,
}


def _mean(values):
    return sum(values) / len(values) if values else 0.0


def _std(values, mean):
    n = len(values)
    if n < 2:
        return 0.0
    return math.sqrt(sum((x - mean) ** 2 for x in values) / (n - 1))


def _normalize(values):
    """Z-score нормализация."""
    n = len(values)
    if n == 0:
        return values[:]
    mean = _mean(values)
    std = _std(values, mean)
    if std == 0:
        return [0.0] * n
    return [(x - mean) / std for x in values]


def _cosine_distance(a, b):
    """Косинусное расстояние между двумя одинаковыми списками."""
    n = len(a)
    if n == 0:
        return 1.0
    dot = sum(a[i] * b[i] for i in range(n))
    norm_a = math.sqrt(sum(x * x for x in a))
    norm_b = math.sqrt(sum(x * x for x in b))
    if norm_a == 0 or norm_b == 0:
        return 1.0
    cos = dot / (norm_a * norm_b)
    return 1.0 - cos


def _format_time(ms):
    return datetime.fromtimestamp(ms / 1000).strftime("%Y-%m-%d %H:%M")


def search_pattern(exchange, symbol, interval, pattern_length=60,
                   forecast_horizon=5, top_n=5, min_signal_threshold=0.0,
                   api_key="", api_secret="", testnet=False):
    """
    Запускает поиск паттерна.
    Возвращает dict с ok, signal, strength, current_price, matches, forecast.
    """
    try:
        # Для анализа не нужны приватные ключи, но биржа может требовать объект.
        api = exchange_api.get_api(exchange, api_key or "-", api_secret or "-", testnet=testnet)
        klines = api.get_klines(symbol, interval, limit=1500)
    except Exception as e:
        return {"ok": False, "error": str(e)}

    if len(klines) < pattern_length + forecast_horizon + top_n + 10:
        return {
            "ok": False,
            "error": f"Недостаточно данных: {len(klines)} свечей. Нужно > {pattern_length + forecast_horizon + 10}.",
        }

    closes = [c[4] for c in klines]
    times = [c[0] for c in klines]
    current_price = closes[-1]

    # Эталон — последние pattern_length свечей.
    reference = _normalize(closes[-pattern_length:])

    # Ищем похожие участки. Пропускаем последние pattern_length + forecast_horizon, чтобы смотреть "было дальше".
    search_end = len(closes) - pattern_length - forecast_horizon
    matches = []
    for i in range(0, search_end - pattern_length):
        window = _normalize(closes[i:i + pattern_length])
        dist = _cosine_distance(reference, window)
        # Что было дальше.
        fut_start = closes[i + pattern_length]
        fut_end = closes[i + pattern_length + forecast_horizon - 1]
        fut_return = (fut_end - fut_start) / fut_start if fut_start else 0.0
        matches.append({
            "index": i,
            "time": _format_time(times[i]),
            "distance": round(dist, 6),
            "future_return": round(fut_return, 6),
            "future_return_pct": round(fut_return * 100, 3),
            "start_price": round(fut_start, 6),
            "end_price": round(fut_end, 6),
        })

    matches.sort(key=lambda x: x["distance"])
    top = matches[:top_n]
    if not top:
        return {"ok": False, "error": "Не найдено похожих паттернов."}

    returns = [m["future_return"] for m in top]
    avg_return = _mean(returns)
    win_rate = sum(1 for r in returns if r > 0) / len(returns)

    # Сигнал.
    if avg_return > min_signal_threshold / 100.0:
        signal = "LONG"
    elif avg_return < -min_signal_threshold / 100.0:
        signal = "SHORT"
    else:
        signal = "NEUTRAL"

    # Сила 0-100: чем однороднее топ и больше средний модуль, тем сильнее.
    abs_returns = [abs(r) for r in returns]
    strength = min(100, int(_mean(abs_returns) * 100 * 2 + win_rate * 50))

    # Прогноз: средняя цена через forecast_horizon свечей.
    if avg_return != 0:
        forecast_price = current_price * (1 + avg_return)
    else:
        forecast_price = current_price

    return {
        "ok": True,
        "symbol": symbol,
        "interval": interval,
        "current_price": round(current_price, 6),
        "forecast_price": round(forecast_price, 6),
        "forecast_return_pct": round(avg_return * 100, 3),
        "signal": signal,
        "strength": strength,
        "win_rate": round(win_rate, 3),
        "matches_count": len(top),
        "matches": top,
        "generated_at": time.time(),
    }


def multi_pattern_search(symbols, exchange, interval, pattern_length=60,
                         forecast_horizon=5, top_n=5, min_signal_threshold=0.0,
                         api_key="", api_secret="", testnet=False,
                         max_workers=3, skip_neutral=True):
    """
    Запускает поиск по паттернам сразу по нескольким монетам.
    Возвращает таблицу с лучшими сигналами.
    symbols — список строк, например ["BTCUSDT", "ETHUSDT"].
    """
    results = []
    errors = []
    if isinstance(symbols, str):
        symbols = [s.strip() for s in symbols.split(",") if s.strip()]
    for symbol in symbols:
        try:
            res = search_pattern(
                exchange, symbol, interval,
                pattern_length=pattern_length,
                forecast_horizon=forecast_horizon,
                top_n=top_n,
                min_signal_threshold=min_signal_threshold,
                api_key=api_key,
                api_secret=api_secret,
                testnet=testnet,
            )
            if res.get("ok"):
                if not (skip_neutral and res.get("signal") == "NEUTRAL"):
                    results.append(res)
            else:
                errors.append({"symbol": symbol, "error": res.get("error")})
        except Exception as e:
            errors.append({"symbol": symbol, "error": str(e)})

    # Сортируем: сначала сила, затем потенциальная доходность.
    results.sort(
        key=lambda r: (r.get("strength", 0), abs(r.get("forecast_return_pct", 0))),
        reverse=True,
    )
    return {
        "ok": True,
        "count": len(results),
        "results": results,
        "errors": errors,
    }
