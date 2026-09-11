# logutil.py — простое файловое логирование для мобильного ядра.
# Пишет в <filesDir>/logs.txt, файл ротируется (храним последние ~128 КБ).

import os
import time

_LOG_PATH = None
_MAX_BYTES = 256 * 1024
_KEEP_BYTES = 128 * 1024


def init(data_dir: str):
    global _LOG_PATH
    _LOG_PATH = os.path.join(data_dir, "logs.txt")


def log(msg: str):
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}\n"
    try:
        path = _LOG_PATH or "logs.txt"
        if os.path.exists(path) and os.path.getsize(path) > _MAX_BYTES:
            with open(path, "rb") as f:
                f.seek(-_KEEP_BYTES, os.SEEK_END)
                tail = f.read()
            with open(path, "wb") as f:
                f.write(tail)
        with open(path, "a", encoding="utf-8") as f:
            f.write(line)
    except Exception:
        pass


def read_logs(max_bytes: int = _KEEP_BYTES) -> str:
    path = _LOG_PATH or "logs.txt"
    try:
        if not os.path.exists(path):
            return ""
        size = os.path.getsize(path)
        with open(path, "rb") as f:
            if size > max_bytes:
                f.seek(-max_bytes, os.SEEK_END)
            data = f.read()
        return data.decode("utf-8", errors="replace")
    except Exception as e:
        return f"[logutil] read error: {e}"


def clear_logs():
    path = _LOG_PATH or "logs.txt"
    try:
        with open(path, "w", encoding="utf-8") as f:
            f.write("")
    except Exception:
        pass
