NGFW Truth Table (Case Definitions)
==========================================

**Purpose:**  
Define **authoritative traffic-matching semantics** for NGFW user policies.

Every case implemented in nftables **must correspond to one column in this table**.  

* * *

Matching Truth Table
---------------------------

| Field | Source IP | Source Port | Destination IP | Destination Port | Protocol | Action |
| --- | --- | --- | --- | --- | --- | --- |
| Case 1 | Specific | ALL | ALL | ALL | ALL | allow / drop |
| Case 2 | Specific | Specific | Specific | Specific | tcp/udp | allow / drop |
| Case 3 | Specific | ALL | Specific | ALL | ALL | allow / drop |
| Case 4 | Specific | ALL | Specific | Specific | tcp/udp | allow / drop |
| Case 5 | Specific | Specific | ALL | Specific | tcp/udp | allow / drop |
| Case 6 | Specific | Specific | ALL | ALL | tcp/udp | allow / drop |
| Case 7 | Specific | ALL | ALL | Specific | tcp/udp | allow / drop |
| Case 8 | Specific | Specific | Specific | ALL | tcp/udp | allow / drop |

* * *

How to Read This Table (Non-Negotiable)
---------------------------------------

*   **“Specific”** means _explicitly matched_ in nftables  
    (`ip saddr`, `tcp dport`, maps, sets, etc.)
*   **“Any”** means _no match condition applied_  
    (field is intentionally ignored)
*   **Action** is the **verdict** applied _after_ matching
*   All cases assume **default drop outside the match**

* * *

Case Semantics (Authoritative Definitions)
------------------------------------------

### Case 1 — Identity-Only Policy

**(Source IP only)**

*   Matches only on **who** the user is
*   No port, protocol, or destination restriction
*   Used for:
    *   trusted users
    *   admin bypass

**This is the highest-risk case.**
```
nft insert rule inet filter FILTER_FORWARD ip saddr <user_ips/user_subnet> <action>
nft insert rule inet filter FILTER_FORWARD ip daddr <user_ips/user_subnet> <action>

nft insert rule inet nat NAT_PRE ip saddr <user_ips/user_subnet> <action>
nft insert rule inet nat NAT_PRE ip daddr <user_ips/user_subnet> <action>

nft insert rule inet nat NAT_POST oifname @wan_ifaces ip saddr <user_ips/user_subnet> masquerade

nft add rule inet mangle prerouting ip saddr <user_ips/user_subnet> meta mark set 0x00<isp_id><tc_class_id>
nft add rule inet mangle forward ip daddr <user_ips/user_subnet> meta mark set 0x00<isp_id><tc_class_id>
```
***
OR (for specific protocol)
--
**(Source IP and protocol only)**

*   Matches only on **who** the user is
*   No port, protocol, or destination restriction
*   Used for:
    *   trusted users
    *   admin bypass

**This is the highest-risk case.**
```
nft insert rule inet filter FILTER_FORWARD ip saddr <user_ips/user_subnet> <action>
nft insert rule inet filter FILTER_FORWARD ip daddr <user_ips/user_subnet> <action>

nft insert rule inet nat NAT_PRE ip saddr <user_ips/user_subnet> ip protocol <protocol> <action>
nft insert rule inet nat NAT_PRE ip daddr <user_ips/user_subnet> ip protocol <protocol> <action>

nft insert rule inet nat NAT_POST oifname @wan_ifaces ip saddr <user_ips/user_subnet> masquerade

nft add rule inet mangle prerouting ip saddr <user_ips/user_subnet> meta mark set 0x00<isp_id><tc_class_id>
nft add rule inet mangle forward ip daddr <user_ips/user_subnet> meta mark set 0x00<isp_id><tc_class_id>
```
* * *

### Case 2 — Full 5-Tuple Policy

**(Source IP + Source Port + Destination IP + Destination Port)**

*   Most restrictive possible match
*   Ideal for:
    *   database access
    *   SSH jump hosts
    *   API consumers


* * *
```
nft insert rule inet filter FILTER_FORWARD ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> <protocol> sport <source_port> <action>
nft insert rule inet filter FILTER_FORWARD ip daddr <user_ips/user_subnet> ip saddr <destination_ip/destination_subnet> <protocol> dport <destination_port> <action>

nft insert rule inet nat NAT_PRE ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> <protocol> sport <source_port> <action>
nft insert rule inet nat NAT_PRE ip daddr <user_ips/user_subnet> ip saddr <destination_ip/destination_subnet> <protocol> dport <destination_port> <action>

nft insert rule inet nat NAT_POST oifname @wan_ifaces ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> <protocol> dport <destination_port> masquerade

nft add rule inet mangle prerouting ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> <protocol> sport <source_port> meta mark set 0x00<isp_id><tc_class_id>
nft add rule inet mangle forward ip daddr <user_ips/user_subnet> ip saddr <destination_ip/destination_subnet> <protocol> dport <destination_port> meta mark set 0x00<isp_id><tc_class_id>
```

### Case 3 — Destination IP Policy

**(Source IP → Destination IP)**

*   Ignores ports entirely
*   Allows all services **to one destination only**
*   Common for:
    *   site-to-site links
    *   fixed backend services

* * *
```
nft insert rule inet filter FILTER_FORWARD ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> <action>
nft insert rule inet filter FILTER_FORWARD ip daddr <user_ips/user_subnet> ip saddr <destination_ip/destination_subnet> <action>

nft insert rule inet nat NAT_PRE ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> <action>
nft insert rule inet nat NAT_PRE ip daddr <user_ips/user_subnet> ip saddr <destination_ip/destination_subnet> <action>

nft insert rule inet nat NAT_POST oifname @wan_ifaces ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> masquerade

nft add rule inet mangle prerouting ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> meta mark set 0x00<isp_id><tc_class_id>
nft add rule inet mangle forward ip daddr <user_ips/user_subnet> ip saddr <destination_ip/destination_subnet> meta mark set 0x00<isp_id><tc_class_id>
```
***
OR (for specific protocol)
--
**(Source IP specific protocol → Destination IP specific protocol)**

*   Ignores ports entirely
*   Allows all services **to one destination and specific protocol only**
*   Common for:
    *   site-to-site links
    *   fixed backend services

* * *
```
nft insert rule inet filter FILTER_FORWARD ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> ip protocol <protocol> <action>
nft insert rule inet filter FILTER_FORWARD ip daddr <user_ips/user_subnet> ip saddr <destination_ip/destination_subnet> ip protocol <protocol> <action>

nft insert rule inet nat NAT_PRE ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> <action>
nft insert rule inet nat NAT_PRE ip daddr <user_ips/user_subnet> ip saddr <destination_ip/destination_subnet> <action>

nft insert rule inet nat NAT_POST oifname @wan_ifaces ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> masquerade

nft add rule inet mangle prerouting ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> meta mark set 0x00<isp_id><tc_class_id>
nft add rule inet mangle forward ip daddr <user_ips/user_subnet> ip saddr <destination_ip/destination_subnet> meta mark set 0x00<isp_id><tc_class_id>
```

### Case 4 — Destination IP + Port Policy

**(Source IP → Destination IP:Port)**

*   Service-specific access to a single host
*   Safer than Case 3
*   Typical for:
    *   HTTPS-only access
    *   single exposed service

* * *
```
nft insert rule inet filter FILTER_FORWARD ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> <action>
nft insert rule inet filter FILTER_FORWARD ip daddr <user_ips/user_subnet> ip saddr <destination_ip/destination_subnet> <protocol> dport <destination_port> <action>

nft insert rule inet nat NAT_PRE ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> <action>
nft insert rule inet nat NAT_PRE ip daddr <user_ips/user_subnet> ip saddr <destination_ip/destination_subnet> <protocol> dport <destination_port>  <action>

nft insert rule inet nat NAT_POST oifname @wan_ifaces ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> <protocol> dport <destination_port>  masquerade

nft add rule inet mangle prerouting ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> meta mark set 0x00<isp_id><tc_class_id>
nft add rule inet mangle forward ip daddr <user_ips/user_subnet> ip saddr <destination_ip/destination_subnet> <protocol> dport <destination_port> meta mark set 0x00<isp_id><tc_class_id>
```

### Case 5 — Port-Constrained Egress

**(Source IP + Source Port → Any Destination: Specific Port)**

*   Rare, but valid
*   Used when **client-side port identity matters**
*   Example:
    *   pinned application ports
    *   legacy systems

* * *
```
nft insert rule inet filter FILTER_FORWARD ip saddr <user_ips/user_subnet> <protocol> dport <destination_port> <protocol> sport <source_port> <action>
nft insert rule inet filter FILTER_FORWARD ip daddr <user_ips/user_subnet> <protocol> sport <source_port> <protocol> dport <destination_port> <action>

nft insert rule inet nat NAT_PRE ip saddr <user_ips/user_subnet> <protocol> dport <destination_port> <protocol> sport <source_port> <action>
nft insert rule inet nat NAT_PRE ip daddr <user_ips/user_subnet> <protocol> sport <source_port> <protocol> dport <destination_port> <action>

nft insert rule inet nat NAT_POST oifname @wan_ifaces ip saddr <user_ips/user_subnet> <protocol> dport <destination_port> <protocol> sport <source_port> masquerade

nft add rule inet mangle prerouting ip saddr <user_ips/user_subnet> <protocol> dport <destination_port> <protocol> sport <source_port> meta mark set 0x00<isp_id><tc_class_id>
nft add rule inet mangle forward ip daddr <user_ips/user_subnet> <protocol> sport <source_port> <protocol> dport <destination_port> meta mark set 0x00<isp_id><tc_class_id>
```

### Case 6 — Source-Port Anchored Policy

**(Source IP + Source Port → Any Destination)**


* * *
```
nft insert rule inet filter FILTER_FORWARD ip saddr <user_ips/user_subnet> <protocol> sport <source_port> <action>
nft insert rule inet filter FILTER_FORWARD ip daddr <user_ips/user_subnet> <action>

nft insert rule inet nat NAT_PRE ip saddr <user_ips/user_subnet> <protocol> sport <source_port> <action>
nft insert rule inet nat NAT_PRE ip daddr <user_ips/user_subnet> <action>

nft insert rule inet nat NAT_POST oifname @wan_ifaces ip saddr <user_ips/user_subnet> <protocol> sport <source_port> masquerade

nft add rule inet mangle prerouting ip saddr <user_ips/user_subnet> <protocol> sport <source_port> meta mark set 0x00<isp_id><tc_class_id>
nft add rule inet mangle forward ip daddr <user_ips/user_subnet> meta mark set 0x00<isp_id><tc_class_id>
```

### Case 7 — Destination Port Policy

**(Source IP → Any Destination: Specific Port)**

* * *
```
nft insert rule inet filter FILTER_FORWARD ip daddr <user_ips/user_subnet> <protocol> dport <destination_port> <action>
nft insert rule inet filter FILTER_FORWARD ip saddr <user_ips/user_subnet> <action>

nft insert rule inet nat NAT_PRE ip daddr <user_ips/user_subnet> <protocol> dport <destination_port> <action>
nft insert rule inet nat NAT_PRE ip saddr <user_ips/user_subnet> <action>

nft insert rule inet nat NAT_POST oifname @wan_ifaces ip saddr <user_ips/user_subnet> <protocol> dport <destination_port> masquerade

nft add rule inet mangle prerouting ip saddr <user_ips/user_subnet> meta mark set 0x00<isp_id><tc_class_id>
nft add rule inet mangle forward ip daddr <user_ips/user_subnet> <protocol> dport <destination_port> meta mark set 0x00<isp_id><tc_class_id>
```

### Case 8 — Destination IP with Source Port

**(Source IP:Port → Destination IP)**

* * *
```
nft insert rule inet filter FILTER_FORWARD ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> <protocol> sport <source_port> <action>
nft insert rule inet filter FILTER_FORWARD ip daddr <user_ips/user_subnet> ip saddr <destination_ip/destination_subnet> <action>

nft insert rule inet nat NAT_PRE ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> <protocol> sport <source_port> <action>
nft insert rule inet nat NAT_PRE ip daddr <user_ips/user_subnet> ip saddr <destination_ip/destination_subnet> <action>

nft insert rule inet nat NAT_POST oifname @wan_ifaces ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> <protocol> sport <source_port> masquerade

nft add rule inet mangle prerouting ip saddr <user_ips/user_subnet> ip daddr <destination_ip/destination_subnet> <protocol> sport <source_port> meta mark set 0x00<isp_id><tc_class_id>
nft add rule inet mangle forward ip daddr <user_ips/user_subnet> ip saddr <destination_ip/destination_subnet> meta mark set 0x00<isp_id><tc_class_id>
```

Enforcement Rules (Critical)
----------------------------

These rules apply to **all cases**:

1.  **Source IP is always specific**  
2.  **Protocol must be explicit (tcp/udp)**  
3.  **Unmatched traffic must hit default drop**  
4.  **Bidirectional rules are mandatory**  

* * *

Mapping This Table to nftables
------------------------------

*   **Specific fields** → `ip saddr`, `ip daddr`, `tcp dport`, `udp sport`, `maps`, `sets`
*   **Any fields** → field omitted entirely
*   **Action** → `accept` or implicit `drop`
*   **Cases** → implemented via:
    *   chains (what)
    *   jumps (when)
 
All future case documentation **must reference the case number from here**.