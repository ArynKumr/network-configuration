NGFW Policy Truth Table (Case Definitions)
==========================================

**Purpose:**  
Define **authoritative traffic-matching semantics** for NGFW user policies.

Every policy case implemented in nftables **must correspond to one column in this table**.  

* * *

Policy Matching Truth Table
---------------------------

| Field | Case 1 | Case 2 | Case 3 | Case 4 | Case 5 | Case 6 | Case 7 | Case 8 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Source IP | Specific | Specific | Specific | Specific | Specific | Specific | Specific | Specific |
| Source Port | Any | Specific | Any | Any | Specific | Specific | Any | Specific |
| Destination IP | Any | Specific | Specific | Specific | Any | Any | Any | Specific |
| Destination Port | Any | Specific | Any | Specific | Specific | Any | Specific | Any |
| Protocol | tcp/udp | tcp/udp | tcp/udp | tcp/udp | tcp/udp | tcp/udp | tcp/udp | tcp/udp |
| Action | allow / drop | allow / drop | allow / drop | allow / drop | allow / drop | allow / drop | allow / drop | allow / drop |

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
nft add set inet filter <policy_users_set> '{ type ipv4_addr; flags interval; }'
nft add set inet nat <policy_users_set> '{ type ipv4_addr; flags interval; }'

nft add chain inet filter <POLICY_NAME>
nft add chain inet nat PRE_NAT_<POLICY_NAME>
nft add chain inet nat POST_NAT_<POLICY_NAME>

nft insert rule inet filter forward ip saddr @<policy_users_set> jump <POLICY_NAME>
nft insert rule inet filter forward ip daddr @<policy_users_set> jump <POLICY_NAME>

nft insert rule inet nat prerouting ip saddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>
nft insert rule inet nat prerouting ip daddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>

nft insert rule inet nat postrouting oifname @wan_ifaces ip saddr @<policy_users_set> jump POST_NAT_<POLICY_NAME>

nft add rule inet filter <POLICY_NAME> <action>

nft add rule inet nat PRE_NAT_<POLICY_NAME> <action>

nft add rule inet nat POST_NAT_<POLICY_NAME> masquerade

nft add element inet mangle user4_marks { <policy_users_ip> : 0x00<isp_id><tc_class_id>}

nft add element inet filter <policy_users_set> { <policy_users_ip> }
nft add element inet nat <policy_users_set> { <policy_users_ip> }
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
nft add set inet filter <policy_users_set> '{ type ipv4_addr; flags interval; }'
nft add set inet nat <policy_users_set> '{ type ipv4_addr; flags interval; }'

nft add chain inet filter <POLICY_NAME>
nft add chain inet nat PRE_NAT_<POLICY_NAME>
nft add chain inet nat POST_NAT_<POLICY_NAME>

nft insert rule inet filter forward ip saddr @<policy_users_set> jump <POLICY_NAME>
nft insert rule inet filter forward ip daddr @<policy_users_set> jump <POLICY_NAME>

nft insert rule inet nat prerouting ip saddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>
nft insert rule inet nat prerouting ip daddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>

nft insert rule inet nat postrouting oifname @wan_ifaces ip saddr @<policy_users_set> jump POST_NAT_<POLICY_NAME>

nft add rule inet filter <POLICY_NAME> ip daddr <destination_ip> <protocol> sport <source_port> <action>
nft add rule inet filter <POLICY_NAME> ip saddr <destination_ip> <protocol> dport <destination_port> <action>
nft add rule inet filter <POLICY_NAME> return

nft add rule inet nat PRE_NAT_<POLICY_NAME> ip saddr <destination_ip> <protocol> dport <destination_port> <action>
nft add rule inet nat PRE_NAT_<POLICY_NAME> ip daddr <destination_ip> <protocol> sport <source_port> <action>
nft add rule inet nat PRE_NAT_<POLICY_NAME> return

nft add rule inet nat POST_NAT_<POLICY_NAME> ip daddr <destination_ip> <protocol> dport <destination_port> masquerade
nft add rule inet nat POST_NAT_<POLICY_NAME> return

nft add element inet mangle user4_marks { <policy_users_ip> : 0x00<isp_id><tc_class_id>}

nft add element inet filter <policy_users_set> { <policy_users_ip> }
nft add element inet nat <policy_users_set> { <policy_users_ip> }
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
nft add set inet filter <policy_users_set> { type ipv4_addr; flags interval; }
nft add set inet nat <policy_users_set> { type ipv4_addr; flags interval; }

nft add chain inet filter <POLICY_NAME>
nft add chain inet nat PRE_NAT_<POLICY_NAME>
nft add chain inet nat POST_NAT_<POLICY_NAME>

nft insert rule inet filter forward ip saddr @<policy_users_set> jump <POLICY_NAME>
nft insert rule inet filter forward ip daddr @<policy_users_set> jump <POLICY_NAME>

nft insert rule inet nat prerouting ip saddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>
nft insert rule inet nat prerouting ip daddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>

nft insert rule inet nat postrouting oifname @wan_ifaces ip saddr @<policy_users_set> jump POST_NAT_<POLICY_NAME>

nft add rule inet filter <POLICY_NAME> ip daddr <destination_ip> <action>
nft add rule inet filter <POLICY_NAME> ip saddr <destination_ip> <action>
nft add rule inet filter <POLICY_NAME> return

nft add rule inet nat PRE_NAT_<POLICY_NAME> ip saddr <destination_ip> <action>
nft add rule inet nat PRE_NAT_<POLICY_NAME> ip daddr <destination_ip> <action>
nft add rule inet nat PRE_NAT_<POLICY_NAME> return

nft add rule inet nat POST_NAT_<POLICY_NAME> ip daddr <destination_ip> masquerade
nft add rule inet nat POST_NAT_<POLICY_NAME> return
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
nft add set inet filter <policy_users_set> '{ type ipv4_addr; flags interval; }'
nft add set inet nat <policy_users_set> '{ type ipv4_addr; flags interval; }'

nft add chain inet filter <POLICY_NAME>
nft add chain inet nat PRE_NAT_<POLICY_NAME>
nft add chain inet nat POST_NAT_<POLICY_NAME>

nft insert rule inet filter forward ip saddr @<policy_users_set> jump <POLICY_NAME>
nft insert rule inet filter forward ip daddr @<policy_users_set> jump <POLICY_NAME>

nft insert rule inet nat postrouting oifname @wan_ifaces ip saddr @<policy_users_set> jump POST_NAT_<POLICY_NAME>

nft add rule inet filter <POLICY_NAME> ip daddr <destination_ip> <action>
nft add rule inet filter <POLICY_NAME> ip saddr <destination_ip> <protocol> dport <destination_port>  <action>
nft add rule inet filter <POLICY_NAME> return

nft add rule inet nat PRE_NAT_<POLICY_NAME> ip saddr <destination_ip> <protocol> dport <destination_port>  <action>
nft add rule inet nat PRE_NAT_<POLICY_NAME> ip daddr <destination_ip> <action>
nft add rule inet nat PRE_NAT_<POLICY_NAME> return

nft add rule inet nat POST_NAT_<POLICY_NAME> ip daddr <destination_ip> <protocol> dport <destination_port>  masquerade
nft add rule inet nat POST_NAT_<POLICY_NAME> return

nft add element inet mangle user4_marks { <policy_users_ip> : 0x00<isp_id><tc_class_id> }

nft add element inet filter <policy_users_set> { <policy_users_ip> }
nft add element inet nat <policy_users_set> { <policy_users_ip> }
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
nft add set inet filter <policy_users_set> '{ type ipv4_addr; flags interval; }'
nft add set inet nat <policy_users_set> '{ type ipv4_addr; flags interval; }'

nft add chain inet filter <POLICY_NAME>
nft add chain inet nat PRE_NAT_<POLICY_NAME>
nft add chain inet nat POST_NAT_<POLICY_NAME>

nft insert rule inet filter forward ip saddr @<policy_users_set> jump <POLICY_NAME>
nft insert rule inet filter forward ip daddr @<policy_users_set> jump <POLICY_NAME>

nft insert rule inet nat prerouting ip saddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>
nft insert rule inet nat prerouting ip daddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>

nft insert rule inet nat postrouting oifname @wan_ifaces ip saddr @<policy_users_set> jump POST_NAT_<POLICY_NAME>

nft add rule inet filter <POLICY_NAME> <protocol> dport <destination_port> <protocol> sport <source_port> <action>
nft add rule inet filter <POLICY_NAME> return

nft add rule inet nat PRE_NAT_<POLICY_NAME> <protocol> dport <destination_port> <protocol> sport <source_port> <action>
nft add rule inet nat PRE_NAT_<POLICY_NAME> return

nft add rule inet nat POST_NAT_<POLICY_NAME> <protocol> dport <destination_port> <protocol> sport <source_port> masquerade
nft add rule inet nat POST_NAT_<POLICY_NAME> return

nft add element inet mangle user4_marks { <policy_users_ip> : 0x00<isp_id><tc_class_id> }

nft add element inet filter <policy_users_set> { <policy_users_ip> }
nft add element inet nat <policy_users_set> { <policy_users_ip> }
```

### Case 6 — Source-Port Anchored Policy

**(Source IP + Source Port → Any Destination)**


* * *
```
nft add set inet filter <policy_users_set> '{ type ipv4_addr; flags interval; }'
nft add set inet nat <policy_users_set> '{ type ipv4_addr; flags interval; }'

nft add chain inet filter <POLICY_NAME>
nft add chain inet nat PRE_NAT_<POLICY_NAME>
nft add chain inet nat POST_NAT_<POLICY_NAME>

nft insert rule inet filter forward ip saddr @<policy_users_set> jump <POLICY_NAME>
nft insert rule inet filter forward ip daddr @<policy_users_set> <action>

nft insert rule inet nat prerouting ip saddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>
nft insert rule inet nat prerouting ip daddr @<policy_users_set> <action>

nft insert rule inet nat postrouting oifname @wan_ifaces ip saddr @<policy_users_set> jump POST_NAT_<POLICY_NAME>

nft add rule inet filter <POLICY_NAME> <protocol> sport <source_port> <action>
nft add rule inet filter <POLICY_NAME> return

nft add rule inet nat PRE_NAT_<POLICY_NAME> <protocol> sport <source_port> <action>
nft add rule inet nat PRE_NAT_<POLICY_NAME> return

nft add rule inet nat POST_NAT_<POLICY_NAME> <protocol> sport <source_port> masquerade
nft add rule inet nat POST_NAT_<POLICY_NAME> return

nft add element inet mangle user4_marks { <policy_users_ip> : 0x00<isp_id><tc_class_id> }

nft add element inet filter <policy_users_set> { <policy_users_ip> }
nft add element inet nat <policy_users_set> { <policy_users_ip> }
```

### Case 7 — Destination Port Policy

**(Source IP → Any Destination: Specific Port)**

* * *
```
nft add set inet filter <policy_users_set> '{ type ipv4_addr; flags interval; }'
nft add set inet nat <policy_users_set> '{ type ipv4_addr; flags interval; }'

nft add chain inet filter <POLICY_NAME>
nft add chain inet nat PRE_NAT_<POLICY_NAME>
nft add chain inet nat POST_NAT_<POLICY_NAME>

nft insert rule inet filter forward ip daddr @<policy_users_set> jump <POLICY_NAME>
nft insert rule inet filter forward ip saddr @<policy_users_set> <action>

nft insert rule inet nat prerouting ip daddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>
nft insert rule inet nat prerouting ip saddr @<policy_users_set> <action>

nft insert rule inet nat postrouting oifname @wan_ifaces ip saddr @<policy_users_set> jump POST_NAT_<POLICY_NAME>

nft add rule inet filter <POLICY_NAME> <protocol> dport <destination_port> <action>
nft add rule inet filter <POLICY_NAME> return

nft add rule inet nat PRE_NAT_<POLICY_NAME> <protocol> dport <destination_port> <action>
nft add rule inet nat PRE_NAT_<POLICY_NAME> return

nft add rule inet nat POST_NAT_<POLICY_NAME> <protocol> dport <destination_port> masquerade
nft add rule inet nat POST_NAT_<POLICY_NAME> return

nft add element inet mangle user4_marks { <policy_users_ip> : 0x00<isp_id><tc_class_id> }

nft add element inet filter <policy_users_set> { <policy_users_ip> }
nft add element inet nat <policy_users_set> { <policy_users_ip> }
```

### Case 8 — Destination IP with Source Port

**(Source IP:Port → Destination IP)**

* * *
```
nft add set inet filter <policy_users_set> '{ type ipv4_addr; flags interval; }'
nft add set inet nat <policy_users_set> '{ type ipv4_addr; flags interval; }'

nft add chain inet filter <POLICY_NAME>
nft add chain inet nat PRE_NAT_<POLICY_NAME>
nft add chain inet nat POST_NAT_<POLICY_NAME>

nft insert rule inet filter forward ip saddr @<policy_users_set> jump <POLICY_NAME>
nft insert rule inet filter forward ip daddr @<policy_users_set> jump <POLICY_NAME>

nft insert rule inet nat prerouting ip saddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>
nft insert rule inet nat prerouting ip daddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>

nft insert rule inet nat postrouting oifname @wan_ifaces ip saddr @<policy_users_set> jump POST_NAT_<POLICY_NAME>

nft add rule inet filter <POLICY_NAME> ip saddr <destination_ip> <action>
nft add rule inet filter <POLICY_NAME> ip daddr <destination_ip> <protocol> sport <source_port> <action>
nft add rule inet filter <POLICY_NAME> return

nft add rule inet nat PRE_NAT_<POLICY_NAME> ip daddr <destination_ip> <protocol> sport <source_port> <action>
nft add rule inet nat PRE_NAT_<POLICY_NAME> ip saddr <destination_ip> <action>
nft add rule inet nat PRE_NAT_<POLICY_NAME> return

nft add rule inet nat POST_NAT_<POLICY_NAME> ip daddr <destination_ip>  <protocol> sport <source_port> masquerade
nft add rule inet nat POST_NAT_<POLICY_NAME> return

nft add element inet mangle user4_marks { <policy_users_ip> : 0x00<isp_id><tc_class_id> }

nft add element inet filter <policy_users_set> { <policy_users_ip> }
nft add element inet nat <policy_users_set> { <policy_users_ip> }
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
    *   sets (who)
    *   chains (what)
    *   jumps (when)
 
All future case documentation **must reference the case number from here**.
