# Home SIEM Lab — Wazuh on Apple Silicon (8 GB)

A small, self-contained security monitoring lab built on a single M1 MacBook Pro (8 GB RAM).
It runs the Wazuh SIEM in containers, monitors two endpoints, and uses the Mac itself as the
attack box to generate and then hunt real detections.

## Goal

Practise blue-team / SOC skills end to end: deploy a SIEM, onboard endpoints, simulate attacks,
and triage the resulting alerts — all on hardware too small for a full multi-VM range.

## Architecture

```
          ┌───────────────────────── MacBook Pro (macOS, 8 GB) ─────────────────────────┐
          │                                                                              │
          │   Docker Desktop                                   Attack tooling (Homebrew) │
          │   ┌───────────────────────────────┐               - nmap                     │
          │   │ Wazuh single-node (compose)   │               - hydra                    │
          │   │  - wazuh.indexer  (1g heap)   │                                          │
          │   │  - wazuh.manager  :1514/:1515 │◄──────── agent 001 (this Mac)            │
          │   │  - wazuh.dashboard :443       │                                          │
          │   └───────────────────────────────┘                                          │
          │            ▲  https://localhost                                              │
          │            │                                                                 │
          │   UTM (Virtualize, ARM64)                                                    │
          │   ┌───────────────────────────────┐                                          │
          │   │ Ubuntu Server 24.04.5 "dml"   │                                          │
          │   │  192.168.64.2                 │──────── agent 002 ──► manager 192.168.64.1│
          │   │  wazuh-agent + auditd + sshd  │                                          │
          │   └───────────────────────────────┘                                          │
          └──────────────────────────────────────────────────────────────────────────────┘
```

- **SIEM:** Wazuh single-node (indexer + manager + dashboard) via the official `wazuh-docker` compose, v4.14.1.
  Indexer Java heap lowered to `-Xms1g -Xmx1g` to fit the RAM budget.
- **Endpoint 1:** the Mac itself — Wazuh macOS agent (ID 001), pointed at `localhost`.
- **Endpoint 2:** Ubuntu Server 24.04.5 ARM64 in UTM (ID 002, host `dml`, `192.168.64.2`),
  with `wazuh-agent` + `auditd` + OpenSSH. Reaches the manager at the Mac's UTM-network IP `192.168.64.1`.
- **Attack box:** the Mac (replaces a Kali VM there's no RAM for), using `nmap` and `hydra`,
  plus Atomic Red Team running *on* the Ubuntu endpoint.

## Memory budget (why it's built this way)

| Component | ~RAM |
|-----------|------|
| macOS | 2.5 GB |
| Wazuh stack | 3.5 GB |
| One VM | 2.0 GB |

Tight but workable on 8 GB. Only run one VM at a time; keep browsers closed during exercises.
If it swaps heavily, host the SIEM in Wazuh Cloud / Elastic Cloud instead and keep local RAM for endpoints.

## Operating the lab

**Start the SIEM** (from the `wazuh-docker/single-node` folder):
```bash
docker compose start      # if already created
# or first time:  docker compose up -d
```

**Stop the SIEM** (preserves data):
```bash
docker compose stop
```

**Dashboard:** https://localhost — accept the self-signed certificate warning.
Default login `admin` / `SecretPassword` (**change before any real-network exposure** — see Hardening).

**Check enrolled agents:**
```bash
docker exec single-node-wazuh.manager-1 /var/ossec/bin/agent_control -l
```

**Ubuntu VM:** start it in UTM (▶). It gets `192.168.64.x`; the Mac is reachable at `192.168.64.1`.

## Component versions (as built, 2026-11-10)

- macOS on Apple Silicon (M1)
- Docker Desktop 29.x
- Wazuh 4.14.1 (indexer / manager / dashboard + agents)
- UTM 5.0.8, Ubuntu Server 24.04.5 LTS (ARM64), kernel 6.8, OpenSSH 9.6p1
- PowerShell 7.6.9 + Invoke-AtomicRedTeam (on the Ubuntu endpoint)
- nmap 7.93, hydra 9.7 (on the Mac)

## Hardening TODO (before this ever touches a real network)

- [x] Rotate the Wazuh `admin` / indexer password (done 2026-11-10 — new hash applied to the
      indexer security index via `securityadmin.sh`; verified and durable across restarts).
- [ ] Rotate the Wazuh API password (`API_PASSWORD`).
- [ ] Restrict the dashboard to localhost only (don't publish :443 on `0.0.0.0` if remote).
- [ ] Replace the self-signed certs if accessed beyond localhost.

## Repository layout

```
.
├── README.md                       # this file
├── incident-report-2026-11-10.md   # attack simulation + triage write-up
└── wazuh-docker/                    # official compose + generated certs (single-node/)
```

> Lab use only. Never point the attack tooling at anything outside this lab.
