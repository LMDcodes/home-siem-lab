# Incident Report — Simulated Attack Chain Against `dml`

**Date:** 2026-11-10
**Analyst:** (lab owner)
**Environment:** Home SIEM lab (Wazuh 4.14.1, single-node)
**Target endpoint:** `dml` — Ubuntu Server 24.04.5, agent 002, `192.168.64.2`
**Attacker:** `192.168.64.1` (the lab's Mac, standing in for an external attacker)
**Classification:** Authorised internal test — all activity self-generated in an isolated lab.

---

## 1. Summary

A three-stage attack chain was executed against the Ubuntu endpoint to validate detection
coverage: network reconnaissance, SSH credential brute-forcing, and a MITRE ATT&CK
persistence technique (rogue account creation). All three stages produced alerts in Wazuh.
No stage succeeded in gaining access; the brute-force did not recover a valid password, and
the account-creation technique was simulated and then cleaned up.

## 2. Timeline (UTC)

| Time | Stage | Action | Source |
|------|-------|--------|--------|
| ~11:59 | Recon | `nmap -Pn -sV 192.168.64.2` — full TCP service scan | 192.168.64.1 |
| 12:02–12:03 | Credential Access | `hydra` SSH brute-force, user `tracysenpai`, 14 passwords | 192.168.64.1 |
| 12:34 | Persistence | Atomic Red Team **T1136.001** — created users `evil_user`, `butter` | on-host (pts/0) |
| 12:36 | Cleanup | ART `-Cleanup` — removed both test users | on-host |

## 3. Detections (observed in Wazuh)

| Stage | Wazuh Rule | Level | Count | Notes |
|-------|-----------|-------|-------|-------|
| Recon | 533 — Listening ports status changed | 7 | 43 | netstat delta around scan/activity |
| Brute-force | 5760 — `sshd: authentication failed` | 5 | 13 | one per failed password |
| Brute-force | 5503 — PAM user login failed | 5 | 4 | PAM-side failures |
| Brute-force | **2502 — User missed the password more than one time** | **10** | 4 | the key brute-force escalation |
| Persistence | **5902 — New user added to the system** | 8 | 2 | `evil_user` (UID 999), `butter` (UID 1001, home `/root`) |
| Cleanup | 5903 — Group/user deleted | 3 | 2 | `evil_user`, `butter` removed |
| Context | 5402 / 5403 — sudo to root / first-time sudo | 3–4 | 5 | privilege use during the exercise |

## 4. MITRE ATT&CK mapping

| Tactic | Technique | ID | Evidence in Wazuh |
|--------|-----------|----|-------------------|
| Reconnaissance | Active Scanning | T1595 | nmap scan; port-status alert (533) |
| Credential Access | Brute Force: Password Guessing | T1110.001 | rules 5760 ×13, 2502 ×4 from a single source IP in ~11 s |
| Persistence | Create Account: Local Account | T1136.001 | rule 5902 — `evil_user`, `butter` |
| Defense Evasion | Indicator Removal (cleanup analogue) | T1070 | rule 5903 — accounts deleted shortly after creation |

## 5. Analysis

- **Brute-force is the clearest signal.** 13 `sshd` failures plus four level-10 "repeated
  password miss" alerts, all from `192.168.64.1` against one user inside ~11 seconds, is an
  unambiguous password-guessing pattern. In production this should page an analyst and/or
  trigger an automatic source-IP block (Wazuh active response).
- **Account creation fired cleanly** via `auditd`/syslog → rule 5902, including the suspicious
  `butter` account whose home was set to `/root` — a detail worth calling out in triage, since
  a root-homed service-style account is a common persistence tell.
- **Recon is noisier / weaker.** The port scan itself did not raise a dedicated "port scan"
  alert (no firewall logging configured); it surfaced only indirectly via netstat change events.
  A detection gap to close (see below).

## 6. Recommendations / detection gaps

1. **Add host-firewall logging** (ufw/iptables → Wazuh) so port scans raise a direct alert,
   not just a netstat side effect.
2. **Enable Wazuh active response** to auto-block an IP after N SSH failures (firewall-drop).
3. **Alert on new local accounts** as high priority, and specifically flag accounts with
   `home=/root` or UID < 1000.
4. **Tune brute-force correlation** (rule 5712 family) and confirm it escalates before 13 tries.
5. Repeat with more Atomic tests (T1059 command execution, T1053 cron persistence, T1070.003
   history clearing) to broaden coverage.

## 7. Outcome

All three attack stages were detected. No unauthorised access achieved. Lab returned to a
clean state (test accounts removed, confirmed by rule 5903). Detection coverage is strong for
credential access and account creation, with a known gap around network-scan visibility.
