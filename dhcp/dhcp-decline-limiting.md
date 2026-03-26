# Kea DHCP — DHCPDECLINE Monitoring & Action Pipeline

## Overview

Kea cannot act on DHCPDECLINE events by itself, but it exposes the statistics and hooks needed to build an external action pipeline. This document covers the full implementation: stats to watch, in-Kea levers, and external remediation options.

---

## 1. Key Statistics

All stats are accessible via the Kea Control Agent REST API at `http://localhost:8000/`.

### Global Stats

| Statistic | Type | Description |
|---|---|---|
| `declined-addresses` | integer | IPs currently in probation (unavailable). Should always be zero. |
| `reclaimed-declined-addresses` | integer | Cumulative count of IPs recovered from probation. Never decreases — useful for long-term trending. |

### Per-Subnet Stats

| Statistic | Description |
|---|---|
| `subnet[id].declined-addresses` | Declined IPs in a specific subnet. Use to identify which subnet is under pressure. |
| `subnet[id].reclaimed-declined-addresses` | Recovery trend per subnet. |

### Per-Pool Stats

| Statistic | Description |
|---|---|
| `subnet[id].pool[pid].declined-addresses` | Declined IPs within a specific pool. Useful for granular pool exhaustion detection. |
| `subnet[id].pool[pid].reclaimed-declined-addresses` | Recovery trend per pool. |

### Reading Stats via REST API

```bash
# All stats
curl -s -X POST http://localhost:8000/ \
  -H "Content-Type: application/json" \
  -d '{"command":"statistic-get-all","service":["dhcp4"]}' | jq .

# Single stat
curl -s -X POST http://localhost:8000/ \
  -H "Content-Type: application/json" \
  -d '{"command":"statistic-get","service":["dhcp4"],
       "arguments":{"name":"declined-addresses"}}' | jq .
```

---

## 2. Understanding the Two Problems

### Problem A — Legitimate Duplicate Address (Rogue Device on Network)

A client correctly sends DHCPDECLINE because another device is already using the offered IP.

**Signal:** `declined-addresses` rises, `reclaimed-declined-addresses` also rises steadily after the probation period expires.

**Action:** Investigate the network for rogue devices or stale static assignments. Alert when `declined-addresses > 0` for more than one probation cycle.

### Problem B — Misbehaving Client Looping DECLINE (Pool Exhaustion Risk)

A client incorrectly and repeatedly sends DHCPDECLINE, cycling through available IPs and putting them all on probation.

**Signal:** `reclaimed-declined-addresses` is accelerating, but `declined-addresses` stays persistently high — IPs are being churned faster than they recover.

**Action:** Rate-limit or block the offending client. Shorten the probation period to recover IPs faster.

---

## 3. In-Kea Levers

### Lever 1 — Probation Period (Global, Static)

Controls how long a declined IP stays unavailable before re-entering the pool.

```json
{
  "Dhcp4": {
    "decline-probation-period": 300
  }
}
```

| Environment | Recommended Value |
|---|---|
| Controlled enterprise | 3600 (1 hour) |
| ISP / public network | 300–600 (5–10 min) |
| Default (untuned) | 86400 (24 hours) — often too long |

> **Tip:** Monitor the ratio of `declined-addresses` vs `reclaimed-declined-addresses` over time to tune this value. If recovery is too slow relative to the decline rate, reduce the period.

---

### Lever 2 — Per-MAC Rate Limiting via `limits` Hook (Static)

Prevents a single client from repeatedly declining IPs. Uses the `limits` hook library (must be loaded).

```json
{
  "hooks-libraries": [
    {
      "library": "/usr/lib/kea/hooks/libdhcp_limits.so"
    }
  ],
  "client-classes": [
    {
      "name": "declines",
      "template-test": "ifelse(pkt4.msgtype == 4, hexstring(pkt4.mac, ':'), '')",
      "user-context": {
        "limits": {
          "rate-limit": "3 packets per hour"
        }
      }
    }
  ]
}
```

**How it works:** Any client sending a DHCPDECLINE (msgtype == 4) is placed into the `declines` class by MAC address. Once the rate limit is hit, further DECLINE messages from that MAC are silently dropped.

**Limitation — this is not dynamic.** Changing the rate requires either:

- A `config-reload` (reads from disk)
- A `config-set` via the REST API (full config push, no restart)

Neither allows per-client tuning at runtime. The rate applies globally to all clients matching the class.

For IPv6, replace `pkt4.msgtype == 4` with `pkt6.msgtype == 9`.

---

## 4. External Dynamic Remediation

Since Lever 2 is static, runtime per-client action must come from outside Kea.

### Option A — Dynamic MAC Blackhole via `host-cmds` Hook

The most surgical option. Uses the `host-cmds` hook to add a host reservation at runtime via the REST API — no config reload required.

**Load the hook:**

```json
{
  "hooks-libraries": [
    {
      "library": "/usr/lib/kea/hooks/libdhcp_host_cmds.so"
    }
  ]
}
```

**Block a MAC at runtime:**

```bash
curl -s -X POST http://localhost:8000/ \
  -H "Content-Type: application/json" \
  -d '{
    "command": "reservation-add",
    "service": ["dhcp4"],
    "arguments": {
      "reservation": {
        "hw-address": "aa:bb:cc:dd:ee:ff",
        "subnet-id": 1,
        "boot-file-name": "",
        "next-server": "0.0.0.0",
        "server-hostname": "",
        "ip-address": "0.0.0.0"
      }
    }
  }'
```

**Remove the block when resolved:**

```bash
curl -s -X POST http://localhost:8000/ \
  -H "Content-Type: application/json" \
  -d '{
    "command": "reservation-del",
    "service": ["dhcp4"],
    "arguments": {
      "subnet-id": 1,
      "identifier-type": "hw-address",
      "identifier": "aa:bb:cc:dd:ee:ff"
    }
  }'
```

> **Note:** `ip-address: "0.0.0.0"` does not blackhole traffic at the network level — it only prevents Kea from offering that MAC a lease. For full isolation, combine with Option B.

---

### Option B — Network-Level Isolation (Switch / RADIUS)

For complete isolation of the offending device, act at the network edge:

- **802.1X + RADIUS CoA** — send a Change-of-Authorization to bounce or quarantine the port
- **Switch port ACL** — dynamically apply a MAC-based ACL via SNMP or switch API
- **VLAN steering** — move the MAC to a quarantine VLAN

This is outside Kea entirely but is the most effective for a truly misbehaving device.

---

## 5. Recommended Monitoring Pipeline

```
Kea Stats REST API (polled every 60s)
  │
  ├─ declined-addresses > 0 for > N minutes
  │     → Alert: investigate for rogue device
  │
  ├─ subnet[id].declined-addresses rising rapidly
  │     → Alert: pool exhaustion risk on subnet id
  │
  └─ reclaimed-declined-addresses rate accelerating
        → Correlate with DHCP4_DECLINE_LEASE log entries
        → Identify offending MAC from logs
        → Trigger: reservation-add to blackhole MAC (Option A)
        → Optional: RADIUS CoA to isolate port (Option B)
```

### Useful Log Correlation

When a decline occurs, Kea logs `DHCP4_DECLINE_LEASE`. This log entry contains the MAC address and declined IP. Correlate this with rising stats to identify the offending client:

```bash
grep DHCP4_DECLINE_LEASE /var/log/kea/kea-dhcp4.log | \
  awk '{print $NF}' | sort | uniq -c | sort -rn | head -20
```

---

## 6. Summary of Options

| Mechanism | Dynamic? | Granularity | Requires |
|---|---|---|---|
| `decline-probation-period` | No (config reload) | Global | Base Kea config |
| `limits` hook rate-limit | No (config reload) | Per MAC class | `libdhcp_limits.so` |
| `host-cmds` reservation blackhole | **Yes (runtime)** | Per MAC + subnet | `libdhcp_host_cmds.so` |
| RADIUS CoA / switch ACL | **Yes (runtime)** | Per port / MAC | Network infrastructure |

For most environments, the recommended combination is:

1. **Tune `decline-probation-period`** down from the 24h default
2. **Load `limits` hook** with a reasonable class-wide rate (e.g. 3/hour)
3. **Load `host-cmds` hook** for runtime MAC blocking by an external script triggered on stat thresholds
4. **Alert on `declined-addresses > 0`** via your monitoring stack
