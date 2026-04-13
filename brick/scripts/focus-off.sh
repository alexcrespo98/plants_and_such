#!/usr/bin/env bash
set -euo pipefail
DB="/etc/pihole/gravity.db"

sudo sqlite3 "$DB" <<'SQL'
UPDATE "group" SET enabled=0 WHERE name='FocusON';
UPDATE "group" SET enabled=1 WHERE name='FocusOFF';
SQL

sudo systemctl restart pihole-FTL
echo "Focus OFF (FocusON disabled, FocusOFF enabled)"
