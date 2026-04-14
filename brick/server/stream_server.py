#!/usr/bin/env python3
"""
stream_server.py — WebSocket server on port 5124
Polls Pi-hole v6 /api/queries every 2 s and broadcasts new DNS queries
to every connected browser client.
"""
import asyncio, json, os, time, urllib.request, urllib.error
import websockets

PIHOLE_API  = "http://localhost/api"
PIHOLE_PASS = "0990"
PHONE_IP    = "192.168.0.9"
STATE_FILE  = os.path.expanduser("~/Desktop/brick/state.json")
POLL_SECS   = 2
PORT        = 5124

_sid = None

# ── Pi-hole auth ───────────────────────────────────────────────────────────────

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

def _fetch_queries(max_results=25):
    global _sid
    if not _sid:
        _pihole_auth()
    url = f"{PIHOLE_API}/queries?max={max_results}"
    req = urllib.request.Request(url, headers={"X-FTL-SID": _sid})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        if e.code == 401:
            _pihole_auth()
            req = urllib.request.Request(url, headers={"X-FTL-SID": _sid})
            with urllib.request.urlopen(req, timeout=10) as r:
                return json.loads(r.read())
        raise

def _load_focus():
    try:
        if os.path.exists(STATE_FILE):
            with open(STATE_FILE) as f:
                return json.load(f).get("focus", False)
    except Exception:
        pass
    return False

# ── broadcast helpers ──────────────────────────────────────────────────────────

CLIENTS: set = set()

async def broadcast(msg: str):
    if CLIENTS:
        await asyncio.gather(*[c.send(msg) for c in list(CLIENTS)], return_exceptions=True)

# ── polling loop ───────────────────────────────────────────────────────────────

async def poll_loop():
    seen_times: set = set()
    while True:
        await asyncio.sleep(POLL_SECS)
        if not CLIENTS:
            continue
        focus = _load_focus()
        try:
            data = await asyncio.get_event_loop().run_in_executor(None, _fetch_queries)
            queries = data.get("queries", [])
        except Exception as e:
            print(f"[stream] query fetch error: {e}")
            continue

        new_msgs = []
        for q in queries:
            ts = q.get("time", 0)
            if ts in seen_times:
                continue
            seen_times.add(ts)

            client_ip = q.get("client", {}).get("ip", "")
            is_phone  = client_ip == PHONE_IP

            msg = {
                "domain": q.get("domain", ""),
                "client": client_ip,
                "status": q.get("status", ""),
                "time":   ts,
                "phone":  is_phone,
                "focus":  focus,
            }
            new_msgs.append(json.dumps(msg))

        # keep seen_times bounded — sort numerically so we keep the most recent timestamps
        if len(seen_times) > 5000:
            seen_times = set(sorted(seen_times)[-2500:])

        for m in reversed(new_msgs):   # oldest-first to client
            await broadcast(m)

# ── WebSocket handler ──────────────────────────────────────────────────────────

async def handler(ws):
    CLIENTS.add(ws)
    print(f"[stream] client connected ({len(CLIENTS)} total)")
    try:
        await ws.wait_closed()
    finally:
        CLIENTS.discard(ws)
        print(f"[stream] client disconnected ({len(CLIENTS)} total)")

# ── entry point ────────────────────────────────────────────────────────────────

async def main():
    # Initial auth
    try:
        _pihole_auth()
        print("[stream] Pi-hole auth OK")
    except Exception as e:
        print(f"[stream] Pi-hole auth warning: {e}")

    async with websockets.serve(handler, "0.0.0.0", PORT):
        print(f"[stream] WebSocket server on :{PORT}")
        await poll_loop()

if __name__ == "__main__":
    asyncio.run(main())
