#!/usr/bin/env bash
# Replay sample Cowrie events through wazuh-logtest on the manager (one session,
# so frequency/correlation rules work) and print which rule each event hits.
# Also sends 8 extra failed logins to exercise the brute-force rules.
set -euo pipefail

MANAGER="${WAZUH_MANAGER_CONTAINER:-single-node-wazuh.manager-1}"
HERE="$(cd "$(dirname "$0")" && pwd)"

events() {
  # Brute force: 8 failures, then the success line from the sample file
  for i in $(seq 1 8); do
    printf '{"eventid":"cowrie.login.failed","username":"root","password":"guess%s","src_ip":"192.168.64.2","session":"bf00%s","message":"login attempt failed","sensor":"cowrie-honeypot"}\n' "$i" "$i"
  done
  grep -v '^$' "$HERE/sample-events.json"
}

events | docker exec -i "$MANAGER" /var/ossec/bin/wazuh-logtest 2>&1 | awk '
  function flush() { if (ev != "") printf "%-30s %-7s %-6s %s\n", ev, (id?id:"-"), (lvl?lvl:"-"), (desc?desc:"NO MATCH"); ev=id=lvl=desc="" }
  BEGIN { printf "%-30s %-7s %-6s %s\n", "eventid", "rule", "level", "description" }
  /^\*\*Phase 1/                { flush() }
  /^\teventid: /                { ev=$0; sub(/^\teventid: \x27/, "", ev); sub(/\x27$/, "", ev) }
  /^\tid: /                     { id=$0;  gsub(/[^0-9]/, "", id) }
  /^\tlevel: /                  { lvl=$0; gsub(/[^0-9]/, "", lvl) }
  /^\tdescription: /            { desc=$0; sub(/^\tdescription: \x27/, "", desc); sub(/\x27$/, "", desc) }
  END { flush() }'
