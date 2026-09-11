# desktop_analysis.py — порт десктопного анализа паттернов (pc_app_gui.py/analysis.py)
# без matplotlib и multiprocessing.

import math
import time
from datetime import datetime, timedelta

import numpy as np
import pandas as pd
import requests

# === Константы, совпадающие с десктопным config.py ===
# Как на десктопе: свечи — Binance spot, список монет — fapi (там же).
API_URL = "https://api.binance.com/api/v3/klines"
DEFAULT_SYMBOL = "SOLUSDT"
INTERVAL = "1m"
FORECAST_LENGTH = 60
LOOKBACK_WINDOW = 400
TOP_N_PATTERNS = 13
MIN_SIGNAL_THRESHOLD = 9
LEVERAGE = 20
VOLATILITY_DIFF_THRESHOLD = 0.05
MIN_LOOKBACK = 60
MAX_LOOKBACK = 1200
MIN_FORECAST = 30
MAX_FORECAST = 600
MIN_TOP_N_PATTERNS = 3
MAX_TOP_N_PATTERNS = 25
MIN_SIGNAL_THRESHOLD_MIN = 2
MIN_SIGNAL_THRESHOLD_MAX = 20

HIST_CACHE = {}
STOP_FLAGS = {}


def set_stop_flag(symbol, value=True):
    STOP_FLAGS[symbol] = value


def get_stop_flag(symbol):
    return STOP_FLAGS.get(symbol, False)


# ------------------------------------------------------------
# Данные
# ------------------------------------------------------------

def get_realtime_data(symbol=None, interval=INTERVAL, limit=1000):
    """Возвращает DataFrame OHLC как в десктопной версии (Binance USD-M Futures)."""
    if symbol is None:
        symbol = DEFAULT_SYMBOL

    params = {"symbol": symbol, "interval": interval, "limit": limit}
    response = requests.get(API_URL, params=params, timeout=15)
    try:
        klines = response.json()
    except Exception:
        klines = None
    if response.status_code != 200 or not isinstance(klines, list):
        msg = ""
        if isinstance(klines, dict):
            msg = klines.get("msg", "")
        raise ValueError(f"Binance klines error {response.status_code}: {msg or response.text}")
    if not klines:
        raise ValueError(f"Binance returned empty klines for {symbol}")

    df = pd.DataFrame(
        klines,
        columns=[
            "timestamp", "open", "high", "low", "close", "volume",
            "close_time", "quote_asset_volume", "num_trades",
            "taker_buy_base", "taker_buy_quote", "ignore",
        ],
    )
    df = df[["timestamp", "open", "high", "low", "close"]]
    df["timestamp"] = pd.to_datetime(df["timestamp"], unit="ms")
    for col in ["open", "high", "low", "close"]:
        df[col] = pd.to_numeric(df[col])
    df.set_index("timestamp", inplace=True)
    return df


def init_historical_cache(symbol=None, interval=INTERVAL):
    """В десктопной версии данные берутся с Binance; кэшируем по символу+интервалу."""
    if symbol is None:
        symbol = DEFAULT_SYMBOL
    key = f"{symbol}:{interval}"
    if key in HIST_CACHE:
        return HIST_CACHE[key]
    df = get_realtime_data(symbol, interval=interval)
    cache = {
        "df": df,
        "open": df["open"].values,
        "high": df["high"].values,
        "low": df["low"].values,
        "close": df["close"].values,
        "index": df.index,
    }
    HIST_CACHE[key] = cache
    return cache


def cleanup_data():
    HIST_CACHE.clear()


# ------------------------------------------------------------
# Математика паттернов (аналог scipy/numpy логики)
# ------------------------------------------------------------

def _find_peaks(values, prominence=0.5):
    """Аналог scipy.signal.find_peaks(x, prominence=p).
    Плато считается пиком в его середине, проминенция — как в scipy:
    пик минус максимум из минимумов до ближайшего более высокого пика
    (или края данных) слева и справа."""
    values = np.asarray(values, dtype=float)
    n = len(values)
    if n < 3:
        return np.array([])

    # Локальные максимумы (scipy _local_maxima_1d): середина плато
    midpoints = []
    left_edges = []
    right_edges = []
    i = 0
    i_max = n - 1
    while i < i_max:
        i += 1
        if values[i - 1] < values[i]:
            i_ahead = i + 1
            while i_ahead < i_max and values[i_ahead] == values[i]:
                i_ahead += 1
            if values[i_ahead] < values[i]:
                left_edges.append(i)
                right_edges.append(i_ahead - 1)
                midpoints.append((i + i_ahead - 1) // 2)
                i = i_ahead

    if not midpoints:
        return np.array([])

    # Проминенция (scipy peak_prominences): расширяем окно влево/вправо,
    # пока не встретим строго более высокую точку или край данных.
    peaks = []
    for mid, le, re_ in zip(midpoints, left_edges, right_edges):
        h = values[mid]
        left_min = h
        j = le
        while j >= 0 and values[j] <= h:
            if values[j] < left_min:
                left_min = values[j]
            j -= 1
        right_min = h
        j = re_
        while j < n and values[j] <= h:
            if values[j] < right_min:
                right_min = values[j]
            j += 1
        if h - max(left_min, right_min) >= prominence:
            peaks.append(mid)
    return np.array(peaks)


def _polyfit_slope(x, y):
    """Наклон линейной регрессии без np.polyfit для скорости."""
    x = np.asarray(x, dtype=float)
    y = np.asarray(y, dtype=float)
    if len(x) < 2:
        return 0.0
    xc = x - np.mean(x)
    denom = np.dot(xc, xc)
    if denom == 0:
        return 0.0
    return float(np.dot(xc, y) / denom)


def _weighted_corr(a, b):
    """Корреляция Пирсона для двух одинаковых массивов."""
    a = np.asarray(a, dtype=float)
    b = np.asarray(b, dtype=float)
    if len(a) < 2 or len(b) < 2:
        return 0.0
    std_a = np.std(a)
    std_b = np.std(b)
    if std_a == 0 or std_b == 0:
        return 0.0
    return float(np.corrcoef(a, b)[0, 1])


# ------------------------------------------------------------
# Ядро поиска паттернов
# ------------------------------------------------------------

def _init_worker(hist_close, current_norm, current_vol, current_trend, weights,
                 lookback_window, forecast_length, vol_thr, interval):
    global _W
    _W = {
        "hist_close": hist_close,
        "L": lookback_window,
        "F": forecast_length,
        "current_norm": current_norm,
        "current_vol": current_vol,
        "current_trend": current_trend,
        "weights": weights,
        "vol_thr": vol_thr,
        "interval": interval,
        "cur_tail": current_norm[-20:],
        "cw": current_norm * weights,
        "xc": np.arange(lookback_window) - np.mean(np.arange(lookback_window)),
        "xc_denom": None,
        "cur_peaks": None,
    }
    _W["xc_denom"] = np.dot(_W["xc"], _W["xc"])
    _W["cur_peaks"] = len(_find_peaks(current_norm, prominence=0.5)) if len(current_norm) > 10 else None


def _calculate_pattern_similarity(i):
    try:
        hist_close = _W["hist_close"]
        lookback_window = _W["L"]
        forecast_length = _W["F"]
        current_vol = _W["current_vol"]

        if i + lookback_window + forecast_length > len(hist_close):
            return (-1, None)

        hist_window = hist_close[i:i + lookback_window]
        hist_mean = np.mean(hist_window)
        hist_std = np.std(hist_window)
        if hist_std < 1e-5:
            return (-1, None)

        hist_norm = (hist_window - hist_mean) / hist_std
        hist_vol = np.std(hist_norm)

        vol_diff = abs(hist_vol - current_vol) / max(hist_vol, current_vol)
        if vol_diff > _W["vol_thr"]:
            return (-1, None)

        weighted_corr = _weighted_corr(_W["cw"], hist_norm * _W["weights"])

        dtw_dist = np.sum(np.abs(_W["cur_tail"] - hist_norm[-20:]))
        shape_sim = 1 / (1 + dtw_dist / 20) if dtw_dist > 0 else 1.0

        hist_trend = np.dot(_W["xc"], hist_norm) / _W["xc_denom"]
        current_trend = _W["current_trend"]
        trend_sim = 1 - abs(current_trend - hist_trend) / (
            abs(current_trend) + abs(hist_trend) + 1e-5
        )

        peak_sim = 0.5
        cur_peaks = _W["cur_peaks"]
        if cur_peaks is not None and len(hist_norm) > 10:
            try:
                hist_peaks = len(_find_peaks(hist_norm, prominence=0.5))
                max_peaks = max(cur_peaks, hist_peaks, 1)
                peak_sim = 1 - abs(cur_peaks - hist_peaks) / max_peaks
            except Exception:
                peak_sim = 0.5

        vol_sim = 1 - vol_diff

        similarity = (
            weighted_corr * 0.4
            + shape_sim * 0.25
            + trend_sim * 0.15
            + peak_sim * 0.1
            + vol_sim * 0.1
        )

        similarity_threshold = 0.65 if _W["interval"] == "1m" else 0.8
        return (similarity, i) if similarity > similarity_threshold else (-1, None)
    except Exception:
        return (-1, None)


def find_top_patterns(current_data, symbol=None, top_n=TOP_N_PATTERNS,
                      forecast_length=FORECAST_LENGTH, lookback_window=None,
                      check_stop_callback=None, interval=None):
    if symbol is None:
        symbol = DEFAULT_SYMBOL
    if lookback_window is None:
        lookback_window = LOOKBACK_WINDOW
    if interval is None:
        interval = INTERVAL

    if get_stop_flag(symbol):
        return []

    try:
        cache = init_historical_cache(symbol, interval=interval)
        hist_df = cache["df"]
        hist_close = cache["close"]
        hist_dates = cache["index"]

        if len(hist_df) < lookback_window + forecast_length + 100:
            return []
    except Exception as e:
        return []

    current_close = current_data["close"].iloc[-lookback_window:].values
    current_mean = np.mean(current_close)
    current_std = np.std(current_close)
    if current_std < 1e-5:
        return []

    current_norm = (current_close - current_mean) / current_std
    current_vol = np.std(current_norm)
    current_trend = _polyfit_slope(np.arange(lookback_window), current_norm)

    weights = np.linspace(0.3, 1.7, lookback_window)
    weights = weights / np.sum(weights)

    search_step = 1 if interval == "1m" else 2
    total_items = len(range(0, len(hist_close) - lookback_window - forecast_length, search_step))
    if total_items <= 0:
        return []

    indices = range(0, len(hist_close) - lookback_window - forecast_length, search_step)

    _init_worker(
        hist_close, current_norm, current_vol, current_trend, weights,
        lookback_window, forecast_length, VOLATILITY_DIFF_THRESHOLD, interval
    )

    results = []
    for idx in indices:
        if check_stop_callback and check_stop_callback():
            return []
        res = _calculate_pattern_similarity(idx)
        if res[0] > 0:
            results.append(res)

    unique_results = []
    used_windows = set()
    min_time_diff = timedelta(days=1)

    for similarity, idx in sorted(results, key=lambda x: -x[0]):
        if len(unique_results) >= top_n * 2:
            break
        pattern_date = hist_dates[idx]
        is_duplicate = False
        for _, used_idx in unique_results:
            if abs(pattern_date - hist_dates[used_idx]) < min_time_diff:
                is_duplicate = True
                break
        if not is_duplicate:
            current_pattern = hist_close[idx:idx + lookback_window]
            for _, used_idx in unique_results:
                used_pattern = hist_close[used_idx:used_idx + lookback_window]
                if np.allclose(current_pattern, used_pattern, rtol=0.05):
                    is_duplicate = True
                    break
        if not is_duplicate:
            unique_results.append((similarity, idx))
            used_windows.add(idx)

    top_patterns = []
    for similarity, idx in sorted(unique_results, key=lambda x: -x[0])[:top_n]:
        if check_stop_callback and check_stop_callback():
            break
        pattern = hist_df.iloc[idx:idx + lookback_window + forecast_length]
        top_patterns.append((similarity, pattern, idx))

    return top_patterns


def analyze_pattern(similarity, pattern, pattern_index, current_price,
                    forecast_length=FORECAST_LENGTH, lookback_window=None):
    if lookback_window is None:
        lookback_window = LOOKBACK_WINDOW

    hist_pattern = pattern.iloc[:lookback_window]
    forecast_data = pattern.iloc[lookback_window:lookback_window + forecast_length]

    if len(forecast_data) == 0:
        return {
            "similarity": similarity,
            "start_date": hist_pattern.index[0],
            "end_date": hist_pattern.index[-1],
            "forecast_start": None,
            "forecast_end": None,
            "forecast_change": 0,
            "forecast_pct_change": 0,
            "forecast_direction": "⌀ Без изменений",
            "forecast_volatility": 0,
            "pattern_volatility": 0,
            "trend": 0,
            "pattern_index": pattern_index,
        }

    forecast_start_price = forecast_data["close"].iloc[0]
    forecast_end_price = forecast_data["close"].iloc[-1]
    forecast_change = forecast_end_price - forecast_start_price
    forecast_pct_change = (forecast_end_price / forecast_start_price - 1) * 100
    forecast_direction = "▲ Рост" if forecast_pct_change > 0 else "▼ Снижение"

    forecast_volatility = forecast_data["close"].pct_change().std() * 100
    pattern_volatility = hist_pattern["close"].pct_change().std() * 100
    pattern_trend = _polyfit_slope(np.arange(len(hist_pattern)), hist_pattern["close"])

    hist_high = hist_pattern["high"].max()
    hist_low = hist_pattern["low"].min()
    hist_high_date = hist_pattern["high"].idxmax()
    hist_low_date = hist_pattern["low"].idxmin()

    forecast_high = forecast_data["high"].max()
    forecast_low = forecast_data["low"].min()
    forecast_high_date = forecast_data["high"].idxmax()
    forecast_low_date = forecast_data["low"].idxmin()

    return {
        "similarity": similarity,
        "start_date": hist_pattern.index[0],
        "end_date": hist_pattern.index[-1],
        "forecast_start": forecast_data.index[0],
        "forecast_end": forecast_data.index[-1],
        "forecast_change": forecast_change,
        "forecast_pct_change": forecast_pct_change,
        "forecast_start_price": forecast_start_price,
        "forecast_end_price": forecast_end_price,
        "forecast_direction": forecast_direction,
        "forecast_volatility": forecast_volatility,
        "pattern_volatility": pattern_volatility,
        "trend": pattern_trend,
        "pattern_index": pattern_index,
        "hist_high": hist_high,
        "hist_low": hist_low,
        "hist_high_date": hist_high_date,
        "hist_low_date": hist_low_date,
        "forecast_high": forecast_high,
        "forecast_low": forecast_low,
        "forecast_high_date": forecast_high_date,
        "forecast_low_date": forecast_low_date,
    }


def generate_forecast(current_data, symbol=None, show_plots=True,
                      forecast_length=FORECAST_LENGTH, lookback_window=None,
                      top_n_patterns=TOP_N_PATTERNS,
                      min_signal_threshold=MIN_SIGNAL_THRESHOLD,
                      check_stop_callback=None, interval=None):
    if symbol is None:
        symbol = DEFAULT_SYMBOL
    if lookback_window is None:
        lookback_window = LOOKBACK_WINDOW
    if interval is None:
        interval = INTERVAL

    top_patterns = find_top_patterns(
        current_data, symbol=symbol, top_n=top_n_patterns,
        forecast_length=forecast_length, lookback_window=lookback_window,
        check_stop_callback=check_stop_callback, interval=interval,
    )

    if not top_patterns:
        neutral_analysis = {
            "similarity": 0.0,
            "forecast_pct_change": 0.0,
            "forecast_direction": "⌀ Без сигнала",
            "forecast_volatility": current_data["close"].pct_change().std() * 100
                if len(current_data) > 1 else 0,
            "pattern_volatility": current_data["close"].pct_change().std() * 100
                if len(current_data) > 1 else 0,
            "trend": 0,
            "hist_high": current_data["high"].max(),
            "hist_low": current_data["low"].min(),
            "hist_high_date": current_data["high"].idxmax(),
            "hist_low_date": current_data["low"].idxmin(),
            "forecast_high": current_data["high"].max(),
            "forecast_low": current_data["low"].min(),
            "forecast_high_date": current_data["high"].idxmax(),
            "forecast_low_date": current_data["low"].idxmin(),
            "forecast_change": 0,
            "forecast_start": None,
            "forecast_end": None,
            "start_date": current_data.index[0],
            "end_date": current_data.index[-1],
            "pattern_index": -1,
        }
        analyses = [neutral_analysis]
        return analyses, top_patterns

    analyses = []
    current_price = current_data["close"].iloc[-1]
    for similarity, pattern, idx in top_patterns:
        analysis = analyze_pattern(
            similarity, pattern, idx, current_price,
            forecast_length=forecast_length, lookback_window=lookback_window,
        )
        analyses.append(analysis)
    return analyses, top_patterns


def _candles_to_list(df, timestamp_key="timestamp"):
    """Конвертирует DataFrame свечей в JSON-список."""
    out = []
    for ts, row in df.iterrows():
        out.append({
            timestamp_key: ts.isoformat() if hasattr(ts, "isoformat") else str(ts),
            "open": float(row["open"]),
            "high": float(row["high"]),
            "low": float(row["low"]),
            "close": float(row["close"]),
            "volume": float(row["volume"]) if "volume" in df.columns and row["volume"] is not None else 0.0,
        })
    return out


def build_signal_windows(res, symbol=None):
    """Формирует JSON-сериализуемые 'График' и 'Движение' окна по результату анализа."""
    if not res or not res.get("top_patterns"):
        return {}

    analyses = res.get("analyses", [])
    top_patterns = res.get("top_patterns", [])
    current_data = res.get("current_data")
    symbol = symbol or res.get("symbol", "")
    signal_type = res.get("signal_type", "flat")
    strength = res.get("strength", 0)
    lookback_window = res.get("lookback_window", LOOKBACK_WINDOW)
    forecast_length = res.get("forecast_length", FORECAST_LENGTH)
    current_price = res.get("current_price", 0.0)
    forecast_price = res.get("forecast_price", current_price)
    avg_pct_change = res.get("forecast_pct_change", 0.0)

    up_count = res.get("long_count", 0)
    down_count = res.get("short_count", 0)
    is_long = signal_type == "long"

    # SL/TP (аналог create_summary_window / show_signal)
    if current_data is not None:
        try:
            atr = float(current_data["high"].iloc[-20:].max() - current_data["low"].iloc[-20:].min())
        except Exception:
            atr = 0.0
    else:
        atr = 0.0
    if is_long:
        stop_loss = current_price * (1 - max(1.0, (1.5 * atr / current_price * 100)) / LEVERAGE / 100)
        take_profit = current_price * (1 + min(5.0, max(1.5, abs(avg_pct_change) * 0.7)) / 100)
    else:
        stop_loss = current_price * (1 + max(1.0, (1.5 * atr / current_price * 100)) / LEVERAGE / 100)
        take_profit = current_price * (1 - min(5.0, max(1.5, abs(avg_pct_change) * 0.7)) / 100)

    # Текущий паттерн
    current_candles = []
    if current_data is not None and len(current_data) >= lookback_window:
        current_candles = _candles_to_list(current_data.iloc[-lookback_window:])

    patterns = []
    for i, ((similarity, pattern_df, idx), a) in enumerate(zip(top_patterns, analyses)):
        if a is None:
            continue
        hist = pattern_df.iloc[:lookback_window]
        forecast = pattern_df.iloc[lookback_window:lookback_window + forecast_length]
        pattern_candles = _candles_to_list(hist) + _candles_to_list(forecast)
        patterns.append({
            "index": i,
            "similarity": float(similarity),
            "date": str(a.get("start_date", "")),
            "forecast_pct": float(a.get("forecast_pct_change", 0.0)),
            "direction": a.get("forecast_direction", ""),
            "candles": pattern_candles,
        })

    pct = [a.get("forecast_pct_change", 0) for a in analyses]
    avg_sim = sum(p[0] for p in top_patterns) / len(top_patterns) if top_patterns else 0
    avg_vol = sum(a.get("forecast_volatility", 0) for a in analyses) / len(analyses) if analyses else 0
    best_pct, worst_pct = (max(pct), min(pct)) if pct else (0, 0)

    return {
        "symbol": symbol,
        "min_signal_threshold": int(res.get("min_signal_threshold", MIN_SIGNAL_THRESHOLD)),
        "current_price": float(current_price),
        "forecast_price": float(forecast_price),
        "avg_pct_change": float(avg_pct_change),
        "signal_type": signal_type,
        "strength": int(strength),
        "up_count": int(up_count),
        "down_count": int(down_count),
        "lookback_window": int(lookback_window),
        "forecast_length": int(forecast_length),
        "target": float(forecast_price),
        "stop_loss": float(stop_loss),
        "take_profit": float(take_profit),
        "atr": float(atr),
        "best_pct": float(best_pct),
        "worst_pct": float(worst_pct),
        "avg_sim": float(avg_sim),
        "avg_vol": float(avg_vol),
        "current_candles": current_candles,
        "patterns": patterns,
    }


def run_analysis_job(symbol=None, top_n_patterns=TOP_N_PATTERNS,
                     min_signal_threshold=MIN_SIGNAL_THRESHOLD,
                     show_all_signals=False, check_stop_callback=None,
                     lookback_window=None, forecast_length=None, interval=None):
    if symbol is None:
        symbol = DEFAULT_SYMBOL

    lb = lookback_window or LOOKBACK_WINDOW
    fc = forecast_length or FORECAST_LENGTH
    iv = interval or INTERVAL

    current_data = get_realtime_data(symbol, interval=iv)
    if current_data is None or len(current_data) < lb:
        return None

    analyses, top_patterns = generate_forecast(
        current_data, symbol=symbol, show_plots=False,
        forecast_length=fc, lookback_window=lb,
        top_n_patterns=top_n_patterns,
        min_signal_threshold=min_signal_threshold,
        check_stop_callback=check_stop_callback,
        interval=iv,
    )

    long_count = 0
    short_count = 0
    for analysis in analyses:
        if analysis["forecast_direction"] == "▲ Рост":
            long_count += 1
        elif analysis["forecast_direction"] == "▼ Снижение":
            short_count += 1

    should_show_long = show_all_signals or long_count >= min_signal_threshold
    should_show_short = show_all_signals or short_count >= min_signal_threshold

    if not top_patterns:
        return {
            "signal_type": "flat",
            "strength": 0,
            "top_patterns": [],
            "analyses": analyses,
            "current_data": current_data,
            "symbol": symbol,
            "lookback_window": LOOKBACK_WINDOW,
            "top_n_patterns": top_n_patterns,
            "forecast_length": FORECAST_LENGTH,
            "min_signal_threshold": min_signal_threshold,
        }

    signal_type = "long" if long_count >= short_count else "short"
    strength = max(long_count, short_count)

    # Средний процент изменения топ-5 паттернов, совпадающих с сигналом
    pct_changes = []
    for analysis in analyses[:5]:
        if analysis["forecast_direction"] == ("▲ Рост" if signal_type == "long" else "▼ Снижение"):
            pct_changes.append(analysis["forecast_pct_change"])
    avg_pct_change = float(np.mean(pct_changes)) if pct_changes else 1.5

    current_price = current_data["close"].iloc[-1]
    forecast_price = current_price * (1 + avg_pct_change / 100.0)

    return {
        "signal_type": signal_type,
        "strength": strength,
        "top_patterns": top_patterns,
        "analyses": analyses,
        "current_data": current_data,
        "symbol": symbol,
        "lookback_window": LOOKBACK_WINDOW,
        "top_n_patterns": top_n_patterns,
        "forecast_length": FORECAST_LENGTH,
        "min_signal_threshold": min_signal_threshold,
        "forecast_pct_change": avg_pct_change,
        "forecast_price": forecast_price,
        "current_price": current_price,
        "long_count": long_count,
        "short_count": short_count,
        "should_show_long": should_show_long,
        "should_show_short": should_show_short,
    }
