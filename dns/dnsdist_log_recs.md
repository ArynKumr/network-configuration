
# DNSDIST Log spam resolve
## Overview
This configuration provides:

* DNS interception using nftables
* dnsdist for forwarding, policy control, and load balancing
* Controlled logging suitable for production environments
* Stable upstream health monitoring
* Safe defaults for router/UTM deployments

---

## Design Goals

* Ensure **predictable and stable DNS behavior**
* Maintain **low-noise logging**
* Avoid unsafe or crash-prone configurations
* Support **scalable and maintainable** setups
* Provide clear **fallback mechanisms**

---

## Logging Configuration

```lua
setVerbose(true)
setVerboseHealthChecks(false)
```

### Behavior

* Enables meaningful operational logs
* Suppresses frequent health check messages
* Retains visibility into upstream state changes and errors

---

## Upstream Server Configuration

### Default Upstreams

```lua
newServer({
  address = "8.8.8.8:53",
  checkInterval = 5,
  maxCheckFailures = 3,
  rise = 2
})

newServer({
  address = "8.8.4.4:53",
  checkInterval = 5,
  maxCheckFailures = 3,
  rise = 2
})
```

### Parameters

* `checkInterval`: reduces probe frequency
* `maxCheckFailures`: avoids transient failures triggering state changes
* `rise`: stabilizes recovery from failure

---

## Dynamic (DB-Driven) Upstreams

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

### Requirements

* Validate all inputs before creating servers
* Ensure pools always contain at least one valid upstream
* Avoid duplicate or invalid entries

---

## Logging Strategy (Optional)

Avoid logging all queries. Instead, log selectively:

```lua
addAction(RCodeRule(DNSRCode.SERVFAIL), LogAction("DNS FAIL: ", false))
```

### Rationale

* Reduces I/O overhead
* Improves performance
* Focuses on actionable events

---

## Debugging Workflow

### Development / Testing

```bash
dnsdist -C /etc/dnsdist/dnsdist.conf
```

* Direct log output (stdout)
* Immediate visibility into errors
* No service restart loop

---

### Production Deployment

```bash
systemctl restart dnsdist
```

Ensure:

* Configuration is validated before deployment
* No runtime crashes (e.g., Lua issues)
* Upstreams are stable

---

## Validation Checklist

* dnsdist listening on intended interface (e.g., `10.10.10.1:53`)
* nftables redirect rules functioning
* Upstreams report `up` state
* No frequent health check state flapping
* DNS queries resolve correctly from clients
* Logs remain minimal and meaningful

---

## Expected Behavior

### Normal Operation

* Minimal log output
* Stable upstream state
* Consistent DNS resolution

### Degraded Conditions

* Clear upstream state changes
* Relevant error logging (timeouts, failures)
* No excessive log noise

---
