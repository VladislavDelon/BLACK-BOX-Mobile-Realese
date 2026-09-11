#!/usr/bin/env python3
"""Create GitHub release v1.1.8 and upload assets."""

import os
import subprocess
import sys
import urllib.parse

import requests
import urllib3
from urllib3.exceptions import InsecureRequestWarning

# The user explicitly requests verify=False; silence the related warnings.
urllib3.disable_warnings(InsecureRequestWarning)

REPO = "VladislavDelon/BLACK-BOX-Mobile-Realese"
CREDENTIAL_URL = "https://github.com/VladislavDelon/BLACK-BOX-Mobile-Realese.git"
CREATE_URL = f"https://140.82.121.5/repos/{REPO}/releases"

ASSETS = [
    ("BLACK_BOX_Mobile_v1.1.8.apk", "application/vnd.android.package-archive"),
    ("version.json", "application/json"),
]

BODY = (
    "- Add desktop-style signal chart and movement windows.\n"
    "- Pattern search now shows 'График' and 'Движение' buttons after analysis.\n"
    "- Uses candlesticks package for OHLC charts.\n"
    "- Same top-pattern and summary logic as desktop version."
)


def get_git_credential():
    """Read the stored GitHub token via 'git credential fill'."""
    input_text = f"url={CREDENTIAL_URL}\n\n"
    try:
        result = subprocess.run(
            ["git", "credential", "fill"],
            input=input_text,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except subprocess.TimeoutExpired:
        raise RuntimeError("git credential fill timed out")

    if result.returncode != 0:
        raise RuntimeError(f"git credential fill failed: {result.stderr}")

    creds = {}
    for line in result.stdout.splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            creds[key.strip()] = value.strip()

    # GCM typically stores the PAT in the 'password' field.
    token = creds.get("password") or creds.get("oauth")
    if not token:
        raise RuntimeError("No token found in git credential output")
    return token


def create_release(token):
    """Create the v1.1.8 release on GitHub."""
    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
        "Host": "api.github.com",
        "User-Agent": "release-v118-script",
    }
    payload = {
        "tag_name": "v1.1.8",
        "name": "v1.1.8",
        "body": BODY,
        "draft": False,
        "prerelease": False,
    }
    response = requests.post(
        CREATE_URL,
        headers=headers,
        json=payload,
        verify=False,
        timeout=60,
    )
    if response.status_code >= 400:
        raise RuntimeError(
            f"Release creation failed ({response.status_code}): {response.text}"
        )
    return response.json()


def upload_asset(upload_url, token, filename, content_type):
    """Upload a single file to the release's upload_url."""
    if not os.path.exists(filename):
        raise FileNotFoundError(f"Asset not found: {filename}")

    # Expand the upload_url template {?name,label} and append the filename.
    base_url = upload_url.replace("{?name,label}", "")
    sep = "?" if "?" not in base_url else "&"
    url = f"{base_url}{sep}name={urllib.parse.quote(filename)}"

    headers = {
        "Accept": "application/vnd.github+json",
        "Authorization": f"Bearer {token}",
        "X-GitHub-Api-Version": "2022-11-28",
        "Host": "uploads.github.com",
        "Content-Type": content_type,
        "User-Agent": "release-v118-script",
    }

    with open(filename, "rb") as f:
        response = requests.post(
            url,
            headers=headers,
            data=f,
            verify=False,
            timeout=600,
        )

    if response.status_code >= 400:
        raise RuntimeError(
            f"Upload of {filename} failed ({response.status_code}): {response.text}"
        )
    return response.json()


def main():
    try:
        token = get_git_credential()
        print("Retrieved GitHub token from git credential.")

        release = create_release(token)
        upload_url = release["upload_url"]
        release_url = release["html_url"]
        print(f"Created release: {release_url}")
        print(f"Upload URL: {upload_url}")

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
