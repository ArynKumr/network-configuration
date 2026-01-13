
Logging & Observability Documentation (nftables NGFW)
=====================================================

**Purpose:**  
Provide **controlled, opt-in visibility** into:

*   user traffic behavior
*   firewall decisions (accept / drop / redirect)
*   NAT activity
*   geofencing enforcement
*   packet marking (QoS / ISP routing)

Logging is **diagnostic**, not enforcement.  
Removing logging **must not change traffic behavior**.

* * *

Core Logging Design (Read This Once)
------------------------------------

### 1\. Logging is **opt-in**

Only users explicitly added to `log_users_*` sets are logged.

### 2\. Logging is **layered**

Each table logs **only what it owns**:

*   `filter` → security decisions
*   `nat` → address translation
*   `mangle` → packet marking
*   `webfilter` → inspection handoff
*   `geo` → border enforcement

### 3\. Logging never implies permission

A log entry does **not** mean traffic is allowed.

* * *

Logging Sets (WHO is Logged)
----------------------------

These sets exist **per table** because nftables tables are isolated.

* * *

### `log_users_v4` — IPv4 Watchlist

```
set log_users_v4 {
    type ipv4_addr
    flags interval
}
```

**Who belongs here:**

*   IPv4 users under investigation
*   Heavy bandwidth consumers
*   Suspicious or compromised hosts

**Why `interval`:**

*   Supports `/32`, subnets, and temporary bulk audits

* * *

### `log_users_v6` — IPv6 Watchlist

```
set log_users_v6 {
    type ipv6_addr
    flags interval
}
```

Same semantics as IPv4, **much higher log volume risk**.

* * *

### `log_users_mac` — Device-Level Watchlist

```
set log_users_mac {
    type ether_addr
}
```

**Use when:**

*   DHCP churn exists
*   IP spoofing suspected
*   Device identity matters more than IP

* * *

FILTER TABLE Logging (Security Decisions)
-----------------------------------------

### Location

`chain forward` — **LAN → WAN traffic**

This is the **most important logging surface**.

* * *

### `[FW-FILTER-FWD-IPMAC]`

```
ip saddr @log_users_v4 log prefix "[FW-FILTER-FWD-IPMAC] " level info
```

**Logged when:**

*   IPv4 source is watched
*   Before IP+MAC validation

**Meaning:**

> “This user attempted to forward traffic — about to be validated”

* * *

### `[FW-FILTER-FWD-IP6MAC]`

Same as above, IPv6.

* * *

### `[FW-FILTER-FWD-MACONLY]`

```
ether saddr @log_users_mac log prefix "[FW-FILTER-FWD-MACONLY] "
```

**Meaning:**

> “This hardware device is generating traffic (MAC-based audit)”

* * *

### `[FW-FILTER-FWD-IP4ONLY] ACCEPT`

```
ip saddr @log_users_v4 log prefix "[FW-FILTER-FWD-IP4ONLY] ACCEPT "
```

**Meaning:**

> “Traffic accepted via IPv4 whitelist (no MAC binding)”

* * *

### `[FW-FILTER-FWD-IP6ONLY] ACCEPT`

IPv6 equivalent.

* * *

### DROP LOGS (VERY IMPORTANT)

These log **final failure** before policy drop.

```
[FW-FILTER-FWD-DROP]
[FW-FILTER-FWD-DROP6]
[FW-FILTER-FWD-DROP-MAC]
```

**If you see these:**

*   User was watched
*   User matched no allow condition
*   Traffic died here

These are **gold for incident response**.

* * *

NAT TABLE Logging (Address Translation)
---------------------------------------

### Location

`chain postrouting` — **just before packets leave**

* * *

### `[FW-NAT-SNAT]`

```
oifname @wan_ifaces ip saddr @log_users_v4 log prefix "[FW-NAT-SNAT] "
```

**Meaning:**

> “This user is being NATed and sent to the internet”

**Use cases:**

*   Accounting
*   Traffic attribution
*   ISP disputes

* * *

WEBFILTER Logging (Inspection Visibility)
-----------------------------------------

### Location

`chain SYS_WEBFILTER` (prerouting)

* * *

### `[FW-WEBFILTER]`

```
log prefix "[FW-WEBFILTER] "
```

**Logged when:**

*   Watched user attempts web access
*   Before NFQUEUE handoff

**Meaning:**

> “This user’s web traffic hit the inspection layer”

This does **not** mean blocked or allowed — only observed.

* * *

GEO TABLE Logging (Border Enforcement)
--------------------------------------

### Inbound

```
[GEOFENCE-BLOCK-V4]
[GEOFENCE-BLOCK-V6]
```

**Meaning:**

> “Traffic from a blocked country was dropped at the border”

Happens **before NAT, mangle, filter**.

* * *

### Outbound

Same prefix, but triggered in `forward`.

**Meaning:**

> “Internal device attempted to reach a blocked country”

* * *

MANGLE TABLE — MARK LOGGING (NEW)
---------------------------------

Your current rules **mark packets correctly** but **do not log marks**.  
That’s intentional for performance — but debugging needs visibility.

### When to enable mark logging

*   QoS not applying
*   Wrong ISP routing
*   tc classes not incrementing

### When NOT to enable

*   Production peak hours
*   Large user sets

* * *

### Safe Mark Logging Rule (IPv4)

```
meta mark != 0 ip saddr @log_users_v4 \
    log prefix "[FW-MANGLE-MARK-V4] " level info
```

### IPv6

```
meta mark != 0 ip6 saddr @log_users_v6 \
    log prefix "[FW-MANGLE-MARK-V6] " level info
```

### MAC-based

```
meta mark != 0 ether saddr @log_users_mac \
    log prefix "[FW-MANGLE-MARK-MAC] " level info
```

**What this logs:**

*   The **final mark value**
*   After maps + conntrack persistence

**Where to place:**

*   End of `mangle prerouting` or `mangle forward`

* * *

### How to Read Mark Logs

Example:

```
FW-MANGLE-MARK-V4 ... mark=0x00ff0012
```

Interpretation:

*   `ff` → ISP ID
*   `0012` → TC class

If this is wrong → **routing + QoS are lying**

* * *
