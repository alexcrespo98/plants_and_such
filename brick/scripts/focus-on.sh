#!/bin/bash
# focus-on.sh — enable FocusON group (blocking), disable FocusOFF group
set -euo pipefail

PIHOLE_DB="/etc/pihole/gravity.db"

sudo sqlite3 "$PIHOLE_DB" "
BEGIN TRANSACTION;
UPDATE domainlist_by_group SET enabled=1 WHERE group_id=(SELECT id FROM \`group\` WHERE name='FocusON');
UPDATE domainlist_by_group SET enabled=0 WHERE group_id=(SELECT id FROM \`group\` WHERE name='FocusOFF');
UPDATE \`group\` SET enabled=1 WHERE name='FocusON';
UPDATE \`group\` SET enabled=0 WHERE name='FocusOFF';
COMMIT;
"

pihole restartdns reload
echo "focus on — FocusON group active"
