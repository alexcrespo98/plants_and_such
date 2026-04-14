# plants_and_such — homelab

home automation for the cottage. mqtt, sonos, aquarium lights, node-red dashboard, pi-hole focus toggle.

## network

| device | ip | role |
|---|---|---|
| homelab server | 192.168.0.32 | mqtt broker, node-red, sonos bridge |
| sonos coordinator | 192.168.0.31 | speaker |
| esp32-c6 #1 | dhcp | aquarium relay |
| esp32-c6 #2 | dhcp | sonos button |

## firmware

### relay (`relay/relay.ino`)
controls aquarium light via gpio 0. connects to mqtt, syncs schedule via ntp, stores schedule in nvs so it survives reboots and wifi outages.

mqtt topics:
- `house/relay1/set` → ON / OFF
- `house/relay1/status` ← current state (every 30s)
- `house/relay1/schedule/set` → {"on":"08:00","off":"22:00"}
- `house/relay1/schedule/current` ← active schedule
- `house/relay1/schedule/get` → triggers publish

### button (`button/button.ino`)
physical sonos controller. gpio 9 input_pullup.
- single click → play/pause
- double click → next track
- long press (1s) → party mode playlist

## node-red (`nodered/dashboard.json`)

import into node-red at http://192.168.0.32:1880

tabs:
- **aquarium** — light switch + schedule
- **sonos** — play/pause, next, party mode, volume
- **alarm + timer** — per-day alarm with time groups, countdown timer, both play "alarm" playlist at vol 50 and auto-stop after 10 min

## brick (`brick/`)

pi-hole focus toggle. tiny http server (port 5123) that flips pi-hole blocklist groups on/off over tailscale, using the **pi-hole v6 REST API** (no sqlite3, no pihole-FTL restarts). a live WebSocket stream server on port 5124 feeds a standalone dashboard.

```
brick/
├── state.json                     # current focus state (on/off + timestamp)
├── brick-server.service           # systemd unit — install to /etc/systemd/system/
├── dashboard.html                 # standalone dark-theme dashboard (open in browser)
├── scripts/
│   ├── focus-on.sh                # curl shortcut → POST /on
│   └── focus-off.sh               # curl shortcut → POST /off
└── server/
    ├── brick_server.py            # http server on port 5123
    ├── stream_server.py           # WebSocket server on port 5124 (live DNS feed)
    └── stream_server.service      # systemd unit for stream server
```

**api (port 5123):**

| url | method | what it does |
|---|---|---|
| `/state` | GET | returns current focus state + timestamp |
| `/toggle` | GET | flips focus on ↔ off |
| `/on` | GET | enables focus mode |
| `/off` | GET | disables focus mode |
| `/health` | GET | health check |
| `/block` | POST | adds `{"domain": "…"}` to pi-hole deny list |

**WebSocket (port 5124):**

streams DNS queries as JSON: `{"domain": "…", "client": "…", "status": "…", "time": …, "phone": false, "focus": true}`

**pi-hole groups:**

| group | when active | purpose |
|---|---|---|
| FocusON | brick is ON | distracting sites blocked |
| FocusOFF | brick is OFF (default) | normal browsing |

**phone exclusion:** `192.168.0.9` (MAC `e6:8e:39:e7:64:36`) is highlighted in the dashboard feed with `"phone": true` / `★phone`. to fully exclude the phone from focus blocks, assign it to a separate pi-hole client group that does not inherit the FocusON blocklist (Pi-hole admin → Groups → assign phone MAC to a group that FocusON does not apply to).

**dependencies:**
```bash
# websockets library (for stream_server.py)
sudo apt install python3-websockets
# or:
pip3 install websockets --break-system-packages
```

**install:**
```bash
# copy files to the server (pi-hole runs on localhost / 192.168.0.32)
scp -r brick/ crespo@192.168.0.32:~/Desktop/

# brick http server (port 5123)
sudo cp ~/Desktop/brick/brick-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now brick-server.service

# live query stream (port 5124)
sudo cp ~/Desktop/brick/server/stream_server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now stream_server.service

# verify
curl http://localhost:5123/state
systemctl status brick-server.service stream_server.service
```

open `brick/dashboard.html` directly in the browser — no build step, no server required.

**behaviour on restart:** server always defaults to the last saved state in `state.json`; on first run defaults to FocusOFF.

**architecture:**
- `brick_server.py` authenticates with pi-hole v6 (`POST /api/auth` → `sid`), then calls `PUT /api/groups/{name}` to toggle groups — instant, no pihole-FTL restart needed.
- `stream_server.py` polls `GET /api/queries?max=25` every 2 s and pushes new entries over WebSocket. handles re-auth automatically on session expiry.
- sudoers entries for sqlite3 / focus scripts are **no longer needed**.

## dependencies

- mosquitto (mqtt broker)
- node-red + node-red-dashboard
- sonos_bridge.py (flask, port 8090, uses soco)
- arduino libs: WiFi, PubSubClient, Preferences, HTTPClient
- pi-hole v6 with FocusON + FocusOFF groups configured
- python3-websockets (for `brick/server/stream_server.py`)
