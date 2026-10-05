"""Small, dependency-free client application for a LOCAL deployment exercise."""

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

VERSION = "1.0"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlsplit(self.path).path
        if path == "/health":
            status, payload = 200, {"status": "ok", "version": VERSION}
        elif path == "/":
            status, payload = 200, {
                "message": os.environ["APP_MESSAGE"],
                "version": VERSION,
            }
        else:
            status, payload = 404, {"error": "not found"}
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def main():
    if not os.environ.get("APP_MESSAGE", "").strip():
        print("STARTUP ERROR: APP_MESSAGE must be set and non-empty", file=sys.stderr)
        return 1
    port = int(os.environ.get("PORT", "8000"))
    host = os.environ.get("BIND_HOST", "127.0.0.1")
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"Exercise app v{VERSION} listening on {host}:{server.server_port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
