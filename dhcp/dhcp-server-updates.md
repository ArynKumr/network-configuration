# Fetching Kea DHCP Stats — Kea 3.0+

This guide walks through how to query the ISC Kea DHCP daemons — both DHCPv4 and DHCPv6 — directly via their built-in HTTP control channel introduced in Kea 3.0.

> **Kea 3.0 Change:** The separate `kea-ctrl-agent` process is no longer required. Each daemon (`kea-dhcp4`, `kea-dhcp6`, `kea-dhcp-ddns`) now exposes its own HTTP/HTTPS control channel directly. You talk straight to the service.

---

## Prerequisites

You will need `curl` installed — it almost certainly already is:

```bash
apt install curl       # Debian/Ubuntu
dnf install curl       # RHEL/Fedora
```

---

## Configuring the Control Channel

Each daemon needs a `control-sockets` block in its config. This replaces the old singular `control-socket` key from pre-3.0.

**kea-dhcp4.conf:**

```json
"control-sockets": [
    {
        "socket-type": "http",
        "socket-address": "127.0.0.1",
        "socket-port": 8000
    }
]
```

**kea-dhcp6.conf:**

```json
"control-sockets": [
    {
        "socket-type": "http",
        "socket-address": "127.0.0.1",
        "socket-port": 8001
    }
]
```

Restart the daemons after adding these blocks:

```bash
systemctl restart kea-dhcp4
systemctl restart kea-dhcp6
```

> **Note:** There is no default port — if this block is absent the control channel simply does not start.

---

## Sending a Command

All Kea control commands follow the same JSON envelope:

```json
{
  "command": "<command-name>",
  "arguments": {}
}
```

The general pattern via `curl`:

```bash
curl -s -X POST http://127.0.0.1:<port> \
  -H "Content-Type: application/json" \
  -d '{ "command": "<command-name>", "arguments": {} }'
```

---

## DHCPv4

### Fetch All Stats

```bash
curl -s -X POST http://127.0.0.1:8000 \
  -H "Content-Type: application/json" \
  -d '{ "command": "statistic-get-all", "arguments": {} }'
```

**Sample output:**

```
 curl -s -X POST http://127.0.0.1:8000 \
  -H "Content-Type: application/json" \
  -d '{ "command": "statistic-get-all", "arguments": {} }'
[ { "arguments": { "cumulative-assigned-addresses": [ [ 0, "2026-03-27 21:45:18.959783" ] ], "declined-addresses": [ [ 0, "2026-03-27 21:45:18.959781" ] ], "pkt4-ack-received": [ [ 0, "2026-03-27 21:45:18.889685" ] ], "pkt4-ack-sent": [ [ 0, "2026-03-27 21:45:18.889686" ] ], "pkt4-decline-received": [ [ 0, "2026-03-27 21:45:18.889686" ] ], "pkt4-discover-received": [ [ 0, "2026-03-27 21:45:18.889687" ] ], "pkt4-inform-received": [ [ 0, "2026-03-27 21:45:18.889687" ] ], "pkt4-nak-received": [ [ 0, "2026-03-27 21:45:18.889687" ] ], "pkt4-nak-sent": [ [ 0, "2026-03-27 21:45:18.889688" ] ], "pkt4-offer-received": [ [ 0, "2026-03-27 21:45:18.889688" ] ], "pkt4-offer-sent": [ [ 0, "2026-03-27 21:45:18.889689" ] ], "pkt4-parse-failed": [ [ 0, "2026-03-27 21:45:18.889690" ] ], "pkt4-receive-drop": [ [ 0, "2026-03-27 21:45:18.889690" ] ], "pkt4-received": [ [ 0, "2026-03-27 21:45:18.889691" ] ], "pkt4-release-received": [ [ 0, "2026-03-27 21:45:18.889691" ] ], "pkt4-request-received": [ [ 0, "2026-03-27 21:45:18.889691" ] ], "pkt4-sent": [ [ 0, "2026-03-27 21:45:18.889692" ] ], "pkt4-unknown-received": [ [ 0, "2026-03-27 21:45:18.889692" ] ], "reclaimed-declined-addresses": [ [ 0, "2026-03-27 21:45:18.959781" ] ], "reclaimed-leases": [ [ 0, "2026-03-27 21:45:18.959783" ] ], "subnet[1].assigned-addresses": [ [ 1, "2026-03-27 21:45:18.959795" ], [ 0, "2026-03-27 21:45:18.959785" ] ], "subnet[1].cumulative-assigned-addresses": [ [ 0, "2026-03-27 21:45:18.959628" ] ], "subnet[1].declined-addresses": [ [ 0, "2026-03-27 21:45:18.959786" ] ], "subnet[1].pool[0].assigned-addresses": [ [ 1, "2026-03-27 21:45:18.959836" ], [ 0, "2026-03-27 21:45:18.959789" ] ], "subnet[1].pool[0].cumulative-assigned-addresses": [ [ 0, "2026-03-27 21:45:18.959633" ] ], "subnet[1].pool[0].declined-addresses": [ [ 0, "2026-03-27 21:45:18.959791" ] ], "subnet[1].pool[0].reclaimed-declined-addresses": [ [ 0, "2026-03-27 21:45:18.959792" ] ], "subnet[1].pool[0].reclaimed-leases": [ [ 0, "2026-03-27 21:45:18.959793" ] ], "subnet[1].pool[0].total-addresses": [ [ 253, "2026-03-27 21:45:18.959632" ] ], "subnet[1].reclaimed-declined-addresses": [ [ 0, "2026-03-27 21:45:18.959787" ] ], "subnet[1].reclaimed-leases": [ [ 0, "2026-03-27 21:45:18.959788" ] ], "subnet[1].total-addresses": [ [ 253, "2026-03-27 21:45:18.959626" ] ], "subnet[1].v4-lease-reuses": [ [ 0, "2026-03-27 21:45:18.959629" ] ], "subnet[1].v4-reservation-conflicts": [ [ 0, "2026-03-27 21:45:18.959630" ] ], "v4-allocation-fail": [ [ 0, "2026-03-27 21:45:18.889693" ] ], "v4-allocation-fail-classes": [ [ 0, "2026-03-27 21:45:18.889694" ] ], "v4-allocation-fail-no-pools": [ [ 0, "2026-03-27 21:45:18.889694" ] ], "v4-allocation-fail-shared-network": [ [ 0, "2026-03-27 21:45:18.889695" ] ], "v4-allocation-fail-subnet": [ [ 0, "2026-03-27 21:45:18.889695" ] ], "v4-lease-reuses": [ [ 0, "2026-03-27 21:45:18.889695" ] ], "v4-reservation-conflicts": [ [ 0, "2026-03-27 21:45:18.889696" ] ] }, "result": 0 } ]
```

---

### Fetch a Specific Stat

```bash
curl -s -X POST http://127.0.0.1:8000 \
  -H "Content-Type: application/json" \
  -d '{ "command": "statistic-get", "arguments": { "name": "cumulative-assigned-addresses" } }'
```

**Sample output:**

```
[ { "arguments": { "cumulative-assigned-addresses": [ [ 0, "2026-03-27 21:45:18.959783" ] ] }, "result": 0 } ]
```

---

### Fetch Per-Subnet Lease Counts

```bash
curl -s -X POST http://127.0.0.1:8000 \
  -H "Content-Type: application/json" \
  -d '{ "command": "statistic-get", "arguments": { "name": "subnet[1].assigned-addresses" } }'
```

> Replace `1` with your actual subnet ID as defined in `kea-dhcp4.conf`.

**Sample output:**

```
[ { "arguments": { "subnet[1].assigned-addresses": [ [ 1, "2026-03-27 21:45:18.959795" ], [ 0, "2026-03-27 21:45:18.959785" ] ] }, "result": 0 } ]
```

---

### List Active Leases (Lease Commands Hook)

If you have `libdhcp_lease_cmds.so` loaded:

```bash
curl -s -X POST http://127.0.0.1:8000 \
  -H "Content-Type: application/json" \
  -d '{ "command": "lease4-get-all", "arguments": {} }'
```

**Sample output:**

```
curl -s -X POST http://127.0.0.1:8000 \
  -H "Content-Type: application/json" \
  -d '{ "command": "lease4-get-all", "arguments": {} }'
[ { "result": 1, "text": "'subnets' parameter not specified" } ]
```

---

## DHCPv6

Same command structure — just point at the DHCPv6 daemon port.

### Fetch All Stats

```bash
curl -s -X POST http://127.0.0.1:8001 \
  -H "Content-Type: application/json" \
  -d '{ "command": "statistic-get-all", "arguments": {} }'
```

**Sample output:**

```
curl -s -X POST http://127.0.0.1:8001 \
  -H "Content-Type: application/json" \
  -d '{ "command": "statistic-get-all", "arguments": {} }'
[ { "arguments": { "cumulative-assigned-nas": [ [ 0, "2026-03-27 21:52:47.992153" ] ], "cumulative-assigned-pds": [ [ 0, "2026-03-27 21:52:47.992153" ] ], "cumulative-registered-nas": [ [ 0, "2026-03-27 21:52:47.992154" ] ], "declined-addresses": [ [ 0, "2026-03-27 21:52:47.992151" ] ], "pkt6-addr-reg-inform-received": [ [ 0, "2026-03-27 21:52:47.977248" ] ], "pkt6-addr-reg-reply-received": [ [ 0, "2026-03-27 21:52:47.977249" ] ], "pkt6-addr-reg-reply-sent": [ [ 0, "2026-03-27 21:52:47.977249" ] ], "pkt6-advertise-received": [ [ 0, "2026-03-27 21:52:47.977249" ] ], "pkt6-advertise-sent": [ [ 0, "2026-03-27 21:52:47.977250" ] ], "pkt6-decline-received": [ [ 0, "2026-03-27 21:52:47.977250" ] ], "pkt6-dhcpv4-query-received": [ [ 0, "2026-03-27 21:52:47.977251" ] ], "pkt6-dhcpv4-response-received": [ [ 0, "2026-03-27 21:52:47.977251" ] ], "pkt6-dhcpv4-response-sent": [ [ 0, "2026-03-27 21:52:47.977251" ] ], "pkt6-infrequest-received": [ [ 0, "2026-03-27 21:52:47.977251" ] ], "pkt6-parse-failed": [ [ 0, "2026-03-27 21:52:47.977251" ] ], "pkt6-rebind-received": [ [ 0, "2026-03-27 21:52:47.977252" ] ], "pkt6-receive-drop": [ [ 0, "2026-03-27 21:52:47.977252" ] ], "pkt6-received": [ [ 0, "2026-03-27 21:52:47.977252" ] ], "pkt6-release-received": [ [ 0, "2026-03-27 21:52:47.977253" ] ], "pkt6-renew-received": [ [ 0, "2026-03-27 21:52:47.977253" ] ], "pkt6-reply-received": [ [ 0, "2026-03-27 21:52:47.977255" ] ], "pkt6-reply-sent": [ [ 0, "2026-03-27 21:52:47.977255" ] ], "pkt6-request-received": [ [ 0, "2026-03-27 21:52:47.977255" ] ], "pkt6-sent": [ [ 0, "2026-03-27 21:52:47.977256" ] ], "pkt6-solicit-received": [ [ 0, "2026-03-27 21:52:47.977256" ] ], "pkt6-unknown-received": [ [ 0, "2026-03-27 21:52:47.977256" ] ], "reclaimed-declined-addresses": [ [ 0, "2026-03-27 21:52:47.992152" ] ], "reclaimed-leases": [ [ 0, "2026-03-27 21:52:47.992152" ] ], "subnet[1].assigned-nas": [ [ 2, "2026-03-27 21:52:47.992169" ], [ 0, "2026-03-27 21:52:47.992156" ] ], "subnet[1].assigned-pds": [ [ 0, "2026-03-27 21:52:47.992157" ] ], "subnet[1].cumulative-assigned-nas": [ [ 0, "2026-03-27 21:52:47.992009" ] ], "subnet[1].cumulative-assigned-pds": [ [ 0, "2026-03-27 21:52:47.992010" ] ], "subnet[1].cumulative-registered-nas": [ [ 0, "2026-03-27 21:52:47.992013" ] ], "subnet[1].declined-addresses": [ [ 0, "2026-03-27 21:52:47.992157" ] ], "subnet[1].pool[0].assigned-nas": [ [ 2, "2026-03-27 21:52:47.992205" ], [ 0, "2026-03-27 21:52:47.992163" ] ], "subnet[1].pool[0].cumulative-assigned-nas": [ [ 0, "2026-03-27 21:52:47.992017" ] ], "subnet[1].pool[0].declined-addresses": [ [ 0, "2026-03-27 21:52:47.992164" ] ], "subnet[1].pool[0].reclaimed-declined-addresses": [ [ 0, "2026-03-27 21:52:47.992165" ] ], "subnet[1].pool[0].reclaimed-leases": [ [ 0, "2026-03-27 21:52:47.992167" ] ], "subnet[1].pool[0].total-nas": [ [ 61440, "2026-03-27 21:52:47.992016" ] ], "subnet[1].reclaimed-declined-addresses": [ [ 0, "2026-03-27 21:52:47.992159" ] ], "subnet[1].reclaimed-leases": [ [ 0, "2026-03-27 21:52:47.992160" ] ], "subnet[1].registered-nas": [ [ 0, "2026-03-27 21:52:47.992161" ] ], "subnet[1].total-nas": [ [ 61440, "2026-03-27 21:52:47.992006" ] ], "subnet[1].total-pds": [ [ 0, "2026-03-27 21:52:47.992007" ] ], "subnet[1].v6-ia-na-lease-reuses": [ [ 0, "2026-03-27 21:52:47.992011" ] ], "subnet[1].v6-ia-pd-lease-reuses": [ [ 0, "2026-03-27 21:52:47.992012" ] ], "v6-allocation-fail": [ [ 0, "2026-03-27 21:52:47.977256" ] ], "v6-allocation-fail-classes": [ [ 0, "2026-03-27 21:52:47.977257" ] ], "v6-allocation-fail-no-pools": [ [ 0, "2026-03-27 21:52:47.977257" ] ], "v6-allocation-fail-shared-network": [ [ 0, "2026-03-27 21:52:47.977258" ] ], "v6-allocation-fail-subnet": [ [ 0, "2026-03-27 21:52:47.977259" ] ], "v6-ia-na-lease-reuses": [ [ 0, "2026-03-27 21:52:47.977259" ] ], "v6-ia-pd-lease-reuses": [ [ 0, "2026-03-27 21:52:47.977259" ] ] }, "result": 0 } ]
```

---

### Fetch Assigned NAs (Non-Temporary Addresses)

```bash
curl -s -X POST http://127.0.0.1:8001 \
  -H "Content-Type: application/json" \
  -d '{ "command": "statistic-get", "arguments": { "name": "cumulative-assigned-nas" } }'
```

**Sample output:**

```
[ { "arguments": { "cumulative-assigned-nas": [ [ 0, "2026-03-27 21:52:47.992153" ] ] }, "result": 0 } ]
```

---

### Fetch Assigned PDs (Prefix Delegations)

```bash
curl -s -X POST http://127.0.0.1:8001 \
  -H "Content-Type: application/json" \
  -d '{ "command": "statistic-get", "arguments": { "name": "cumulative-assigned-pds" } }'
```

**Sample output:**

```
[ { "arguments": { "cumulative-assigned-pds": [ [ 0, "2026-03-27 21:52:47.992153" ] ] }, "result": 0 } ]
```

---

### Per-Subnet Stats (DHCPv6)

```bash
curl -s -X POST http://127.0.0.1:8001 \
  -H "Content-Type: application/json" \
  -d '{ "command": "statistic-get", "arguments": { "name": "subnet[1].assigned-nas" } }'
```

**Sample output:**

```
[ { "arguments": { "subnet[1].assigned-nas": [ [ 2, "2026-03-27 21:52:47.992169" ], [ 0, "2026-03-27 21:52:47.992156" ] ] }, "result": 0 } ]
```

---

## Response Structure

All responses from Kea follow this envelope regardless of command:

```json
{
  "result": 0,
  "text": "...",
  "arguments": {
    ...
  }
}
```

The `result` field is the most important:

| Value | Meaning |
|-------|---------|
| `0` | Success |
| `1` | Error |
| `2` | Unsupported command |
| `3` | Empty result (no data matched) |

---

## Useful Stats Reference

### DHCPv4 Key Metrics

| Stat Name | Description |
|-----------|-------------|
| `pkt4-received` | Total DHCP packets received |
| `pkt4-discover-received` | DISCOVER packets received |
| `pkt4-offer-sent` | OFFER packets sent |
| `pkt4-request-received` | REQUEST packets received |
| `pkt4-ack-sent` | ACK packets sent |
| `cumulative-assigned-addresses` | Total addresses ever assigned |
| `declined-addresses` | Addresses marked declined |
| `subnet[N].assigned-addresses` | Active leases on subnet N |
| `subnet[N].total-addresses` | Pool size on subnet N |

### DHCPv6 Key Metrics

| Stat Name | Description |
|-----------|-------------|
| `pkt6-received` | Total DHCPv6 packets received |
| `pkt6-solicit-received` | Solicit packets received |
| `pkt6-advertise-sent` | Advertise packets sent |
| `pkt6-request-received` | REQUEST packets received |
| `pkt6-reply-sent` | Reply packets sent |
| `cumulative-assigned-nas` | Total NAs ever assigned |
| `cumulative-assigned-pds` | Total PDs ever assigned |
| `declined-addresses` | Addresses marked declined |
| `subnet[N].assigned-nas` | Active NA leases on subnet N |

---

## Unix Socket (Legacy)

The old Unix socket approach still works in 3.0 but is deprecated and will be removed in a future release. If you have an existing Unix socket config and need to query it in the interim:

```bash
echo '{ "command": "statistic-get-all", "arguments": {} }' | \
  socat - UNIX-CONNECT:/run/kea/kea4-ctrl-socket
```

Migrate to the `control-sockets` HTTP array as soon as practical.

---

## Adding TLS (Recommended for Non-Loopback)

If you expose the control channel beyond loopback, TLS with client certificates is strongly recommended over plain HTTP:

```json
"control-sockets": [
    {
        "socket-type": "https",
        "socket-address": "127.0.0.1",
        "socket-port": 8443,
        "trust-anchor": "/path/to/ca.pem",
        "cert-file": "/path/to/server-cert.pem",
        "key-file": "/path/to/server-key.pem",
        "cert-required": true
    }
]
```


---

## See Also

- [Kea ARM — Statistics](https://kea.readthedocs.io/en/latest/arm/stats.html)
- [Kea ARM — Management API](https://kea.readthedocs.io/en/latest/arm/ctrl-channel.html)
- [Kea ARM — Hook Libraries](https://kea.readthedocs.io/en/latest/arm/hooks.html)
