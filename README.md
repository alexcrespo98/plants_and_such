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

pi-hole focus toggle. tiny http server (port 5123) that flips pi-hole blocklist groups on/off over tailscale.

```
brick/
├── state.json                  # current focus state (on/off + timestamp)
├── brick-server.service        # systemd unit — install to /etc/systemd/system/
├── scripts/
│   ├── focus-on.sh             # enables FocusON group, disables FocusOFF
│   └── focus-off.sh            # enables FocusOFF group, disables FocusON
└── server/
    └── brick_server.py         # http server on port 5123
```

**api (port 5123):**

| url | what it does |
|---|---|
| `/state` | returns current focus state + timestamp |
| `/toggle` | flips focus on ↔ off |
| `/on` | enables focus mode |
| `/off` | disables focus mode |
| `/health` | health check |

**pi-hole groups:**

| group | when active | purpose |
|---|---|---|
| FocusON | brick is ON | distracting sites blocked |
| FocusOFF | brick is OFF (default) | normal browsing |

**install:**
```bash
# copy files to raspberry pi
scp -r brick/ pi@<pi-ip>:~/Desktop/

# install and enable the persistent server service
sudo cp ~/Desktop/brick/brick-server.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable brick-server.service
sudo systemctl start brick-server.service

# check it's running
systemctl status brick-server.service
curl http://localhost:5123/state
```

**behaviour on restart:** server always defaults to FocusOFF on startup, then waits for `/toggle`, `/on`, or `/off` calls.

**permissions required** (`/etc/sudoers.d/`):
- `brick-pihole` — allows `sqlite3` on pi-hole db without password
- `brick-nopasswd` — allows focus scripts without password

## dependencies

- mosquitto (mqtt broker)
- node-red + node-red-dashboard
- sonos_bridge.py (flask, port 8090, uses soco)
- arduino libs: WiFi, PubSubClient, Preferences, HTTPClient
- pi-hole with FocusON + FocusOFF groups configured
