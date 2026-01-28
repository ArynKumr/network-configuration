* * *

Per-Client Static SNAT via nftables Maps (ISP-Aware)
====================================================

Purpose
-------

Provide **deterministic Source NAT** so that:

*   each internal client is translated to a **specific public IP**, and
*   that public IP **belongs to the same ISP** the client is **_routed_** through.

* * *

Core Configuration
------------------

### 1\. Define the SNAT Map

```
nft add map inet nat client_to_wan { type ipv4_addr : ipv4_addr; }
```

**Meaning:**

| Key | Value |
| --- | --- |
| Client private IP | ISP SNAT IP |

This is a **1 → 1 deterministic mapping**, not masquerade.

* * *

### 2\. Add Client → Public IP Binding

```
nft add element inet nat client_to_wan {
    <client_ip> : <isp_ip_from_isp_pool_map>
}
```

Example:

```
nft add element inet nat client_to_wan {
    192.168.10.50 : 10.1.1.1
}
```

That client will **always** exit using `10.1.1.1`.

* * *

### 3\. Apply SNAT Using the Map

```
nft insert rule inet nat postrouting snat to ip saddr map @client_to_wan
```

**What this does:**

*   looks up the **source IP** in the map
*   rewrites it to the mapped **public IP**
*   only applies when a match exists
*   unmapped users fall through to other NAT rules (e.g. masquerade)


> **A client SNATed to a public IP MUST be MARKED to be routed via the same ISP that owns that IP.**


Enforcing ISP Consistency (Design Rule)
---------------------------------------

### Assumption

You already use:

*   **nftables mangle marks**  
    `0x00<isp_id><tc_class>`
*   **ip rule** based routing per ISP

* * *

### Required Invariant

```
client ISP_ID == SNAT public IP ISP_ID
```

That means:

| Component | Must match |
| --- | --- |
| `user4_marks` ISP bits | ISP that owns SNAT IP |
| `ip rule fwmark` | Routing table of same ISP |
| `client_to_wan map value` | IP from same ISP pool |

* * *

Practical Enforcement Patterns
------------------------------

### Pattern 1: Operational Discipline (Minimum)

*   Maintain **separate IP pools per ISP**
*   Only insert SNAT mappings from the correct pool
*   Ensure provisioning logic checks ISP IDs

* * *

Interaction with Other NAT Rules
--------------------------------

Order matters.

**Correct order in `postrouting`:**

1.  **Client-specific SNAT (this map)**
2.  **Policy-based SNAT**
3.  **Masquerade (fallback)**

If masquerade runs first, this setup is useless.

* * *

When You SHOULD Use This
------------------------

Use this design for:

*   servers with fixed public identity
*   port-forwarded services
*   ISP-mandated static IP bindings
*   compliance / logging requirements
*   multi-ISP environments with strict routing

* * *

When You SHOULD NOT Use This
----------------------------

Do **not** use this for:

*   large user pools without automation
*   dynamic ISP failover (unless remapped)
*   unknown / transient devices

Masquerade is better there.

* * *

One-Line Summary
----------------

> This setup provides **per-client deterministic SNAT**, but it only works correctly if the **client’s routing ISP and SNAT IP belong to the same provider**