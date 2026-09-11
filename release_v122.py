#!/usr/bin/env python3
"""Create GitHub release v1.2.2 and upload assets."""

import os
import subprocess
import sys
import urllib.parse

import requests
import urllib3
from urllib3.exceptions import InsecureRequestWarning

urllib3.disable_warnings(InsecureRequestWarning)

REPO = "VladislavDelon/BLACK-BOX-Mobile-Realese"
CREDENTIAL_URL = "https://github.com/VladislavDelon/BLACK-BOX-Mobile-Realese.git"
API_HOST = "140.82.121.5"
UPLOAD_IP = "140.82.121.14"
TAG = "v1.2.2"
CREATE_URL = f"https://{API_HOST}/repos/{REPO}/releases"

ASSETS = [
    ("BLACK_BOX_Mobile_v1.2.2.apk", "application/vnd.android.package-archive"),
    ("version.json", "application/json"),
]

BODY = (
    "- Убран эмоджи из кнопки торгового цикла.\n"
    "- «Временно данных нет» исправлено: спот остаётся основным источником (как на десктопе), "
    "плюс автоматический фолбэк на фьючерс и повторные запросы при сбоях.\n"
    "- Новый раздел «Логи» (ссылка внизу главного меню рядом с версией): "
    "ошибки и события с датой и временем.\n"
    "- Полоски карточек в главном меню теперь белые.\n"
    "- В «Аккаунте» добавлена настройка «Светлая тема» — переключение оформления приложения.\n"
    "- Звуковой сигнал при достижении порога играет один раз на монету (был дублирующийся писк)."
)


def get_git_credential():
    input_text = f"url={CREDENTIAL_URL}\n\n"
    result = subprocess.run(
        ["git", "credential", "fill"],
        input=input_text,
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"git credential fill failed: {result.stderr}")
    creds = {}
    for line in result.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            creds[key.strip()] = value.strip()
    token = creds.get("password") or creds.get("oauth")
    if not token:
        raise RuntimeError("No token found in git credential output")
    return token


def api_headers(token, host="api.github.com"):
    return {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
        "Host": host,
        "User-Agent": "release-v122-script",
    }


def get_release_by_tag(token):
    url = f"https://{API_HOST}/repos/{REPO}/releases/tags/{TAG}"
    r = requests.get(url, headers=api_headers(token), verify=False, timeout=60)
    if r.status_code == 200:
        return r.json()
    return None


def create_release(token):
    payload = {
        "tag_name": TAG,
        "name": TAG,
        "body": BODY,
        "draft": False,
        "prerelease": False,
    }
    r = requests.post(
        CREATE_URL,
        headers=api_headers(token),
        json=payload,
        verify=False,
        timeout=60,
    )
    if r.status_code == 422:
        existing = get_release_by_tag(token)
        if existing:
            return existing
    if r.status_code >= 400:
        raise RuntimeError(f"Release creation failed ({r.status_code}): {r.text}")
    return r.json()


def delete_existing_assets(token, release):
    url = f"https://{API_HOST}/repos/{REPO}/releases/{release['id']}/assets"
    r = requests.get(url, headers=api_headers(token), verify=False, timeout=60)
    if r.status_code != 200:
        return
    existing = {a["name"]: a["id"] for a in r.json()}
    for filename, _ in ASSETS:
        if filename in existing:
            del_url = f"https://{API_HOST}/repos/{REPO}/releases/assets/{existing[filename]}"
            requests.delete(del_url, headers=api_headers(token), verify=False, timeout=60)


def upload_asset(upload_url, token, filename, content_type):
    if not os.path.exists(filename):
        raise FileNotFoundError(f"Asset not found: {filename}")

    base_url = upload_url.replace("{?name,label}", "")
    base_url = base_url.replace("uploads.github.com", UPLOAD_IP)
    sep = "?" if "?" not in base_url else "&"
    url = f"{base_url}{sep}name={urllib.parse.quote(filename)}"

    headers = api_headers(token, host="uploads.github.com")
    headers["Content-Type"] = content_type

    with open(filename, "rb") as f:
        r = requests.post(url, headers=headers, data=f, verify=False, timeout=600)
    if r.status_code >= 400:
        raise RuntimeError(f"Upload of {filename} failed ({r.status_code}): {r.text}")
    return r.json()


def main():
    try:
        token = get_git_credential()
        print("Retrieved GitHub token from git credential.")

        release = create_release(token)
        upload_url = release["upload_url"]
        release_url = release["html_url"]
        print(f"Release: {release_url}")

        delete_existing_assets(token, release)

        for filename, content_type in ASSETS:
            print(f"Uploading {filename} ...", end=" ", flush=True)
            upload_asset(upload_url, token, filename, content_type)
            print("done")

        print(f"\nRelease URL: {release_url}")
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
