Bandwidth Quota Management using `tc` HTB Class Statistics
==========================================================

Context & Assumptions
---------------------

*   Each user is mapped to **one HTB class** (e.g. `1:10`) or a pool is assigned to multiple users
*   Traffic is already classified into this class using:
    *   `fwmark` (from nftables mangle)
    *   `tc filter fw`
*   **Quota enforcement is byte-based**, not time-based

### Interface Semantics (Important)

| Interface | What it Measures |
| --- | --- |
| WAN iface | **Upload quota** (user → internet) |
| LAN iface | **Download quota** (internet → user) |

* * *

Example Class Output (Parsed)
-----------------------------

```json
{
  "handle": "1:10",
  "parent": "1:1",
  "rate": 64000000,
  "ceil": 64000000,
  "stats": {
    "bytes": 656838230,
    "packets": 316289,
    "drops": 491,
    "overlimits": 118287
  }
}
```

### Key Field That Matters

```
stats.bytes
```

This is the **counter** for quota accounting.

Everything else is secondary.

* * *

What `stats.bytes` Represents
-----------------------------

*   Total bytes **successfully dequeued** from this class
*   Includes:
    *   TCP payload
    *   TCP/IP headers

This makes it **accurate for billing and quota enforcement**.

* * *

Quota Model
-----------

Each user/pool has:

| Attribute | Meaning |
| --- | --- |
| `download_quota_bytes` | Measured on LAN iface |
| `upload_quota_bytes` | Measured on WAN iface |
| `classid` | HTB class (e.g. `1:10`) |
| `fwmark` | Packet classifier |

Quota logic **must check both directions independently**.

* * *

Monitoring Logic (Control Plane)
--------------------------------

### Step 1 — Read Stats

```bash
tc -s -j class show dev <iface> | jq
```

Filter by:

```bash
.handle == "1:10"
```

Extract:

```bash
.stats.bytes
```

* * *

### Step 2 — Compare Against Quota

Example:

```text
User Download Quota: 500 MB
Current Usage:       656 MB
```

➡ **Quota exceeded**

* * *

Enforcement Strategies (Choose One)
-----------------------------------

### Option A — Throttle User (Soft Cap)

#### Action

1.  Delete existing class
2.  Recreate class with lower rate/ceil

```bash
tc filter delete dev <iface> protocol ip parent 1:0 prio 1 handle 0x0000<tc_class_marks>/0x0000FFFF fw flowid 1:10
tc class del dev <iface> classid 1:10
```

```bash
tc class add dev <iface> parent 1:1 classid 1:10 \
    htb rate 1mbit ceil 1mbit
```

*   Existing connections continue
*   User feels slowdown, not disconnect
*   Clean UX

* * *

### Option B — Hard Cut (Quota Exhausted)

#### Action

1.  Delete class
2.  Remove classifier
3.  Optionally remove nft rules

```bash
tc filter del dev <iface> parent 1:0 handle <mark>/0xFFFF fw
```

```bash
tc class del dev <iface> classid 1:10
```

Result:

*   Traffic falls into **default class**
*   Or is **fully blocked** (depending on firewall)

* * *

Directional Enforcement Rules
-----------------------------

### Download Quota (LAN iface)

*   Measure: `tc -s class show dev <lan_iface>`
*   Enforce:
    *   throttle LAN class
    *   or drop forward traffic

### Upload Quota (WAN iface)

*   Measure: `tc -s class show dev <wan_iface>`
*   Enforce:
    *   throttle WAN class

* * *

Common Failure Modes (Don’t Ignore)
-----------------------------------

### 1\. NATed traffic counted twice

Happens if you measure both LAN and WAN for same direction

Correct:

*   LAN = download only
*   WAN = upload only

* * *

### 2\. Deleting class without deleting filter

Packets get misclassified or fall through

Always verify:

```bash
tc filter show dev <iface>
```

* * *

### 3\. Per-packet quota logic

Wrong — TC is per-flow dequeuing

Quota checks must be **periodic**, not inline

* * *