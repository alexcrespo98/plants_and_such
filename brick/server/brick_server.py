#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import json, os, subprocess, time

STATE_FILE = os.path.expanduser("~/Desktop/brick/state.json")
FOCUS_ON_SCRIPT = os.path.expanduser("~/Desktop/brick/scripts/focus-on.sh")
FOCUS_OFF_SCRIPT = os.path.expanduser("~/Desktop/brick/scripts/focus-off.sh")

def load_state():
    if not os.path.exists(STATE_FILE):
        return {"focus": False, "updated_at": None}
    with open(STATE_FILE, "r") as f:
        return json.load(f)

def save_state(state):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)

def run_script(path):
    # no shell, safer
    subprocess.check_call([path])

class Handler(BaseHTTPRequestHandler):
    def _json(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._json(200, {"ok": True})
            return

        if self.path == "/state":
            self._json(200, load_state())
            return

        if self.path in ("/on", "/off", "/toggle"):
            st = load_state()

            if self.path == "/toggle":
                st["focus"] = not bool(st.get("focus"))
            elif self.path == "/on":
                st["focus"] = True
            elif self.path == "/off":
                st["focus"] = False

            st["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
            save_state(st)

            try:
                run_script(FOCUS_ON_SCRIPT if st["focus"] else FOCUS_OFF_SCRIPT)
            except Exception as e:
                self._json(500, {"error": str(e), "state": st})
                return

            self._json(200, {"focus": st["focus"], "updated_at": st["updated_at"]})
            return

        self._json(404, {"error": "not found"})

if __name__ == "__main__":
    # Bind to all so Tailscale can reach it
    HTTPServer(("0.0.0.0", 5123), Handler).serve_forever()
