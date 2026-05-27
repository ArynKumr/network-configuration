# DNS Interception & Forwarding — Configuration Guide

## Overview
This configuration provides a foundation for reliable, low-noise DNS forwarding using **dnsdist** with **nftables** interception. It is designed to be deployment-agnostic and applicable to routers, UTM appliances, home labs, or cloud-hosted resolvers.

Optional enhancements for structured telemetry are described separately at the end.

---

## Design Goals

- Predictable and stable DNS behavior
- Low-noise, actionable logging
- Safe defaults suitable for production
- Scalable upstream management
- Clear fallback and recovery mechanisms

---

## Core Components

| Component | Role |
|---|---|
| nftables | Intercepts DNS traffic and redirects to dnsdist |
| dnsdist | Forwarding, policy control, load balancing |
| Upstream resolvers | Any standard DNS servers (public or private) |

---

## Logging Configuration

```lua
setVerbose(true)
setVerboseHealthChecks(false)
```

**Behavior:**
- Enables meaningful operational logs (startup, state changes, errors)
- Suppresses repetitive health check probe messages
- Surfaces actionable events without log noise

> **NOTE:** Disable if unrequired by setting both to `false`. By default both are `true`.

---

## Upstream Server Configuration

### Static Upstreams

```lua
newServer({
  address = "PRIMARY_DNS:53",
  source = wanName,
  reconnectOnUp = true,
  healthCheckMode = "lazy",
  checkInterval = 1,
  lazyHealthCheckFailedInterval = 5,
  rise = 2,
  maxCheckFailures = 1,
  lazyHealthCheckThreshold = 1,
  lazyHealthCheckSampleSize = 3,
  lazyHealthCheckMinSampleCount = 3,
  lazyHealthCheckMode = "TimeoutOrServFail"
})

newServer({
  address = "SECONDARY_DNS:53",
  source = wanName,
  reconnectOnUp = true,
  healthCheckMode = "lazy",
  checkInterval = 1,
  lazyHealthCheckFailedInterval = 5,
  rise = 2,
  maxCheckFailures = 1,
  lazyHealthCheckThreshold = 1,
  lazyHealthCheckSampleSize = 3,
  lazyHealthCheckMinSampleCount = 3,
  lazyHealthCheckMode = "TimeoutOrServFail"
})
```

Replace `PRIMARY_DNS` and `SECONDARY_DNS` with your resolvers (e.g., `8.8.8.8`, `1.1.1.1`, or internal forwarders).

**Parameter rationale:**

| Parameter | Purpose |
|---|---|
| `source` | Binds outbound health-check and query traffic to a specific interface or IP (e.g. the WAN interface), ensuring probes egress via the correct path |
| `reconnectOnUp` | Re-establishes the connection to an upstream as soon as it is marked healthy again, avoiding stale socket state after a recovery |
| `healthCheckMode` | Set to `"lazy"` to avoid constant active probing; health is instead inferred from real query traffic, reducing probe overhead |
| `checkInterval` | Interval in seconds between active health probes; lower values improve detection speed at the cost of more probe traffic |
| `lazyHealthCheckFailedInterval` | How frequently (in seconds) to re-probe an upstream that is already marked down under lazy mode |
| `rise` | Number of consecutive successful checks required before an upstream is promoted back to healthy; prevents flapping on marginal links |
| `maxCheckFailures` | Number of consecutive failures before an upstream is marked down; set to `1` for fast failure detection |
| `lazyHealthCheckThreshold` | Minimum failure rate (as a percentage) within the sample window before lazy health-checking is triggered |
| `lazyHealthCheckSampleSize` | Number of recent queries to include in the failure-rate calculation window |
| `lazyHealthCheckMinSampleCount` | Minimum number of samples required before the failure rate is evaluated; prevents premature state changes on low-traffic paths |
| `lazyHealthCheckMode` | Defines what counts as a failure for lazy health checking; `"TimeoutOrServFail"` triggers on both query timeouts and SERVFAIL responses |

### Dynamic (Runtime-Configured) Upstreams

```lua
if dns1 and dns1 ~= "" then
  newServer({
    address = dns1 .. ":53",
    pool = poolName,
    checkInterval = 5,
    maxCheckFailures = 3,
    rise = 2
  })
end
if dns2 and dns2 ~= "" then
  newServer({
    address = dns2 .. ":53",
    pool = poolName,
    checkInterval = 5,
    maxCheckFailures = 3,
    rise = 2
  })
end
```

**Requirements:**
- Validate all inputs before creating servers
- Ensure each pool contains at least one valid upstream
- Avoid duplicate or empty entries

---

## Logging Strategy

Log errors directly in dnsdist; delegate full query telemetry to an external collector (see Optional Enhancements):

```lua
addAction(RCodeRule(DNSRCode.SERVFAIL), LogAction("DNS FAIL: ", false))
```

This surfaces actionable failures in the system journal while keeping I/O overhead minimal on the DNS path itself.

---

## Deployment

### Development / Testing

```bash
dnsdist -C /path/to/dnsdist.conf
```

- Outputs logs directly to stdout
- Immediate visibility into errors
- No service restart loop

### Production

```bash
systemctl restart dnsdist
```

Ensure before deployment:
- Configuration is validated (no Lua syntax errors)
- Upstreams are reachable
- dnsdist is listening on the intended interface and port
- nftables redirect rules are active

---

## Validation Checklist

- dnsdist is listening on the intended address (e.g., `127.0.0.1:53` or `10.0.0.1:53`)
- nftables redirect rules are functioning
- All configured upstreams report `up` state
- No frequent upstream state flapping
- DNS queries resolve correctly from clients
- System logs are minimal and actionable

---

## Expected Behavior

**Normal operation:**
- Minimal log output (startup and upstream state changes only)
- Stable upstream state
- Consistent DNS resolution for clients

**Degraded conditions:**
- Clear upstream state change messages in logs
- SERVFAIL errors surfaced in the system journal
- No excessive log noise
- DNS resolution continues via remaining healthy upstreams

---

---

# Optional Enhancement: Structured DNS Telemetry via go-dnscollector

> **This section is optional.** The core dnsdist setup above is fully functional without it. The following adds full per-query telemetry, useful for forensics, dashboards, compliance logging, or capacity planning — without burdening dnsdist's own logging path.

[go-dnscollector](https://github.com/dmachard/go-dnscollector) is a high-performance DNS traffic collector. It integrates with dnsdist via a Unix socket or TCP, offloading all query logging from dnsdist itself, keeping the resolver lean while providing structured, filterable DNS telemetry.

---

## Architecture

```
Client → nftables → dnsdist → Upstream resolvers
                       │
                  [DNSTap / protobuf stream]
                       ↓
               go-dnscollector
                       │
          ┌────────────┼────────────┐
          ↓            ↓            ↓
       stdout       JSON file    Loki /
      (dev)         (prod)     Prometheus
```

dnsdist emits DNSTap messages over a local socket. go-dnscollector receives and decodes them, routing to any combination of outputs.

---

## dnsdist Side — Enable DNSTap Output

Add to `dnsdist.conf`:

```lua
-- Non-blocking: collector unavailability will not stall dnsdist.
local fslu = newFrameStreamUnixLogger("/var/run/dnscollector/dnsdist.sock")

addAction(AllRule(), DnstapLogAction("dnsdist", fslu))
addResponseAction(AllRule(), DnstapLogResponseAction("dnsdist", fslu))
```

### Unix Socket vs TCP

| Factor | Unix Socket | TCP |
|---|---|---|
| Latency | Lower (no TCP stack) | Slightly higher |
| Reliability | Process-local | Network-dependent |
| Config complexity | Minimal | Requires port/firewall config |

Unix socket is the recommended default when dnsdist and go-dnscollector run on the same host.

---

## go-dnscollector Side — Minimal Config

`/etc/go-dnscollector/config.yml`:

```yaml
global:
  trace:
    verbose: false

pipelines:
  - name: dnsdist-input
    dnstap-relay:
      listen-ip: "unix"
      listen-port: 0
      sock-path: /var/run/dnscollector/dnsdist.sock

  - name: log-output
    logfile:
      file-path: /var/log/dnscollector/queries.log
      max-size: 100        # MB before rotation
      max-backups: 5
      mode: json           # use "text" for human-readable output

routes:
  - from: [ dnsdist-input ]
    to:   [ log-output ]
```

JSON mode produces one DNS event per line, suitable for ingestion by Loki, Elasticsearch, or similar shippers.

---

## Socket Directory Setup

```bash
mkdir -p /var/run/dnscollector
chown dnsdist:dnscollector /var/run/dnscollector
chmod 770 /var/run/dnscollector
```

Both `dnsdist` and `go-dnscollector` must have access to the socket path. Adjust group ownership to match your system users.

---

## Selective Logging (Noise Reduction)

Filter by record type or response code before writing to disk:

```yaml
pipelines:
  - name: log-output
    logfile:
      file-path: /var/log/dnscollector/queries.log
      mode: json
      directives:
        - match:
            qtype: [ "A", "AAAA", "MX" ]
        - match:
            rcode: [ "SERVFAIL", "NXDOMAIN" ]
```

This complements the dnsdist-side `LogAction` on SERVFAILs — dnsdist logs errors directly to the journal; go-dnscollector handles the full query stream independently.

---

## Systemd Startup Order

go-dnscollector must be running before dnsdist connects to the socket:

```ini
# /etc/systemd/system/dnsdist.service.d/override.conf
[Unit]
After=go-dnscollector.service
Wants=go-dnscollector.service
```

dnsdist will reconnect automatically if the collector restarts. The non-blocking `FrameStreamUnixLogger` ensures DNS resolution is never stalled by collector unavailability.

---

## Production Startup (with Telemetry)

```bash
systemctl restart go-dnscollector   # start collector first
systemctl restart dnsdist
```

---

## Logging Summary (with Telemetry Enabled)

| Source | What it captures | Destination |
|---|---|---|
| `setVerbose(true)` | Startup, upstream state changes | systemd journal |
| `LogAction` on SERVFAIL | Error-level DNS failures | systemd journal |
| `DnstapLogAction` (all queries) | Full query/response stream | go-dnscollector → file / Loki |
| `setVerboseHealthChecks(false)` | Health probe chatter | (suppressed) |

---

## Debugging go-dnscollector

```bash
# Verify the socket exists and is accessible
ls -la /var/run/dnscollector/

# Run the collector in foreground with verbose output
go-dnscollector -config /etc/go-dnscollector/config.yml -v

# Confirm dnsdist is writing to the tap
tail -f /var/log/dnscollector/queries.log
```
