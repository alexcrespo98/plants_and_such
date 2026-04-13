#!/usr/bin/env python3
"""
brick_server.py — Pi-hole focus toggle HTTP server (port 5123)

Endpoints:
  GET /state   — returns current focus state + timestamp
  GET /toggle  — flips focus on ↔ off
  GET /on      — enables focus mode (FocusON group)
  GET /off     — disables focus mode (FocusOFF group, default)
  GET /health  — health check

On every start the server defaults to OFF (FocusOFF active).
Run as a persistent systemd service via brick-server.service.
"""

import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer

PORT = 5123
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STATE_FILE = os.path.join(BASE_DIR, "state.json")
SCRIPTS_DIR = os.path.join(BASE_DIR, "scripts")


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _read_state() -> dict:
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {"state": "off", "since": _now_iso()}


def _write_state(state: str) -> dict:
    data = {"state": state, "since": _now_iso()}
    with open(STATE_FILE, "w") as f:
        json.dump(data, f)
    return data


def _run_script(name: str) -> bool:
    script = os.path.join(SCRIPTS_DIR, name)
    try:
        result = subprocess.run(
            ["bash", script],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode != 0:
            print(f"[brick] {name} stderr: {result.stderr.strip()}", file=sys.stderr)
            return False
        print(f"[brick] {name}: {result.stdout.strip()}")
        return True
    except subprocess.TimeoutExpired:
        print(f"[brick] {name} timed out", file=sys.stderr)
        return False
    except Exception as e:
        print(f"[brick] {name} error: {e}", file=sys.stderr)
        return False


def _set_focus(on: bool) -> dict:
    script = "focus-on.sh" if on else "focus-off.sh"
    ok = _run_script(script)
    if ok:
        return _write_state("on" if on else "off")
    # Return current state without updating if script failed
    data = _read_state()
    data["error"] = f"{script} failed"
    return data


class BrickHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):  # noqa: N802
        print(f"[brick] {self.address_string()} {fmt % args}")

    def _send_json(self, data: dict, status: int = 200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):  # noqa: N802
        path = self.path.split("?")[0].rstrip("/")

        if path == "/state":
            self._send_json(_read_state())

        elif path == "/toggle":
            current = _read_state().get("state", "off")
            should_enable = current != "on"   # flip: if currently on → disable, else enable
            data = _set_focus(should_enable)
            self._send_json(data)

        elif path == "/on":
            self._send_json(_set_focus(True))

        elif path == "/off":
            self._send_json(_set_focus(False))

        elif path == "/health":
            self._send_json({"status": "ok", "port": PORT})

        else:
            self._send_json({"error": "not found"}, 404)


def main():
    print(f"[brick] starting — defaulting to FocusOFF")
    _set_focus(False)   # always reset to off on (re)start

    server = HTTPServer(("0.0.0.0", PORT), BrickHandler)
    print(f"[brick] listening on port {PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[brick] shutting down")
        server.server_close()


if __name__ == "__main__":
    main()
