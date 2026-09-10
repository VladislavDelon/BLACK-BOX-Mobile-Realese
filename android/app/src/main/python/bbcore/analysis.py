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
from bbcore import desktop_analysis

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


def _friendly_error(e):
    err = str(e).lower()
    if "timeout" in err:
        return "Таймаут соединения. Проверьте интернет."
    if "name" in err and "resolve" in err:
        return "Нет соединения с интернетом."
    if "max retries" in err:
        return "Сеть временно недоступна."
    if "certificate" in err or "ssl" in err:
        return "Проблема с HTTPS-сертификатом."
    if "no symbol" in err:
        return "Символ не найден на бирже."
    return "Временно данных нет"


def _map_signal(res, min_threshold):
    """Определяет LONG/SHORT/NEUTRAL и силу из результата десктопного анализа."""
    if not res or not res.get("top_patterns"):
        return "NEUTRAL", 0

    sig_type = res.get("signal_type", "flat")
    long_count = res.get("long_count", 0)
    short_count = res.get("short_count", 0)
    strength = res.get("strength", 0)

    if sig_type == "long" and long_count >= min_threshold:
        return "LONG", strength
    if sig_type == "short" and short_count >= min_threshold:
        return "SHORT", strength
    return "NEUTRAL", strength


def search_pattern(exchange, symbol, interval, pattern_length=400,
                   forecast_horizon=15, top_n=10, min_signal_threshold=7,
                   api_key="", api_secret="", testnet=False):
    """
    Запускает поиск паттерна, идентичный десктопному.
    Возвращает dict с ok, signal, strength, current_price, matches, forecast.
    """
    try:
        res = desktop_analysis.run_analysis_job(
            symbol=symbol,
            top_n_patterns=top_n,
            min_signal_threshold=min_signal_threshold,
            show_all_signals=True,
            lookback_window=pattern_length,
            forecast_length=forecast_horizon,
            interval=interval,
        )
        if res is None:
            return {"ok": False, "error": "Не удалось загрузить данные"}
    except Exception as e:
        return {"ok": False, "error": _friendly_error(e)}

    signal, strength = _map_signal(res, min_signal_threshold)
    analyses = res.get("analyses", [])
    top_patterns = res.get("top_patterns", [])
    current_price = res.get("current_price", 0.0)
    forecast_price = res.get("forecast_price", current_price)
    forecast_return_pct = res.get("forecast_pct_change", 0.0)
    windows = desktop_analysis.build_signal_windows(res, symbol=symbol)

    # win_rate = доля большинства от общего числа найденных паттернов.
    analyses_with_dir = [a for a in analyses if "forecast_direction" in a]
    win_rate = strength / len(analyses_with_dir) if analyses_with_dir else 0.0

    matches = []
    for (similarity, pattern, idx), analysis in zip(top_patterns, analyses):
        if not analysis or "forecast_direction" not in analysis:
            continue
        matches.append({
            "time": str(analysis.get("start_date", "")),
            "distance": round(1.0 - float(similarity), 6),
            "future_return_pct": round(float(analysis.get("forecast_pct_change", 0.0)), 3),
            "start_price": round(float(analysis.get("forecast_start_price", 0.0)), 6),
            "end_price": round(float(analysis.get("forecast_end_price", 0.0)), 6),
        })

    return {
        "ok": True,
        "symbol": symbol,
        "interval": interval,
        "current_price": round(float(current_price), 6),
        "forecast_price": round(float(forecast_price), 6),
        "forecast_return_pct": round(float(forecast_return_pct), 3),
        "signal": signal,
        "strength": int(strength),
        "strength_max": int(res.get("top_n_patterns", top_n)),
        "win_rate": round(win_rate, 3),
        "matches_count": len(matches),
        "matches": matches,
        "windows": windows,
        "generated_at": time.time(),
    }


def multi_pattern_search(symbols, exchange, interval, pattern_length=400,
                         forecast_horizon=15, top_n=10, min_signal_threshold=7,
                         api_key="", api_secret="", testnet=False,
                         max_workers=3, skip_neutral=True, progress_callback=None):
    """
    Запускает поиск по паттернам сразу по нескольким монетам.
    Возвращает таблицу с лучшими сигналами.
    symbols — список строк, например ["BTCUSDT", "ETHUSDT"].
    progress_callback — функция вида fn(symbol, status, signal=None, result=None, error=None),
    вызывается после каждой пары.
    """
    results = []
    errors = []
    if isinstance(symbols, str):
        symbols = [s.strip() for s in symbols.split(",") if s.strip()]
    for symbol in symbols:
        try:
            if progress_callback:
                progress_callback(symbol, "loading")
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
                if progress_callback:
                    progress_callback(symbol, "done", signal=res.get("signal"), result=res)
            else:
                errors.append({"symbol": symbol, "error": res.get("error")})
                if progress_callback:
                    progress_callback(symbol, "error", error=res.get("error"))
        except Exception as e:
            errors.append({"symbol": symbol, "error": _friendly_error(e)})
            if progress_callback:
                progress_callback(symbol, "error", error=_friendly_error(e))

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
