# prices.py — сравнение цен на разных биржах (cross-prices).
# Порт с десктопного cross_prices_app.py.

import concurrent.futures
import requests


def _symbol_plain(base, quote):
    return f"{base.upper()}{quote.upper()}"


def _symbol_dash(base, quote):
    return f"{base.upper()}-{quote.upper()}"


def _fetch(url, headers=None, verify=True):
    h = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"}
    if headers:
        h.update(headers)
    r = requests.get(url, headers=h, timeout=10, verify=verify)
    r.raise_for_status()
    return r.json()


def _parse_binance(data):
    last = float(data["lastPrice"])
    chg = float(data["priceChangePercent"])
    return last, chg


def _parse_binance_futures(data):
    return _parse_binance(data)


def _parse_mexc(data):
    last = float(data["lastPrice"])
    chg = float(data["priceChangePercent"])
    return last, chg


def _parse_bybit(data):
    tick = data.get("result", {}).get("list", [])
    if not tick:
        raise ValueError("no symbol")
    item = tick[0]
    last = float(item["lastPrice"])
    chg = float(item["price24hPcnt"]) * 100
    return last, chg


def _parse_okx(data):
    tick = data.get("data", [])
    if not tick:
        raise ValueError("no symbol")
    item = tick[0]
    last = float(item["last"])
    chg = float(item.get("chg%", "0").replace("+", ""))
    return last, chg


def _parse_kucoin(data):
    tick = data.get("data", {})
    if not tick:
        raise ValueError("no symbol")
    last = float(tick["last"])
    chg = float(tick.get("changeRate", 0)) * 100
    return last, chg


EXCHANGES = [
    {
        "name": "Binance",
        "market": "Spot",
        "symbol": _symbol_plain,
        "url": "https://api.binance.com/api/v3/ticker/24hr?symbol={symbol}",
        "parse": _parse_binance,
        "verify": True,
    },
    {
        "name": "Binance",
        "market": "Futures",
        "symbol": _symbol_plain,
        "url": "https://fapi.binance.com/fapi/v1/ticker/24hr?symbol={symbol}",
        "parse": _parse_binance_futures,
        "verify": True,
    },
    {
        "name": "MEXC",
        "market": "Spot",
        "symbol": _symbol_plain,
        "url": "https://api.mexc.com/api/v3/ticker/24hr?symbol={symbol}",
        "parse": _parse_mexc,
        "verify": True,
    },
    {
        "name": "Bybit",
        "market": "Spot",
        "symbol": _symbol_plain,
        "url": "https://api.bybit.com/v5/market/tickers?category=spot&symbol={symbol}",
        "parse": _parse_bybit,
        "verify": True,
    },
    {
        "name": "OKX",
        "market": "Spot",
        "symbol": _symbol_dash,
        "url": "https://www.okx.com/api/v5/market/ticker?instId={symbol}",
        "parse": _parse_okx,
        "verify": True,
    },
    {
        "name": "KuCoin",
        "market": "Spot",
        "symbol": _symbol_dash,
        "url": "https://api.kucoin.com/api/v1/market/stats?symbol={symbol}",
        "parse": _parse_kucoin,
        "verify": True,
    },
]


def _fetch_one(ex, base, quote):
    try:
        symbol = ex["symbol"](base, quote)
        url = ex["url"].format(symbol=symbol)
        data = _fetch(url, verify=ex.get("verify", True))
        last, chg = ex["parse"](data)
        return {
            "exchange": ex["name"],
            "market": ex["market"],
            "symbol": symbol,
            "price": last,
            "change_pct": chg,
            "ok": True,
        }
    except Exception as e:
        return {
            "exchange": ex["name"],
            "market": ex["market"],
            "symbol": ex["symbol"](base, quote),
            "price": 0.0,
            "change_pct": 0.0,
            "ok": False,
            "error": str(e),
        }


def get_all_prices(base: str, quote: str = "USDT"):
    """Возвращает список цен со всех поддерживаемых бирж."""
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(EXCHANGES)) as executor:
        futures = [executor.submit(_fetch_one, ex, base, quote) for ex in EXCHANGES]
        out = [f.result() for f in concurrent.futures.as_completed(futures)]
    # Сортируем по исходному порядку бирж для стабильности.
    order = {ex["name"]: i for i, ex in enumerate(EXCHANGES)}
    out.sort(key=lambda p: order.get(p["exchange"], 999))
    return {"ok": True, "base": base.upper(), "quote": quote.upper(), "prices": out}
