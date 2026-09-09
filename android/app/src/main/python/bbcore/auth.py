# auth.py — регистрация, авторизация, проверка ключей и информация об обновлениях
# для мобильного Python-ядра BLACK BOX в Chaquopy.

import base64
import hashlib
import json
import os
import platform
import socket
import time
import urllib.parse
import uuid

import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

try:
    from bbcore import config
except ImportError:
    import config

APP_DIR = config.APP_DIR
REG_FILE = config.REGISTRATION_FILE
USERS_DIR = config.USERS_DIR
USERS_FILE = config.USERS_FILE
LOCAL_KEYS_DIR = config.KEYS_DIR
LOCAL_KEYS_FILE = config.LOCAL_KEYS_FILE
LOCAL_DEACTIVATED_FILE = config.LOCAL_DEACTIVATED_FILE

VERSION_URL = config.VERSION_URL
UPDATE_URL = config.UPDATE_URL
GITHUB_REPO = config.GITHUB_REPO

os.makedirs(USERS_DIR, exist_ok=True)
os.makedirs(LOCAL_KEYS_DIR, exist_ok=True)


def init_data_dir(data_dir: str):
    """Переинициализирует пути, когда Kotlin передаёт приватную папку приложения."""
    global APP_DIR, REG_FILE, USERS_DIR, USERS_FILE, LOCAL_KEYS_DIR
    global LOCAL_KEYS_FILE, LOCAL_DEACTIVATED_FILE
    config.set_app_dir(data_dir)
    APP_DIR = config.APP_DIR
    REG_FILE = config.REGISTRATION_FILE
    USERS_DIR = config.USERS_DIR
    USERS_FILE = config.USERS_FILE
    LOCAL_KEYS_DIR = config.KEYS_DIR
    LOCAL_KEYS_FILE = config.LOCAL_KEYS_FILE
    LOCAL_DEACTIVATED_FILE = config.LOCAL_DEACTIVATED_FILE
    os.makedirs(USERS_DIR, exist_ok=True)
    os.makedirs(LOCAL_KEYS_DIR, exist_ok=True)

KEYS_PATH = "keys.txt"
DEACTIVATED_PATH = "deactivated.txt"
_GITHUB_IPS = ("140.82.121.5", "140.82.121.14")


# ---------------------------------------------------------------------------
# Утилиты
# ---------------------------------------------------------------------------

def _parse_key_list(text):
    """Возвращает список ключей из plain-text, пропуская пустые и комментарии."""
    return [
        line.split(";", 1)[0].strip()
        for line in text.splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]


def _load_local_keys():
    try:
        with open(LOCAL_KEYS_FILE, "r", encoding="utf-8") as f:
            return _parse_key_list(f.read())
    except FileNotFoundError:
        return []


def _load_local_deactivated_keys():
    try:
        with open(LOCAL_DEACTIVATED_FILE, "r", encoding="utf-8") as f:
            return _parse_key_list(f.read())
    except FileNotFoundError:
        return []


# ---------------------------------------------------------------------------
# HTTP / GitHub helpers с fallback на прямой IP
# ---------------------------------------------------------------------------

def _request(method, url, headers=None, json_payload=None, data=None,
             verify=True, timeout=10, allow_redirects=True):
    try:
        if method == "get":
            return requests.get(
                url,
                headers=headers,
                verify=verify,
                timeout=timeout,
                allow_redirects=allow_redirects,
            )
        if method == "head":
            return requests.head(
                url,
                headers=headers,
                verify=verify,
                timeout=timeout,
                allow_redirects=allow_redirects,
            )
        if method == "put":
            return requests.put(
                url,
                headers=headers,
                json=json_payload,
                verify=verify,
                timeout=timeout,
            )
        if method == "delete":
            return requests.delete(
                url,
                headers=headers,
                json=json_payload,
                verify=verify,
                timeout=timeout,
            )
        return requests.request(
            method,
            url,
            headers=headers,
            data=data,
            verify=verify,
            timeout=timeout,
        )
    except Exception as e:
        print(f"[request] {method.upper()} {url}: {e}")
        return None


def _request_with_fallback(method, base_url, headers=None, json_payload=None,
                           data=None, timeout=10, allow_redirects=True,
                           ok_codes=(200,)):
    """Сначала DNS, затем оба прямых IP GitHub с Host-заголовком."""
    parsed = urllib.parse.urlparse(base_url)
    netloc = parsed.netloc
    candidates = [(base_url, netloc, True)]
    for ip in _GITHUB_IPS:
        ip_url = f"{parsed.scheme}://{ip}{parsed.path}"
        if parsed.query:
            ip_url += f"?{parsed.query}"
        candidates.append((ip_url, netloc, False))

    for url, host, verify in candidates:
        hdrs = dict(headers or {})
        if host:
            hdrs.setdefault("Host", host)
        try:
            r = _request(
                method,
                url,
                headers=hdrs,
                json_payload=json_payload,
                data=data,
                verify=verify,
                timeout=timeout,
                allow_redirects=allow_redirects,
            )
            if r is not None and r.status_code in ok_codes:
                return r
            if r is not None:
                print(f"[fallback] {url} -> {r.status_code}")
        except Exception as e:
            print(f"[fallback] {url} exception: {e}")
    return None


def _github_api_url(path):
    return f"https://api.github.com/repos/{GITHUB_REPO}/contents/{path}"


# ---------------------------------------------------------------------------
# Удалённая работа с файлами репозитория
# ---------------------------------------------------------------------------

def _fetch_remote_lines(path):
    """Загружает plain-text (keys.txt / deactivated.txt) через GitHub API."""
    if not config.GITHUB_TOKEN:
        return None
    url = _github_api_url(path)
    headers = {
        "Authorization": f"token {config.GITHUB_TOKEN}",
        "Accept": "application/vnd.github.v3+json",
    }
    r = _request_with_fallback(
        "get", url, headers=headers, timeout=10, ok_codes=(200,)
    )
    if not r:
        return None
    try:
        data = r.json()
        if data.get("encoding") == "base64" and "content" in data:
            text = base64.b64decode(data["content"]).decode("utf-8")
            return _parse_key_list(text)
    except Exception as e:
        print(f"[remote lines parse] {e}")
    return None


def _load_remote_keys():
    return _fetch_remote_lines(KEYS_PATH)


def _load_remote_deactivated_keys():
    return _fetch_remote_lines(DEACTIVATED_PATH)


def _fetch_remote_text(path):
    """Загружает произвольный текстовый файл из приватного репозитория."""
    if not config.GITHUB_TOKEN:
        return None
    url = _github_api_url(path)
    headers = {
        "Authorization": f"token {config.GITHUB_TOKEN}",
        "Accept": "application/vnd.github.v3+json",
    }
    r = _request_with_fallback(
        "get", url, headers=headers, timeout=10, ok_codes=(200,)
    )
    if not r:
        return None
    try:
        data = r.json()
        if data.get("encoding") == "base64" and "content" in data:
            return base64.b64decode(data["content"]).decode("utf-8")
    except Exception as e:
        print(f"[remote text parse] {e}")
    return None


def _fetch_remote_json(path):
    text = _fetch_remote_text(path)
    if text is None:
        return None
    try:
        return json.loads(text)
    except Exception:
        return text


def _fetch_remote_list(path):
    """Возвращает список содержимого папки из приватного репозитория."""
    if not config.GITHUB_TOKEN:
        return []
    url = _github_api_url(path)
    headers = {
        "Authorization": f"token {config.GITHUB_TOKEN}",
        "Accept": "application/vnd.github.v3+json",
    }
    r = _request_with_fallback(
        "get", url, headers=headers, timeout=10, ok_codes=(200,)
    )
    if not r:
        return []
    try:
        data = r.json()
        if isinstance(data, list):
            return data
    except Exception:
        pass
    return []


def _put_remote_file(path, content, message="update"):
    """Создаёт или обновляет файл в приватном репозитории."""
    if not config.GITHUB_TOKEN:
        return False
    url = _github_api_url(path)
    headers = {
        "Authorization": f"token {config.GITHUB_TOKEN}",
        "Accept": "application/vnd.github.v3+json",
    }
    payload = {
        "message": message,
        "content": base64.b64encode(
            content if isinstance(content, bytes) else content.encode("utf-8")
        ).decode("ascii"),
    }
    # Получаем sha, если файл уже существует.
    r = _request_with_fallback(
        "get", url, headers=headers, timeout=10, ok_codes=(200,)
    )
    if r:
        try:
            sha = r.json().get("sha")
            if sha:
                payload["sha"] = sha
        except Exception:
            pass
    r = _request_with_fallback(
        "put", url, headers=headers, json_payload=payload,
        timeout=15, ok_codes=(200, 201),
    )
    return bool(r and r.status_code in (200, 201))


def _delete_remote_file(path, message="delete"):
    """Удаляет файл из приватного репозитория."""
    if not config.GITHUB_TOKEN:
        return False
    url = _github_api_url(path)
    headers = {
        "Authorization": f"token {config.GITHUB_TOKEN}",
        "Accept": "application/vnd.github.v3+json",
    }
    r = _request_with_fallback(
        "get", url, headers=headers, timeout=10, ok_codes=(200,)
    )
    if not r:
        return False
    try:
        sha = r.json().get("sha")
    except Exception:
        return False
    if not sha:
        return False
    payload = {"message": message, "sha": sha}
    r = _request_with_fallback(
        "delete", url, headers=headers, json_payload=payload,
        timeout=15, ok_codes=(200, 204),
    )
    return bool(r and r.status_code in (200, 204))


# ---------------------------------------------------------------------------
# Пользователи
# ---------------------------------------------------------------------------

def _remote_user_path(name):
    return f"users/{name}.json"


def _load_remote_user(name):
    """Ищет пользователя в users/ по имени (без учёта регистра)."""
    if not name:
        return None
    name = name.strip().lower()
    user = _fetch_remote_json(_remote_user_path(name))
    if user and "login" in user:
        return user
    for item in _fetch_remote_list("users"):
        if item.get("type") != "file" or not item.get("name", "").endswith(".json"):
            continue
        data = _fetch_remote_json(f"users/{item['name']}")
        if not data:
            continue
        if str(data.get("login", "")).strip().lower() == name:
            return data
    return None


def _load_all_remote_users():
    users = {}
    for item in _fetch_remote_list("users"):
        if item.get("type") != "file" or not item.get("name", "").endswith(".json"):
            continue
        data = _fetch_remote_json(f"users/{item['name']}")
        if data and "login" in data:
            users[data["login"]] = data
    return users


def _save_remote_user(name, info, message="register user"):
    content = json.dumps(info, ensure_ascii=False, indent=2)
    return _put_remote_file(_remote_user_path(name), content, message)


def _load_users():
    """Все зарегистрированные пользователи: сначала remote, затем локальный бэкап."""
    users = _load_all_remote_users()
    if users:
        return users
    if not os.path.exists(USERS_FILE):
        return users
    try:
        with open(USERS_FILE, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = [p.strip() for p in line.split(";", 3)]
                if len(parts) >= 3:
                    users[parts[0]] = {
                        "login": parts[0],
                        "password": parts[1],
                        "key": parts[2],
                        "email": parts[3] if len(parts) > 3 else "",
                    }
    except Exception as e:
        print(f"[load users] {e}")
    return users


# ---------------------------------------------------------------------------
# Публичные API-функции
# ---------------------------------------------------------------------------

def get_device_id():
    """Возвращает устойчивый device-id на основе характеристик устройства."""
    raw = platform.system() + platform.machine() + platform.node()
    try:
        raw += socket.gethostname()
    except Exception:
        pass
    try:
        raw += hex(uuid.getnode())
    except Exception:
        pass
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def load_registration():
    try:
        with open(REG_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_registration(data):
    with open(REG_FILE, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def _has_connection():
    """Проверяет, есть ли связь с GitHub API."""
    if not config.GITHUB_TOKEN:
        return False
    try:
        remote = _load_remote_keys()
        return remote is not None
    except Exception:
        return False


def validate_key(key):
    if not key:
        return False
    key = key.strip()
    remote = _load_remote_keys()
    if remote is not None:
        if key not in remote:
            return False
        deactivated = _load_remote_deactivated_keys()
        if deactivated is None:
            deactivated = _load_local_deactivated_keys()
        if key in deactivated:
            return False
        return True
    # Fallback на локальные файлы.
    if key not in _load_local_keys():
        return False
    if key in _load_local_deactivated_keys():
        return False
    return True


def is_registered():
    reg = load_registration()
    if not reg.get("remember"):
        return False
    return bool(
        reg.get("key") and reg.get("name") and validate_key(reg.get("key"))
    )


def set_github_token(token):
    """Сохраняет токен в окружение, config и локальный token.txt (если не пустой)."""
    token = (token or "").strip()
    if not token:
        return False
    os.environ["BB_GITHUB_TOKEN"] = token
    config.GITHUB_TOKEN = token
    try:
        with open(config._TOKEN_FILE, "w", encoding="utf-8") as f:
            f.write(token)
    except Exception as e:
        print(f"[token save error] {e}")
    return True


def register(name, key, password=None, email=None, remember=False, **extra):
    name = (name or "").strip()
    key = (key or "").strip()
    password = (password or "").strip()
    if not key or not name:
        return "invalid_key"
    if not _has_connection():
        return "no_connection"
    if not validate_key(key):
        return "invalid_key"
    info = {
        "login": name,
        "password": password or "",
        "key": key,
        "email": (email or "").strip(),
    }
    info.update(extra)
    if not _save_remote_user(name, info, f"register user {name}"):
        return "invalid_key"
    # Локальный резерв.
    try:
        with open(USERS_FILE, "a", encoding="utf-8") as f:
            f.write(f"{name};{password};{key};{email or ''}\n")
    except Exception as e:
        print(f"[local user write] {e}")
    data = load_registration()
    data.update({
        "name": name,
        "key": key,
        "password": password,
        "email": email,
        "remember": remember,
        "registered_at": time.time(),
    })
    data.update(extra)
    save_registration(data)
    return True


def login(name, password, key, remember=False):
    if not (name and key):
        return "not_registered"
    name = name.strip()
    key = key.strip()
    password = (password or "").strip()
    if not _has_connection():
        return "no_connection"
    if not validate_key(key):
        return "invalid_key"
    user = _load_remote_user(name)
    if not user or str(user.get("login", "")).strip().lower() != name.lower():
        return "not_registered"
    if (
        str(user.get("password", "")).strip() != password
        or str(user.get("key", "")).strip().lower() != key.lower()
    ):
        return "wrong_credentials"
    data = load_registration()
    data.update({
        "name": name,
        "key": key,
        "password": password,
        "remember": remember,
        "registered_at": time.time(),
    })
    save_registration(data)
    return True


def delete_account(name, password, key):
    """Удаляет пользователя с GitHub и сбрасывает локальную сессию."""
    if not (name and password and key):
        return False
    name = name.strip()
    key = key.strip()
    password = (password or "").strip()
    user = _load_remote_user(name)
    if (
        not user
        or str(user.get("password", "")).strip() != password
        or str(user.get("key", "")).strip().lower() != key.lower()
    ):
        return False
    _delete_remote_file(_remote_user_path(name), f"delete user {name}")
    # Обновляем локальный резерв.
    try:
        if os.path.exists(USERS_FILE):
            with open(USERS_FILE, "r", encoding="utf-8") as f:
                lines = [
                    line.rstrip("\n")
                    for line in f
                    if line.strip() and not line.startswith("#")
                ]
            with open(USERS_FILE, "w", encoding="utf-8") as f:
                for line in lines:
                    parts = [p.strip() for p in line.split(";", 3)]
                    if (
                        len(parts) >= 3
                        and parts[0] == name
                        and parts[1] == password
                        and parts[2] == key
                    ):
                        continue
                    f.write(line + "\n")
    except Exception:
        pass
    reg = load_registration()
    if (
        reg.get("name") == name
        and reg.get("password") == password
        and reg.get("key") == key
    ):
        save_registration({})
    return True


def get_user_by_key(key):
    """Возвращает данные пользователя (login, email, password) по ключу."""
    if not key:
        return None
    key = key.strip()
    for login, info in _load_users().items():
        if info.get("key") == key:
            return {
                "login": login,
                "password": info.get("password", ""),
                "email": info.get("email", ""),
            }
    reg = load_registration()
    if reg.get("key") == key:
        return {
            "login": reg.get("name", ""),
            "password": reg.get("password", ""),
            "email": reg.get("email", ""),
        }
    return None


# ---------------------------------------------------------------------------
# Обновления (mobile): только информация, без скачивания/замены APK
# ---------------------------------------------------------------------------

def get_current_version():
    """Читает текущую версию из version.json (assets)."""
    try:
        with open(config.VERSION_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict) and data.get("version"):
            return str(data.get("version"))
    except Exception:
        pass
    return config.VERSION


def check_for_update(current_version=None):
    """Возвращает (has_update, new_version, download_url)."""
    if not VERSION_URL:
        return False, None, None
    if current_version is None:
        current_version = get_current_version()
    try:
        headers = {"Accept": "application/json"}
        r = _request_with_fallback(
            "get", VERSION_URL, headers=headers,
            timeout=5, allow_redirects=True, ok_codes=(200,),
        )
        if not r:
            return False, None, None
        data = r.json()
        new_version = data.get("version")
        download_url = data.get("download_url") or UPDATE_URL
        if new_version and new_version != current_version:
            return True, new_version, download_url
        return False, new_version, None
    except Exception as e:
        print(f"[check update] {e}")
        return False, None, None


def update_info(current_version=None):
    """Возвращает информацию об обновлении в виде dict для Flutter."""
    has_update, new_version, download_url = check_for_update(current_version)
    return {
        "ok": True,
        "has_update": bool(has_update),
        "new_version": new_version or "",
        "download_url": download_url or "",
    }
