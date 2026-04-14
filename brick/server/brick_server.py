#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import json, os, time, urllib.request, urllib.error

PIHOLE_API   = "http://localhost/api"
PIHOLE_PASS  = "0990"
STATE_FILE   = os.path.expanduser("~/Desktop/brick/state.json")

_sid = None   # cached Pi-hole session id

# ── Pi-hole v6 auth ────────────────────────────────────────────────────────────

def _pihole_auth():
    global _sid
    req = urllib.request.Request(
        f"{PIHOLE_API}/auth",
        data=json.dumps({"password": PIHOLE_PASS}).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as r:
        data = json.loads(r.read())
    _sid = data["session"]["sid"]
    return _sid

def _sid_headers():
    global _sid
    if not _sid:
        _pihole_auth()
    return {"X-FTL-SID": _sid, "Content-Type": "application/json"}

def _pihole_request(method, path, body=None, retry=True):
    """Make an authenticated Pi-hole API request; re-auth once on 401."""
    global _sid
    url = f"{PIHOLE_API}{path}"
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=_sid_headers(), method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        if e.code == 401 and retry:
            _pihole_auth()
            return _pihole_request(method, path, body, retry=False)
        raise

# ── Pi-hole group helpers ──────────────────────────────────────────────────────

def _get_group(name):
    data = _pihole_request("GET", "/groups")
    for g in data.get("groups", []):
        if g["name"] == name:
            return g
    return None

def _set_group_enabled(name, enabled):
    g = _get_group(name)
    if g is None:
        raise RuntimeError(f"Pi-hole group '{name}' not found")
    _pihole_request("PUT", f"/groups/{name}", {
        "name": g["name"],
        "enabled": enabled,
        "comment": g.get("comment", ""),
    })

def apply_focus(on: bool):
    _set_group_enabled("FocusON",  on)
    _set_group_enabled("FocusOFF", not on)

# ── state helpers ──────────────────────────────────────────────────────────────

def load_state():
    if not os.path.exists(STATE_FILE):
        return {"focus": False, "updated_at": None}
    with open(STATE_FILE, "r") as f:
        return json.load(f)

def save_state(state):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        json.dump(state, f)

# ── HTTP handler ───────────────────────────────────────────────────────────────

class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # suppress access log noise

    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def _json(self, code, obj):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_response(204)
        self._cors()
        self.end_headers()

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
                apply_focus(st["focus"])
            except Exception as e:
                self._json(500, {"error": str(e), "state": st})
                return

            self._json(200, {"focus": st["focus"], "updated_at": st["updated_at"]})
            return

        self._json(404, {"error": "not found"})

    def do_POST(self):
        if self.path == "/block":
            length = int(self.headers.get("Content-Length", 0))
            try:
                payload = json.loads(self.rfile.read(length))
                domain = payload.get("domain", "").strip()
                if not domain:
                    self._json(400, {"error": "domain required"})
                    return
                _pihole_request("POST", "/domains/deny", {
                    "domain": domain,
                    "comment": "blocked via brick",
                    "enabled": True,
                    "type": "deny",
                })
                self._json(200, {"blocked": domain})
            except Exception as e:
                self._json(500, {"error": str(e)})
            return

        self._json(404, {"error": "not found"})

if __name__ == "__main__":
    # Ensure auth is established at startup
    try:
        _pihole_auth()
    except Exception as e:
        print(f"Warning: Pi-hole auth failed at startup: {e}")
    print("Brick server listening on :5123")
    HTTPServer(("0.0.0.0", 5123), Handler).serve_forever()
