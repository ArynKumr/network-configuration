
SNAT Policy Documentation (nftables)
====================================

This document describes **Source NAT (SNAT) using nftables maps**, covering:

*   **Case 1:** Complete traffic SNAT (user → single ISP IP)
*   **Case 2:** Destination-specific SNAT (user → ISP IP only for selected destinations)

It also explains the **routing and ISP-ID constraints** that **must** be respected for correctness.

* * *

Design Principles (Read First)
------------------------------

1.  **SNAT does NOT choose the route**
    *   Routing is decided **before** postrouting
    *   SNAT only rewrites the **source IP**
2.  **SNAT IP must belong to the egress ISP**
    *   Otherwise return traffic breaks
    *   Asymmetric routing = dropped replies
3.  **Maps are used for scale**
    *   No per-user rules
    *   O(1) lookup
    *   Safe for thousands of users

* * *

Case 1 — Complete Traffic SNAT (Per-User ISP Lock)
--------------------------------------------------

### Use Case

*   A user must **always appear from a specific ISP IP**
*   All destinations
*   All ports
*   All protocols
*   Typical for:
    *   static IP customers
    *   compliance routing
    *   ISP-locked users

* * *

### Configuration

#### 1\. Create the SNAT Map

```bash
nft add map inet nat client_to_wan '{
    type ipv4_addr : ipv4_addr;
}'
```

**Meaning:**

| Key | Value |
| --- | --- |
| Client IPv4 | ISP public IPv4 |

* * *

#### 2\. Add Mapping Entry

```bash
nft add element inet nat client_to_wan {
    <client_ip> : <isp_ip_from_isp_pool>
}
```

Example:

```
192.168.1.50 → 203.0.113.10
```

* * *

#### 3\. Apply SNAT Rule

```bash
nft insert rule inet nat postrouting \
    snat to ip saddr map @client_to_wan
```

* * *

### Mandatory Constraint (CRITICAL)

> **The user MUST be routed via the same ISP as the SNAT IP**

That means:

*   User’s `isp_id` in `mangle` **must match**
*   User’s routing table **must egress the same WAN**

If this is violated:

*   SYN goes out ISP-A
*   Reply comes back ISP-B
*   Connection breaks silently


* * *

### Behavior Summary (Case 1)

| Aspect | Result |
| --- | --- |
| Routing | Fixed to ISP |
| SNAT | Always applied |
| Destination awareness | None |
| ISP-ID dependency | **Required** |
| Safe for | Static users |

* * *

Case 2 — Destination-Specific SNAT (Selective ISP Identity)
-----------------------------------------------------------

### Use Case

*   User normally routes via one ISP
*   **Only specific destinations** can use a different ISP IP
*   Common for:
    *   banking sites
    *   geo-restricted services
    *   partner networks
    *   split-egress designs

* * *

### Configuration

#### 1\. Create the Destination-Aware Map

```bash
nft add map inet nat destination_to_wan '{
    type ipv4_addr . ipv4_addr : ipv4_addr;
}'
```

**Meaning:**

| Key | Value |
| --- | --- |
| Client IP + Destination IP | ISP public IP |

* * *

#### 2\. Add Mapping Entry

```bash
nft add element inet nat destination_to_wan {
    <client_ip_or_subnet> . <destination_ip_or_subnet> : <isp_ip>
}
```

Examples:

```
192.168.1.50 . 8.8.8.8     → 198.51.100.20
192.168.1.0/24 . 1.1.1.0/24 → 198.51.100.20
```

* * *

#### 3\. Apply SNAT Rule

```bash
nft insert rule inet nat postrouting \
    snat ip saddr . ip daddr map @destination_to_wan
```

* * *

### Routing Constraint (Different from Case 1)

> **User routing table does NOT need to match ISP of SNAT IP**

Why this works:

*   SNAT only triggers **when destination matches**
*   You intentionally override identity **only for that destination**
*   Other traffic remains untouched

However:

*   The destination **must be reachable via the ISP owning the SNAT IP**
*   Otherwise return traffic still breaks

* * *

### Behavior Summary (Case 2)

| Aspect | Result |
| --- | --- |
| Routing | User default |
| SNAT | Conditional |
| Destination awareness | **Yes** |
| ISP-ID dependency | **Not required** |
| Safe for | Split routing |

* * *

Comparison Table
----------------

| Feature | Case 1 | Case 2 |
| --- | --- | --- |
| Scope | All traffic | Destination-only |
| Map key | Client IP | Client IP + Destination |
| ISP-ID match required | **Yes** | No |
| Routing flexibility | None | High |
| Risk if misused | High | Medium |
| Typical use | Static IP | Selective egress |

* * *
