#!/usr/bin/env bash
# Install the Cowrie rules on the Wazuh manager container and create the
# "honeypot" agent group the Cowrie agent enrolls into. Safe to re-run.
set -euo pipefail

MANAGER="${WAZUH_MANAGER_CONTAINER:-single-node-wazuh.manager-1}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"

echo "[*] Copying cowrie_rules.xml into $MANAGER"
docker cp "$HERE/wazuh-manager/cowrie_rules.xml" "$MANAGER:/var/ossec/etc/rules/cowrie_rules.xml"
docker exec "$MANAGER" chown wazuh:wazuh /var/ossec/etc/rules/cowrie_rules.xml
docker exec "$MANAGER" chmod 660 /var/ossec/etc/rules/cowrie_rules.xml

echo "[*] Ensuring agent group 'honeypot' exists"
groups=$(docker exec "$MANAGER" /var/ossec/bin/agent_groups -l 2>/dev/null || true)
if ! grep -qw honeypot <<<"$groups"; then
  docker exec "$MANAGER" /var/ossec/bin/agent_groups -a -g honeypot -q
fi

echo "[*] Restarting Wazuh manager (validates the ruleset)"
docker exec "$MANAGER" /var/ossec/bin/wazuh-control restart >/dev/null 2>&1 || true
running=no
for _ in $(seq 1 30); do
  status=$(docker exec "$MANAGER" /var/ossec/bin/wazuh-control status 2>/dev/null || true)
  if grep -q "wazuh-analysisd is running" <<<"$status"; then
    running=yes; break
  fi
  sleep 2
done
errors=$(docker exec "$MANAGER" tail -n 200 /var/ossec/logs/ossec.log | grep -iE "(error|critical).*(rule|cowrie)" || true)
if [ -n "$errors" ] || [ "$running" != yes ]; then
  echo "[!] Manager reported rule errors:"
  echo "$errors"
  exit 1
fi
echo "[+] Rules loaded. Run scripts/test-rules.sh to check them with wazuh-logtest."
