# config.py — мобильная конфигурация BLACK BOX для Chaquopy / Android.

import json
import os

# Приватная папка приложения: задаётся из Kotlin через FILES_DIR,
# либо используется папка пакета bbcore.
def set_app_dir(data_dir):
    global APP_DIR, REGISTRATION_FILE, USERS_DIR, USERS_FILE, KEYS_DIR
    global LOCAL_KEYS_FILE, LOCAL_DEACTIVATED_FILE, LAUNCHER_LANG_FILE
    global UPDATE_TMP_DIR, _TOKEN_FILE, GITHUB_TOKEN
    APP_DIR = data_dir
    os.makedirs(APP_DIR, exist_ok=True)
    REGISTRATION_FILE = os.path.join(APP_DIR, "registration.json")
    USERS_DIR = os.path.join(APP_DIR, "users")
    USERS_FILE = os.path.join(USERS_DIR, "users.txt")
    KEYS_DIR = os.path.join(APP_DIR, "keys")
    LOCAL_KEYS_FILE = os.path.join(KEYS_DIR, "keys.txt")
    LOCAL_DEACTIVATED_FILE = os.path.join(KEYS_DIR, "deactivated.txt")
    LAUNCHER_LANG_FILE = os.path.join(APP_DIR, "launcher_lang.json")
    UPDATE_TMP_DIR = os.path.join(APP_DIR, "update_tmp")
    _TOKEN_FILE = os.path.join(APP_DIR, "token.txt")
    os.makedirs(USERS_DIR, exist_ok=True)
    os.makedirs(KEYS_DIR, exist_ok=True)
    # Восстанавливаем ранее сохранённый GitHub-токен.
    if not GITHUB_TOKEN and os.path.exists(_TOKEN_FILE):
        try:
            with open(_TOKEN_FILE, "r", encoding="utf-8") as f:
                GITHUB_TOKEN = f.read().strip()
        except Exception:
            pass


APP_DIR = os.environ.get("FILES_DIR", os.path.dirname(__file__))
os.makedirs(APP_DIR, exist_ok=True)

APP_NAME = "BLACK BOX Mobile"

# Версия читается из bundled assets. Если файла нет — fallback.
VERSION_FILE = os.path.join(os.path.dirname(__file__), "assets", "version.json")
try:
    with open(VERSION_FILE, "r", encoding="utf-8") as f:
        _version_data = json.load(f)
    VERSION = (
        str(_version_data.get("version", "1.0.0"))
        if isinstance(_version_data, dict)
        else "1.0.0"
    )
except Exception:
    VERSION = "1.0.0"

# Ссылки на релиз мобильного APK.
VERSION_URL = "https://github.com/VladislavDelon/BLACK-BOX-Mobile-Realese/releases/latest/download/version.json"
UPDATE_URL = "https://github.com/VladislavDelon/BLACK-BOX-Mobile-Realese/releases/latest/download/BLACK_BOX_Mobile.apk"

# Приватный репозиторий с ключами и пользователями.
GITHUB_REPO = os.environ.get("BB_GITHUB_REPO", "VladislavDelon/blackbox-keys")
GITHUB_TOKEN = os.environ.get("BB_GITHUB_TOKEN", "")

# Если в окружении токен не задан, пробуем загрузить ранее сохранённый.
_TOKEN_FILE = os.path.join(APP_DIR, "token.txt")
if not GITHUB_TOKEN and os.path.exists(_TOKEN_FILE):
    try:
        with open(_TOKEN_FILE, "r", encoding="utf-8") as f:
            GITHUB_TOKEN = f.read().strip()
    except Exception:
        pass

# Стандартные пути локальных файлов (все внутри APP_DIR).
REGISTRATION_FILE = os.path.join(APP_DIR, "registration.json")
USERS_DIR = os.path.join(APP_DIR, "users")
USERS_FILE = os.path.join(USERS_DIR, "users.txt")
KEYS_DIR = os.path.join(APP_DIR, "keys")
LOCAL_KEYS_FILE = os.path.join(KEYS_DIR, "keys.txt")
LOCAL_DEACTIVATED_FILE = os.path.join(KEYS_DIR, "deactivated.txt")
LAUNCHER_LANG_FILE = os.path.join(APP_DIR, "launcher_lang.json")
UPDATE_TMP_DIR = os.path.join(APP_DIR, "update_tmp")
