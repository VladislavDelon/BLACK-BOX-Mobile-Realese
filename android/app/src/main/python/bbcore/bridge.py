# bridge.py — мост между Kotlin/Flutter и Python-ядром BLACK BOX.
# Все функции возвращают JSON-совместимые dict, чтобы спокойно уходили через MethodChannel.

import json
import os

from bbcore import exchange_api
from bbcore import auth
from bbcore import config

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


def check_update():
    try:
        has_update, new_version, download_url = auth.check_for_update(config.VERSION)
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
    "check_update": check_update,
    "get_auth_state": get_auth_state,
    "load_registration": load_registration,
    "register": register,
    "login": login,
    "logout": logout,
    "set_github_token": set_github_token,
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
