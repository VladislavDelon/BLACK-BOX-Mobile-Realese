# exchange_api.py
# Подключение к биржам. Binance Futures + MEXC Futures.

import json
import time
import hmac
import hashlib
import urllib.parse
from decimal import Decimal, ROUND_DOWN

import requests


class ExchangeError(Exception):
    pass


class BinanceAPI:
    """Binance USD-M Futures API."""
    supports_embedded_tp_sl = False

    def __init__(self, api_key: str, api_secret: str, testnet: bool = False):
        self.api_key = api_key.strip()
        self.api_secret = api_secret.strip()
        self.testnet = testnet
        self.base_url = "https://testnet.binancefuture.com" if testnet else "https://fapi.binance.com"
        self._filters = {}

    def _signature(self, query: str) -> str:
        return hmac.new(
            self.api_secret.encode("utf-8"),
            query.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()

    def _get(self, path: str, params: dict = None, signed: bool = False) -> dict:
        params = params or {}
        if signed:
            params["timestamp"] = int(time.time() * 1000)
            params["recvWindow"] = 10000
        query = urllib.parse.urlencode(params)
        if signed:
            query += f"&signature={self._signature(query)}"
        url = f"{self.base_url}{path}?{query}"
        headers = {"X-MBX-APIKEY": self.api_key}
        r = requests.get(url, headers=headers, timeout=15)
        return self._handle(r)

    def _post(self, path: str, params: dict = None, signed: bool = True) -> dict:
        params = params or {}
        if signed:
            params["timestamp"] = int(time.time() * 1000)
            params["recvWindow"] = 10000
        query = urllib.parse.urlencode(params)
        if signed:
            query += f"&signature={self._signature(query)}"
        url = f"{self.base_url}{path}?{query}"
        headers = {"X-MBX-APIKEY": self.api_key}
        r = requests.post(url, headers=headers, timeout=15)
        return self._handle(r)

    def _handle(self, r) -> dict:
        try:
            data = r.json()
        except Exception:
            data = {"_raw": r.text}
        if r.status_code >= 400:
            msg = data.get("msg", r.text) if isinstance(data, dict) else r.text
            raise ExchangeError(f"Binance API error {r.status_code}: {msg}")
        return data

    def test_connection(self) -> bool:
        try:
            self._get("/fapi/v2/account", signed=True)
            return True
        except Exception:
            return False

    def get_balance(self, asset: str = "USDT") -> float:
        data = self._get("/fapi/v2/balance", signed=True)
        for b in data:
            if b.get("asset") == asset:
                return float(b.get("availableBalance", 0))
        return 0.0

    def _load_filters(self, symbol: str):
        if symbol in self._filters:
            return
        info = requests.get(f"{self.base_url}/fapi/v1/exchangeInfo", timeout=15).json()
        for s in info.get("symbols", []):
            if s["symbol"] == symbol:
                filters = {}
                for f in s.get("filters", []):
                    if f["filterType"] == "LOT_SIZE":
                        filters["step"] = float(f["stepSize"])
                        filters["min_qty"] = float(f["minQty"])
                    elif f["filterType"] == "PRICE_FILTER":
                        filters["tick"] = float(f["tickSize"])
                    elif f["filterType"] == "MIN_NOTIONAL":
                        filters["min_notional"] = float(f.get("notional", f.get("minNotional", 0)))
                self._filters[symbol] = filters
                return
        self._filters[symbol] = {}

    def round_qty(self, symbol: str, qty: float) -> float:
        self._load_filters(symbol)
        step = self._filters.get(symbol, {}).get("step", 0.001)
        d = Decimal(str(step))
        q = Decimal(str(qty))
        rounded = q.quantize(d, rounding=ROUND_DOWN)
        return float(rounded)

    def round_price(self, symbol: str, price: float) -> float:
        self._load_filters(symbol)
        tick = self._filters.get(symbol, {}).get("tick", 0.01)
        d = Decimal(str(tick))
        p = Decimal(str(price))
        return float(p.quantize(d, rounding=ROUND_DOWN))

    def set_leverage(self, symbol: str, leverage: int) -> dict:
        return self._post(
            "/fapi/v1/leverage",
            {"symbol": symbol, "leverage": leverage},
            signed=True,
        )

    def get_klines(self, symbol: str, interval: str, limit: int = 500):
        """Возвращает свечи как список [time, open, high, low, close, volume]."""
        r = requests.get(
            f"{self.base_url}/fapi/v1/klines",
            params={"symbol": symbol, "interval": interval, "limit": limit},
            timeout=15,
        )
        if r.status_code != 200:
            raise ExchangeError(f"Binance klines error {r.status_code}: {r.text}")
        return [
            [
                int(c[0]),
                float(c[1]),
                float(c[2]),
                float(c[3]),
                float(c[4]),
                float(c[5]),
            ]
            for c in r.json()
        ]

    def get_price(self, symbol: str) -> dict:
        """Возвращает last/bid/ask по фьючерсному символу."""
        s = symbol.upper()
        try:
            r = requests.get(
                f"{self.base_url}/fapi/v1/ticker/24hr",
                params={"symbol": s},
                timeout=15,
            )
            if r.status_code != 200:
                raise ExchangeError(f"Binance price error {r.status_code}: {r.text}")
            data = r.json()
            return {
                "last": float(data.get("lastPrice", 0)),
                "bid": float(data.get("bidPrice", 0)),
                "ask": float(data.get("askPrice", 0)),
                "change_pct": float(data.get("priceChangePercent", 0)),
            }
        except Exception as e:
            raise ExchangeError(f"Binance get_price error: {e}")

    def get_usdt_symbols(self):
        """Список USDT-M фьючерсных пар."""
        try:
            r = requests.get(
                f"{self.base_url}/fapi/v1/exchangeInfo", timeout=15
            )
            data = r.json()
            return sorted(
                s["symbol"]
                for s in data.get("symbols", [])
                if s.get("quoteAsset") == "USDT" and s.get("status") == "TRADING"
            )
        except Exception as e:
            raise ExchangeError(f"symbols fetch error: {e}")

    def place_market_order(self, symbol: str, side: str, quantity: float) -> dict:
        """side: 'BUY' or 'SELL' (one-way mode). quantity already rounded."""
        return self._post(
            "/fapi/v1/order",
            {
                "symbol": symbol,
                "side": side,
                "type": "MARKET",
                "quantity": f"{quantity:.10f}".rstrip("0").rstrip("."),
            },
            signed=True,
        )

    def place_stop_order(self, symbol: str, side: str, stop_price: float, close_position: bool = True) -> dict:
        """STOP_MARKET для SL."""
        return self._post(
            "/fapi/v1/order",
            {
                "symbol": symbol,
                "side": side,
                "type": "STOP_MARKET",
                "stopPrice": f"{stop_price:.10f}".rstrip("0").rstrip("."),
                "closePosition": "true" if close_position else "false",
            },
            signed=True,
        )

    def place_take_profit_order(self, symbol: str, side: str, stop_price: float, close_position: bool = True) -> dict:
        """TAKE_PROFIT_MARKET для TP."""
        return self._post(
            "/fapi/v1/order",
            {
                "symbol": symbol,
                "side": side,
                "type": "TAKE_PROFIT_MARKET",
                "stopPrice": f"{stop_price:.10f}".rstrip("0").rstrip("."),
                "closePosition": "true" if close_position else "false",
            },
            signed=True,
        )

    def get_positions(self) -> list:
        """Открытые фьючерсные позиции (positionRisk v2)."""
        data = self._get("/fapi/v2/positionRisk", signed=True)
        out = []
        for p in data if isinstance(data, list) else []:
            amt = float(p.get("positionAmt", 0) or 0)
            if amt == 0:
                continue
            out.append({
                "symbol": p.get("symbol", ""),
                "side": "LONG" if amt > 0 else "SHORT",
                "qty": abs(amt),
                "entry_price": float(p.get("entryPrice", 0) or 0),
                "mark_price": float(p.get("markPrice", 0) or 0),
                "pnl": float(p.get("unRealizedProfit", 0) or 0),
                "leverage": int(float(p.get("leverage", 0) or 0)),
                "liq_price": float(p.get("liquidationPrice", 0) or 0),
            })
        return out


class MEXCAPI:
    """MEXC Futures API (contract.mexc.com)."""

    supports_embedded_tp_sl = True

    def __init__(self, api_key: str, api_secret: str, testnet: bool = False):
        self.api_key = api_key.strip()
        self.api_secret = api_secret.strip()
        self.testnet = testnet
        self.base_url = "https://contract.mexc.com"
        self._filters = {}

    # --------------------------------------------------------
    @staticmethod
    def _symbol(symbol: str) -> str:
        """Приводит символ к формату MEXC: BTCUSDT -> BTC_USDT."""
        s = symbol.upper().replace("/", "").replace("-", "")
        if "_" in s:
            return s
        for q in ("USDT", "USDC", "BUSD", "BTC", "ETH", "BNB"):
            if s.endswith(q) and len(s) > len(q):
                return f"{s[:-len(q)]}_{q}"
        return s

    def _sign(self, param_str: str) -> str:
        return hmac.new(
            self.api_secret.encode("utf-8"),
            param_str.encode("utf-8"),
            hashlib.sha256,
        ).hexdigest()

    def _signed_headers(self, param_str: str) -> dict:
        ts = int(time.time() * 1000)
        sign_str = f"{self.api_key}{ts}{param_str}"
        return {
            "ApiKey": self.api_key,
            "Request-Time": str(ts),
            "Signature": self._sign(sign_str),
            "Content-Type": "application/json",
        }

    def _get(self, path: str, params: dict = None, signed: bool = False) -> dict:
        params = params or {}
        if signed:
            query = urllib.parse.urlencode(sorted(params.items()))
            headers = self._signed_headers(query)
            url = f"{self.base_url}{path}"
            if query:
                url += f"?{query}"
        else:
            headers = {"User-Agent": "Mozilla/5.0"}
            url = f"{self.base_url}{path}"
            if params:
                url += f"?{urllib.parse.urlencode(params)}"
        r = requests.get(url, headers=headers, timeout=15)
        return self._handle(r)

    def _post(self, path: str, params: dict = None, signed: bool = True) -> dict:
        params = params or {}
        body = json.dumps(params, separators=(",", ":"))
        if signed:
            headers = self._signed_headers(body)
        else:
            headers = {
                "Content-Type": "application/json",
                "User-Agent": "Mozilla/5.0",
            }
        r = requests.post(f"{self.base_url}{path}", data=body, headers=headers, timeout=15)
        return self._handle(r)

    def _handle(self, r) -> dict:
        try:
            data = r.json()
        except Exception:
            data = {"_raw": r.text}
        if r.status_code >= 400 or (isinstance(data, dict) and data.get("success") is False):
            msg = data.get("message") or data.get("msg") or r.text
            raise ExchangeError(f"MEXC API error {r.status_code}: {msg}")
        return data

    # --------------------------------------------------------
    def test_connection(self) -> bool:
        try:
            data = self._get("/api/v1/private/account/assets", signed=True)
            return bool(data.get("success")) and data.get("code") == 0
        except Exception:
            return False

    def get_balance(self, asset: str = "USDT") -> float:
        data = self._get("/api/v1/private/account/assets", signed=True)
        for b in data.get("data", []):
            if b.get("currency") == asset:
                return float(b.get("availableBalance", 0))
        return 0.0

    def _load_filters(self, symbol: str):
        mexc = self._symbol(symbol)
        if mexc in self._filters:
            return
        try:
            r = requests.get(
                f"{self.base_url}/api/v1/contract/detail?symbol={mexc}",
                timeout=15,
            )
            d = r.json().get("data", {})
            if isinstance(d, list) and d:
                d = d[0]
            if not isinstance(d, dict):
                d = {}
        except Exception:
            d = {}
        self._filters[mexc] = {
            "contractSize": float(d.get("contractSize", 1) or 1),
            "volScale": int(d.get("volScale", 0) or 0),
            "priceUnit": float(d.get("priceUnit", 0.01) or 0.01),
            "minVol": float(d.get("minVol", 1) or 1),
            "maxVol": float(d.get("maxVol", 999999) or 999999),
            "minLeverage": int(d.get("minLeverage", 1) or 1),
            "maxLeverage": int(d.get("maxLeverage", 100) or 100),
        }

    def round_qty(self, symbol: str, qty: float) -> float:
        """Возвращает количество в контрактах (MEXC vol)."""
        self._load_filters(symbol)
        mexc = self._symbol(symbol)
        f = self._filters.get(mexc, {})
        contract_size = float(f.get("contractSize", 1.0) or 1.0)
        vol_scale = int(f.get("volScale", 0) or 0)
        min_vol = float(f.get("minVol", 1) or 1)

        vol = qty / contract_size if contract_size > 0 else qty
        if vol_scale > 0:
            step = 10 ** (-vol_scale)
        else:
            step = 1
        d = Decimal(str(step))
        q = Decimal(str(vol))
        vol = float(q.quantize(d, rounding=ROUND_DOWN))
        if vol < min_vol:
            return 0.0
        return vol

    def round_price(self, symbol: str, price: float) -> float:
        self._load_filters(symbol)
        mexc = self._symbol(symbol)
        tick = float(self._filters.get(mexc, {}).get("priceUnit", 0.01) or 0.01)
        d = Decimal(str(tick))
        p = Decimal(str(price))
        return float(p.quantize(d, rounding=ROUND_DOWN))

    def set_leverage(self, symbol: str, leverage: int) -> dict:
        # Плечо задаётся прямо в ордере (order/create)
        return {}

    def get_klines(self, symbol: str, interval: str, limit: int = 500):
        """Возвращает свечи MEXC futures [time, open, high, low, close, volume]."""
        mexc = self._symbol(symbol)
        interval_map = {
            "1m": "Min1", "3m": "Min3", "5m": "Min5", "15m": "Min15",
            "30m": "Min30", "1h": "Min60", "2h": "Min120", "4h": "Min240",
            "1d": "Day1", "1w": "Week1",
        }
        mexc_interval = interval_map.get(interval, interval)
        r = requests.get(
            f"{self.base_url}/api/v1/contract/kline",
            params={"symbol": mexc, "interval": mexc_interval},
            timeout=15,
        )
        data = self._handle(r)
        rows = data.get("data", {}).get("time", []) if isinstance(data, dict) else []
        if not rows:
            return []
        rows = rows[-limit:] if len(rows) > limit else rows
        out = []
        for t, row in rows:
            # row: [open, high, low, close, vol?, ...]
            out.append([
                int(t), float(row[0]), float(row[1]), float(row[2]),
                float(row[3]), float(row[4]) if len(row) > 4 else 0.0,
            ])
        return out

    def get_price(self, symbol: str) -> dict:
        """Возвращает last/bid/ask по фьючерсному символу MEXC."""
        mexc = self._symbol(symbol)
        try:
            r = requests.get(
                f"{self.base_url}/api/v1/contract/ticker?symbol={mexc}",
                timeout=15,
            )
            if r.status_code != 200:
                raise ExchangeError(f"MEXC price error {r.status_code}: {r.text}")
            d = r.json().get("data", {})
            if isinstance(d, list) and d:
                d = d[0]
            return {
                "last": float(d.get("lastPrice", 0)),
                "bid": float(d.get("bid1Price", d.get("bidPrice", 0))),
                "ask": float(d.get("ask1Price", d.get("askPrice", 0))),
                "change_pct": float(d.get("riseFallRate", 0)) * 100,
            }
        except Exception as e:
            raise ExchangeError(f"MEXC get_price error: {e}")

    def get_usdt_symbols(self):
        try:
            r = requests.get(
                f"{self.base_url}/api/v1/contract/detail", timeout=15
            )
            data = r.json()
            symbols = []
            for item in data.get("data", []):
                s = item.get("symbol", "")
                if "_USDT" in s:
                    symbols.append(s.replace("_", ""))
            return sorted(symbols)
        except Exception as e:
            raise ExchangeError(f"MEXC symbols error: {e}")

    def _last_price(self, symbol: str) -> float:
        try:
            r = requests.get(
                f"{self.base_url}/api/v1/contract/ticker?symbol={symbol}",
                timeout=15,
            )
            return float(r.json().get("data", {}).get("lastPrice", 0))
        except Exception:
            return 0.0

    def place_market_order(
        self,
        symbol: str,
        side: str,
        quantity: float,
        leverage: int = 1,
        stop_loss: float = None,
        take_profit: float = None,
    ) -> dict:
        """side: 'BUY' or 'SELL'. quantity уже в контрактах (vol)."""
        mexc = self._symbol(symbol)
        vol = quantity
        f = self._filters.get(mexc, {})
        if int(f.get("volScale", 0)) == 0:
            vol = int(quantity)

        if side.upper() == "BUY":
            side_code = 1  # open long
        else:
            side_code = 3  # open short

        price = self._last_price(mexc)
        payload = {
            "symbol": mexc,
            "price": price,
            "vol": vol,
            "leverage": int(leverage),
            "side": side_code,
            "type": 5,        # market
            "openType": 2,    # cross
            "positionMode": 2,  # one-way
        }
        if stop_loss is not None:
            payload["stopLossPrice"] = self.round_price(mexc, stop_loss)
        if take_profit is not None:
            payload["takeProfitPrice"] = self.round_price(mexc, take_profit)
        return self._post("/api/v1/private/order/create", payload, signed=True)

    def get_positions(self) -> list:
        """Открытые позиции MEXC futures."""
        data = self._get("/api/v1/private/position/open_positions", signed=True)
        out = []
        items = data.get("data", []) if isinstance(data, dict) else []
        for p in items:
            hold_vol = float(p.get("holdVol", 0) or 0)
            if hold_vol <= 0:
                continue
            ptype = int(p.get("positionType", 1) or 1)
            out.append({
                "symbol": str(p.get("symbol", "")).replace("_", ""),
                "side": "LONG" if ptype == 1 else "SHORT",
                "qty": hold_vol,
                "entry_price": float(p.get("holdAvgPrice") or p.get("openAvgPrice") or 0),
                "mark_price": float(p.get("fairPrice") or 0),
                "pnl": float(p.get("profit") or 0),
                "leverage": int(p.get("leverage", 0) or 0),
                "liq_price": float(p.get("liquidatePrice", 0) or 0),
            })
        return out

    def place_stop_order(self, *args, **kwargs) -> dict:
        # TP/SL задаются в основном ордере для MEXC
        return {}

    def place_take_profit_order(self, *args, **kwargs) -> dict:
        # TP/SL задаются в основном ордере для MEXC
        return {}


# ==========================================================
# Обёртка
# ==========================================================

def get_api(exchange: str, api_key: str, api_secret: str, **kwargs):
    exchange = exchange.lower().replace(" ", "")
    if exchange == "binancefutures" or exchange == "binance":
        return BinanceAPI(api_key, api_secret, kwargs.get("testnet", False))
    if exchange == "mexcfutures" or exchange == "mexc":
        return MEXCAPI(api_key, api_secret, kwargs.get("testnet", False))
    raise ExchangeError(f"Биржа '{exchange}' пока не поддерживается.")
