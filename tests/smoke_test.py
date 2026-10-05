"""Smoke test for a running instance: python tests/smoke_test.py <base_url> <expected_message>"""

import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from app import VERSION  # noqa: E402

BASE_URL = sys.argv[1].rstrip("/")
EXPECTED_MESSAGE = sys.argv[2]


def get(path):
    try:
        with urllib.request.urlopen(BASE_URL + path, timeout=3) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as error:
        return error.code, json.loads(error.read())


def wait_until_ready(seconds=20):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            return get("/health")
        except (urllib.error.URLError, ConnectionError):
            time.sleep(1)
    sys.exit(f"FAIL: no answer from {BASE_URL}/health after {seconds}s")


def check(condition, description):
    if not condition:
        sys.exit(f"FAIL: {description}")
    print(f"ok: {description}")


status, body = wait_until_ready()
check(status == 200, "/health returns 200")
check(body.get("status") == "ok", "/health reports status ok")
check(body.get("version") == VERSION, f"/health reports version {VERSION}, the code in this commit")

status, body = get("/")
check(status == 200, "/ returns 200")
check(body.get("message") == EXPECTED_MESSAGE, "/ returns the message supplied at runtime")

status, _ = get("/does-not-exist")
check(status == 404, "unknown paths return 404")

print("All smoke tests passed")
