# bridge.py — мост между Kotlin/Flutter и Python-ядром BLACK BOX.
# Все функции возвращают JSON-совместимые dict, чтобы спокойно уходили через MethodChannel.

import json
import os
import threading
import time

from bbcore import exchange_api
from bbcore import auth
from bbcore import config
from bbcore import analysis
from bbcore import auto_trading
from bbcore import prices

# Папка для локальных данных задаётся из Kotlin (filesDir приложения)
_DATA_DIR = None


def init(data_dir: str):
    """Вызывается из Kotlin при старте. data_dir — приватная папка приложения."""
    global _DATA_DIR
    _DATA_DIR = data_dir
    os.environ["FILES_DIR"] = data_dir
    os.makedirs(_DATA_DIR, exist_ok=True)
    auth.init_data_dir(data_dir)
    return {"ok": True, "data_dir": _DATA_DIR}


def ping():
    return {"ok": True, "message": "python core alive"}


def _keys_path() -> str:
    return os.path.join(_DATA_DIR or ".", "exchange_keys.json")


def test_exchange(exchange: str, api_key: str, api_secret: str, testnet: bool = False):
    """Проверяет подключение к бирже и возвращает баланс USDT."""
    try:
        api = exchange_api.get_api(exchange, api_key, api_secret, testnet=testnet)
    except Exception as e:
        return {"ok": False, "error": str(e)}

    if not api.test_connection():
        return {"ok": False, "error": "Не удалось подключиться. Проверьте ключи."}

    try:
        balance = api.get_balance("USDT")
    except Exception as e:
        return {"ok": False, "error": f"Баланс недоступен: {e}"}

    return {"ok": True, "balance": balance, "exchange": exchange}


def get_balance(exchange: str, api_key: str, api_secret: str, testnet: bool = False):
    try:
        api = exchange_api.get_api(exchange, api_key, api_secret, testnet=testnet)
        return {"ok": True, "balance": api.get_balance("USDT")}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def save_account(exchange: str, name: str, api_key: str, api_secret: str, testnet: bool = False):
    """Сохраняет ключи локально (JSON в приватной папке приложения)."""
    accounts = load_accounts().get("accounts", [])
    record = {
        "name": name or exchange,
        "exchange": exchange,
        "api_key": api_key,
        "api_secret": api_secret,
        "testnet": bool(testnet),
    }
    # Обновляем существующую запись для этой биржи или добавляем
    for i, a in enumerate(accounts):
        if a.get("exchange") == exchange:
            accounts[i] = record
            break
    else:
        accounts.append(record)
    _write_keys({"accounts": accounts, "active_index": len(accounts) - 1})
    return {"ok": True, "count": len(accounts)}


def load_accounts():
    """Читает сохранённые аккаунты. Возвращает {"accounts": [...], "active_index": n}."""
    path = _keys_path()
    if not os.path.exists(path):
        return {"accounts": [], "active_index": -1}
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            return {"accounts": data.get("accounts", []), "active_index": data.get("active_index", -1)}
        if isinstance(data, list):
            return {"accounts": data, "active_index": -1}
    except Exception:
        pass
    return {"accounts": [], "active_index": -1}


def set_active(index: int):
    data = load_accounts()
    accounts = data["accounts"]
    if 0 <= index < len(accounts):
        data["active_index"] = index
        _write_keys(data)
        return {"ok": True, "active": accounts[index].get("exchange")}
    return {"ok": False, "error": "index out of range"}


def get_active():
    data = load_accounts()
    idx = data["active_index"]
    if 0 <= idx < len(data["accounts"]):
        return {"ok": True, "account": data["accounts"][idx]}
    return {"ok": False, "error": "no active account"}


def delete_account(index: int):
    data = load_accounts()
    accounts = data["accounts"]
    if 0 <= index < len(accounts):
        accounts.pop(index)
        ai = data["active_index"]
        if ai == index:
            data["active_index"] = -1
        elif ai > index:
            data["active_index"] = ai - 1
        _write_keys(data)
        return {"ok": True}
    return {"ok": False, "error": "index out of range"}


def _write_keys(payload: dict):
    with open(_keys_path(), "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False)


# ----------------------------------------------------------
# Версия / обновления / авторизация
# ----------------------------------------------------------

def get_version():
    return {"ok": True, "version": config.VERSION}


def get_news():
    return auth.get_news(config.VERSION)


def check_update():
    try:
        has_update, new_version, download_url = auth.check_for_update(config.VERSION)
        if new_version is None:
            return {
                "ok": False,
                "error": "Не удалось получить удалённую версию",
                "has_update": False,
                "new_version": "",
                "download_url": "",
                "current_version": config.VERSION,
            }
        return {
            "ok": True,
            "has_update": bool(has_update),
            "new_version": new_version or "",
            "download_url": download_url or "",
            "current_version": config.VERSION,
        }
    except Exception as e:
        return {"ok": False, "error": str(e)}


def get_auth_state():
    try:
        registered = auth.is_registered()
        reg = auth.load_registration() if registered else {}
        return {"ok": True, "registered": registered, "registration": reg}
    except Exception as e:
        return {"ok": False, "registered": False, "error": str(e)}


def load_registration():
    try:
        return {"ok": True, "registration": auth.load_registration()}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def register(name: str, password: str, key: str,
             email: str = "", remember: bool = True):
    try:
        result = auth.register(name, key, password=password,
                               email=email or None, remember=remember)
        if result is True:
            return {"ok": True}
        return {"ok": False, "error": result or "invalid_key"}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def login(name: str, password: str, key: str, remember: bool = True):
    try:
        result = auth.login(name, password, key, remember=remember)
        if result is True:
            return {"ok": True}
        return {"ok": False, "error": result or "wrong_credentials"}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def logout():
    try:
        auth.save_registration({})
        return {"ok": True}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def set_github_token(token: str):
    try:
        auth.set_github_token(token)
        return {"ok": True}
    except Exception as e:
        return {"ok": False, "error": str(e)}


# ----------------------------------------------------------
# Анализ / поиск по паттернам
# ----------------------------------------------------------

def _all_symbols_fallback():
    """Статический список USDT-M фьючерсных пар на случай недоступности API."""
    try:
        path = os.path.join(os.path.dirname(__file__), "assets", "all_symbols.json")
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return []


def get_symbols(exchange: str, api_key: str = "", api_secret: str = "", testnet: bool = False):
    try:
        api = exchange_api.get_api(exchange, api_key or "-", api_secret or "-", testnet=testnet)
        return {"ok": True, "symbols": api.get_usdt_symbols()}
    except Exception as e:
        symbols = _all_symbols_fallback()
        if symbols:
            return {"ok": True, "symbols": symbols, "note": "offline"}
        return {"ok": False, "error": str(e)}


def get_price(exchange: str, symbol: str, api_key: str = "", api_secret: str = "", testnet: bool = False):
    try:
        api = exchange_api.get_api(exchange, api_key or "-", api_secret or "-", testnet=testnet)
        price = api.get_price(symbol)
        return {"ok": True, "symbol": symbol, "exchange": exchange, **price}
    except Exception as e:
        return {"ok": False, "error": str(e)}


def get_all_prices(base: str, quote: str = "USDT"):
    try:
        return prices.get_all_prices(base, quote)
    except Exception as e:
        return {"ok": False, "error": str(e)}


def search_pattern(exchange: str, symbol: str, interval: str, pattern_length: int = 400,
                   forecast_horizon: int = 15, top_n: int = 10,
                   min_signal_threshold: float = 7.0,
                   api_key: str = "", api_secret: str = "", testnet: bool = False):
    return analysis.search_pattern(
        exchange, symbol, interval,
        pattern_length=pattern_length,
        forecast_horizon=forecast_horizon,
        top_n=top_n,
        min_signal_threshold=min_signal_threshold,
        api_key=api_key,
        api_secret=api_secret,
        testnet=testnet,
    )


_analysis_jobs = {}


def _progress_callback(job_id, symbol, status, signal=None, result=None, error=None):
    job = _analysis_jobs.get(job_id)
    if job is None:
        return
    if status == "loading":
        job["progress"].append({"symbol": symbol, "status": "Загрузка...", "signal": signal})
    elif status == "done":
        pct = result.get("forecast_return_pct", 0) if result else 0
        job["progress"].append({
            "symbol": symbol,
            "status": f"{signal} {pct}%",
            "signal": signal,
            "pct": pct,
        })
        job["results"].append(result)
    elif status == "error":
        job["progress"].append({"symbol": symbol, "status": "Временно данных нет", "signal": "ERROR"})
        job["errors"].append({"symbol": symbol, "error": error or "Временно данных нет"})
    job["last_update"] = time.time()


def start_analysis(symbols, exchange: str, interval: str, pattern_length: int = 400,
                   forecast_horizon: int = 15, top_n: int = 10,
                   min_signal_threshold: float = 7.0,
                   api_key: str = "", api_secret: str = "", testnet: bool = False,
                   skip_neutral: bool = False, sound_threshold: float = 1.5):
    job_id = "_active"
    _analysis_jobs[job_id] = {
        "status": "running",
        "progress": [],
        "results": [],
        "errors": [],
        "started_at": time.time(),
        "last_update": time.time(),
        "final": None,
    }

    def run():
        try:
            res = analysis.multi_pattern_search(
                symbols, exchange, interval,
                pattern_length=pattern_length,
                forecast_horizon=forecast_horizon,
                top_n=top_n,
                min_signal_threshold=min_signal_threshold,
                api_key=api_key,
                api_secret=api_secret,
                testnet=testnet,
                skip_neutral=skip_neutral,
                progress_callback=lambda symbol, status, signal=None, result=None, error=None: (
                    _progress_callback(job_id, symbol, status, signal=signal, result=result, error=error)
                ),
            )
            _analysis_jobs[job_id]["status"] = "done"
            _analysis_jobs[job_id]["final"] = res
        except Exception as e:
            _analysis_jobs[job_id]["status"] = "error"
            _analysis_jobs[job_id]["error"] = str(e)

    threading.Thread(target=run, daemon=True).start()
    return {"ok": True, "job_id": job_id}


def get_analysis_progress(job_id: str = "_active"):
    job = _analysis_jobs.get(job_id)
    if not job:
        return {"ok": False, "error": "job not found"}
    return {
        "ok": True,
        "status": job["status"],
        "progress": job["progress"],
        "results": job["results"],
        "errors": job["errors"],
        "final": job["final"],
    }


def cancel_analysis(job_id: str = "_active"):
    job = _analysis_jobs.get(job_id)
    if job:
        job["status"] = "cancelled"
    return {"ok": True}


def multi_pattern_search(symbols, exchange: str, interval: str, pattern_length: int = 400,
                         forecast_horizon: int = 15, top_n: int = 10,
                         min_signal_threshold: float = 7.0,
                         api_key: str = "", api_secret: str = "", testnet: bool = False,
                         skip_neutral: bool = True):
    return analysis.multi_pattern_search(
        symbols, exchange, interval,
        pattern_length=pattern_length,
        forecast_horizon=forecast_horizon,
        top_n=top_n,
        min_signal_threshold=min_signal_threshold,
        api_key=api_key,
        api_secret=api_secret,
        testnet=testnet,
        skip_neutral=skip_neutral,
    )


def run_trading_cycle(symbols, exchange: str, api_key: str, api_secret: str,
                      interval: str = "15m", pattern_length: int = 60,
                      forecast_horizon: int = 5, top_n: int = 5,
                      min_signal_threshold: float = 0.0,
                      trade_threshold: float = 1.5,
                      position_size: float = 100.0, leverage: int = 10,
                      amount_mode: str = "fixed",
                      tp_mode: str = "signal", tp_pct: float = 0.0,
                      sl_mode: str = "signal", sl_pct: float = 0.0,
                      testnet: bool = False, max_trades: int = None):
    return auto_trading.run_trading_cycle(
        symbols, exchange, api_key, api_secret,
        interval=interval,
        pattern_length=pattern_length,
        forecast_horizon=forecast_horizon,
        top_n=top_n,
        min_signal_threshold=min_signal_threshold,
        trade_threshold=trade_threshold,
        position_size=position_size,
        leverage=leverage,
        amount_mode=amount_mode,
        tp_mode=tp_mode,
        tp_pct=tp_pct,
        sl_mode=sl_mode,
        sl_pct=sl_pct,
        testnet=testnet,
        max_trades=max_trades,
    )


# ----------------------------------------------------------
# JSON-диспетчер для MethodChannel: одна точка входа из Kotlin.
# ----------------------------------------------------------

_METHODS = {
    "ping": ping,
    "init": init,
    "test_exchange": test_exchange,
    "get_balance": get_balance,
    "save_account": save_account,
    "load_accounts": load_accounts,
    "set_active": set_active,
    "get_active": get_active,
    "delete_account": delete_account,
    "get_version": get_version,
    "get_news": get_news,
    "check_update": check_update,
    "get_auth_state": get_auth_state,
    "load_registration": load_registration,
    "register": register,
    "login": login,
    "logout": logout,
    "set_github_token": set_github_token,
    "get_symbols": get_symbols,
    "get_price": get_price,
    "get_all_prices": get_all_prices,
    "search_pattern": search_pattern,
    "multi_pattern_search": multi_pattern_search,
    "start_analysis": start_analysis,
    "get_analysis_progress": get_analysis_progress,
    "cancel_analysis": cancel_analysis,
    "run_trading_cycle": run_trading_cycle,
}


def call_json(method: str, args_json: str = "{}") -> str:
    """Вызывает метод ядра. args_json — JSON-объект с аргументами.
    Возвращает JSON-строку с результатом."""
    try:
        fn = _METHODS.get(method)
        if fn is None:
            return json.dumps({"ok": False, "error": f"unknown method: {method}"})
        args = json.loads(args_json or "{}")
        if not isinstance(args, dict):
            args = {}
        result = fn(**args)
        return json.dumps(result, ensure_ascii=False, default=str)
    except Exception as e:
        return json.dumps({"ok": False, "error": f"{type(e).__name__}: {e}"})
