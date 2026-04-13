#!/bin/bash
# focus-off.sh — enable FocusOFF group (normal browsing), disable FocusON group
set -euo pipefail

PIHOLE_DB="/etc/pihole/gravity.db"

sudo sqlite3 "$PIHOLE_DB" "
BEGIN TRANSACTION;
UPDATE domainlist_by_group SET enabled=1 WHERE group_id=(SELECT id FROM \`group\` WHERE name='FocusOFF');
UPDATE domainlist_by_group SET enabled=0 WHERE group_id=(SELECT id FROM \`group\` WHERE name='FocusON');
UPDATE \`group\` SET enabled=1 WHERE name='FocusOFF';
UPDATE \`group\` SET enabled=0 WHERE name='FocusON';
COMMIT;
"

pihole restartdns reload
echo "focus off — FocusOFF group active"
