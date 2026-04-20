NGFW Policy Truth Table (Case Definitions)
==========================================

**Purpose:**  
Define **authoritative traffic-matching semantics** for NGFW user policies.

Every policy case implemented in nftables **must correspond to one column in this table**.  



Policy Matching Truth Table
---------------------------

| Field | Source IP | Source Port | Destination IP | Destination Port | Protocol | Action | ISP ID | TC Class ID |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Case 1 | Specific | ALL | ALL | ALL | tcp/udp | allow / drop | ISP ID | TC Class ID |
| Case 2 | Specific | Specific | Specific | Specific | tcp/udp | allow / drop | ISP ID | TC Class ID |
| Case 3 | Specific | ALL | Specific | ALL | tcp/udp | allow / drop | ISP ID | TC Class ID |
| Case 4 | Specific | ALL | Specific | Specific | tcp/udp | allow / drop | ISP ID | TC Class ID |
| Case 5 | Specific | Specific | ALL | Specific | tcp/udp | allow / drop | ISP ID | TC Class ID |
| Case 6 | Specific | Specific | Specific | ALL | tcp/udp | allow / drop | ISP ID | TC Class ID |

# Policy Creation Common Rules

These are the common rules **To be applied before policy creation** before defining policies 

# IPV4

```
nft add set inet filter <policy_users_set> '{ type ipv4_addr; flags interval; }'
nft add set inet nat <policy_users_set> '{ type ipv4_addr; flags interval; }'

nft add chain inet filter <POLICY_NAME>

nft add chain inet nat PRE_NAT_<POLICY_NAME>
nft add chain inet nat POST_NAT_<POLICY_NAME>

nft insert rule inet filter FILTER_FORWARD ip saddr @<policy_users_set> jump <POLICY_NAME>
nft insert rule inet filter FILTER_FORWARD ip daddr @<policy_users_set> jump <POLICY_NAME>

nft insert rule inet nat NAT_PRE ip saddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>
nft insert rule inet nat NAT_PRE ip daddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>

nft insert rule inet nat NAT_POST oifname @wan_ifaces ip saddr @<policy_users_set> jump POST_NAT_<POLICY_NAME>

```

# IPV6

```
nft add set inet filter <policy_users_set> '{ type ipv6_addr; flags interval; }'
nft add set inet nat <policy_users_set> '{ type ipv6_addr; flags interval; }'

nft add chain inet filter <POLICY_NAME>

nft add chain inet nat PRE_NAT_<POLICY_NAME>
nft add chain inet nat POST_NAT_<POLICY_NAME>

nft insert rule inet filter FILTER_FORWARD ip6 saddr @<policy_users_set> jump <POLICY_NAME>
nft insert rule inet filter FILTER_FORWARD ip6 daddr @<policy_users_set> jump <POLICY_NAME>

nft insert rule inet nat NAT_PRE ip6 saddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>
nft insert rule inet nat NAT_PRE ip6 daddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>

nft insert rule inet nat NAT_POST oifname @wan_ifaces ip6 saddr @<policy_users_set> jump POST_NAT_<POLICY_NAME>

```

Case Semantics 
------------------------------------------

1. Case 1 — Identity-Only Policy

    **(Source IP only)**

    *   Matches only on **who** the user is
    *   No port, protocol, or destination restriction
    *   Used for:
        *   trusted users
        *   admin bypass

    **This is the highest-risk case.**
    ```
    nft add rule inet filter <POLICY_NAME> <action>

    nft add rule inet nat PRE_NAT_<POLICY_NAME> <action>

    nft add rule inet nat POST_NAT_<POLICY_NAME> masquerade

    ```
    ***
    OR (for specific protocol)
    --
    **(Source IP and protocol only)**

    *   Matches only on **who** the user is and what protocol is being used
    *   No port, or destination restriction
    *   Used for:
        *   trusted users
        *   admin bypass

    # IPV4

    ```
    nft add rule inet filter <POLICY_NAME> ip protocol <protocol> <action>

    nft add rule inet nat PRE_NAT_<POLICY_NAME> <action>

    nft add rule inet nat POST_NAT_<POLICY_NAME> masquerade

    ```

    # IPV6

    ```
    nft add rule inet filter <POLICY_NAME> ip6 protocol <protocol> <action>

    nft add rule inet nat PRE_NAT_<POLICY_NAME> <action>

    nft add rule inet nat POST_NAT_<POLICY_NAME> masquerade

    ```


1. Case 2 — Full 5-Tuple Policy

    **(Source IP + Source Port + Destination IP + Destination Port)**

    *   Most restrictive possible match
    *   Ideal for:
        *   database access
        *   SSH jump hosts
        *   API consumers

    # IPV4

    ```
    nft add rule inet filter <POLICY_NAME> ip daddr <destination_ip> <protocol> sport <source_port> <action>
    nft add rule inet filter <POLICY_NAME> ip saddr <destination_ip> <protocol> dport <destination_port> <action>
    nft add rule inet filter <POLICY_NAME> return

    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip saddr <destination_ip> <protocol> dport <destination_port> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip daddr <destination_ip> <protocol> sport <source_port> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> return

    nft add rule inet nat POST_NAT_<POLICY_NAME> ip daddr <destination_ip> <protocol> dport <destination_port> masquerade
    nft add rule inet nat POST_NAT_<POLICY_NAME> return

    ```

    # IPV6

    ```
    nft add rule inet filter <POLICY_NAME> ip6 daddr <destination_ip6> <protocol> sport <source_port> <action>
    nft add rule inet filter <POLICY_NAME> ip6 saddr <destination_ip6> <protocol> dport <destination_port> <action>
    nft add rule inet filter <POLICY_NAME> return

    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip6 saddr <destination_ip6> <protocol> dport <destination_port> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip6 daddr <destination_ip6> <protocol> sport <source_port> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> return

    nft add rule inet nat POST_NAT_<POLICY_NAME> ip6 daddr <destination_ip6> <protocol> dport <destination_port> masquerade
    nft add rule inet nat POST_NAT_<POLICY_NAME> return

    ```

1. Case 3 — Destination IP Policy

    **(Source IP → Destination IP)**

    *   Ignores ports entirely
    *   Allows all services **to one destination only**
    *   Common for:
        *   site-to-site links
        *   fixed backend services

    # IPV4

    ```
    nft add rule inet filter <POLICY_NAME> ip daddr <destination_ip> <action>
    nft add rule inet filter <POLICY_NAME> ip saddr <destination_ip> <action>
    nft add rule inet filter <POLICY_NAME> return

    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip saddr <destination_ip> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip daddr <destination_ip> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> return

    nft add rule inet nat POST_NAT_<POLICY_NAME> ip daddr <destination_ip> masquerade
    nft add rule inet nat POST_NAT_<POLICY_NAME> return
    ```

    # IPV6

    ```
    nft add rule inet filter <POLICY_NAME> ip6 daddr <destination_ip6> <action>
    nft add rule inet filter <POLICY_NAME> ip6 saddr <destination_ip6> <action>
    nft add rule inet filter <POLICY_NAME> return

    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip6 saddr <destination_ip6> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip6 daddr <destination_ip6> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> return

    nft add rule inet nat POST_NAT_<POLICY_NAME> ip6 daddr <destination_ip6> masquerade
    nft add rule inet nat POST_NAT_<POLICY_NAME> return
    ```

    ***
    OR (for specific protocol)
    --
    **(Source IP specific protocol → Destination IP specific protocol)**

    *   Ignores ports entirely
    *   Allows all services **to one destination specific protocol**
    *   Common for:
        *   site-to-site links
        *   fixed backend services

    # IPV4

    ```
    nft add rule inet filter <POLICY_NAME> ip daddr <destination_ip> ip protocol <protocol> <action>
    nft add rule inet filter <POLICY_NAME> ip saddr <destination_ip> ip protocol <protocol> <action>
    nft add rule inet filter <POLICY_NAME> return

    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip saddr <destination_ip> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip daddr <destination_ip> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> return

    nft add rule inet nat POST_NAT_<POLICY_NAME> ip daddr <destination_ip> masquerade
    nft add rule inet nat POST_NAT_<POLICY_NAME> return
    ```

    # IPV6

    ```
    nft add rule inet filter <POLICY_NAME> ip6 daddr <destination_ip> ip6 protocol <protocol> <action>
    nft add rule inet filter <POLICY_NAME> ip6 saddr <destination_ip> ip6 protocol <protocol> <action>
    nft add rule inet filter <POLICY_NAME> return

    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip6 saddr <destination_ip6> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip6 daddr <destination_ip6> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> return

    nft add rule inet nat POST_NAT_<POLICY_NAME> ip daddr <destination_ip> masquerade
    nft add rule inet nat POST_NAT_<POLICY_NAME> return
    ```


1. Case 4 — Destination IP + Port Policy

    **(Source IP → Destination IP:Port)**

    *   Service-specific access to a single host
    *   Safer than Case 3
    *   Typical for:
        *   HTTPS-only access
        *   single exposed service

    # IPV4

    ```
    nft add rule inet filter <POLICY_NAME> ip daddr <destination_ip> <action>
    nft add rule inet filter <POLICY_NAME> ip saddr <destination_ip> <protocol> dport <destination_port>  <action>
    nft add rule inet filter <POLICY_NAME> return

    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip saddr <destination_ip> <protocol> dport <destination_port>  <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip daddr <destination_ip> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> return

    nft add rule inet nat POST_NAT_<POLICY_NAME> ip daddr <destination_ip> <protocol> dport <destination_port>  masquerade
    nft add rule inet nat POST_NAT_<POLICY_NAME> return

    ```

    # IPV6

    ```
    nft add rule inet filter <POLICY_NAME> ip6 daddr <destination_ip6> <action>
    nft add rule inet filter <POLICY_NAME> ip6 saddr <destination_ip6> <protocol> dport <destination_port>  <action>
    nft add rule inet filter <POLICY_NAME> return

    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip6 saddr <destination_ip6> <protocol> dport <destination_port>  <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip6 daddr <destination_ip6> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> return

    nft add rule inet nat POST_NAT_<POLICY_NAME> ip6 daddr <destination_ip6> <protocol> dport <destination_port>  masquerade
    nft add rule inet nat POST_NAT_<POLICY_NAME> return

    ```

1. Case 5 — Port-Constrained Egress

    **(Source IP + Source Port → Any Destination: Specific Port)**

    *   Rare, but valid
    *   Used when **client-side port identity matters**
    *   Example:
        *   pinned application ports
        *   legacy systems

    # IPV4 / IPV6

    ```
    nft add rule inet filter <POLICY_NAME> <protocol> dport <destination_port> <protocol> sport <source_port> <action>
    nft add rule inet filter <POLICY_NAME> <protocol> sport <destination_port> <protocol> dport <source_port> <action>
    nft add rule inet filter <POLICY_NAME> return

    nft add rule inet nat PRE_NAT_<POLICY_NAME> <protocol> dport <destination_port> <protocol> sport <source_port> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> <protocol> sport <destination_port> <protocol> dport <source_port> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> return

    nft add rule inet nat POST_NAT_<POLICY_NAME> <protocol> dport <destination_port> <protocol> sport <source_port> masquerade
    nft add rule inet nat POST_NAT_<POLICY_NAME> return

    ```

1. Case 6 — Destination IP with Source Port

    **(Source IP:Port → Destination IP)**

    # IPV4

    ```
    nft add rule inet filter <POLICY_NAME> ip saddr <destination_ip> <action>
    nft add rule inet filter <POLICY_NAME> ip daddr <destination_ip> <protocol> sport <source_port> <action>
    nft add rule inet filter <POLICY_NAME> return

    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip daddr <destination_ip> <protocol> sport <source_port> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip saddr <destination_ip> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> return

    nft add rule inet nat POST_NAT_<POLICY_NAME> ip daddr <destination_ip>  <protocol> sport <source_port> masquerade
    nft add rule inet nat POST_NAT_<POLICY_NAME> return

    ```

    # IPV6

    ```
    nft add rule inet filter <POLICY_NAME> ip6 saddr <destination_ip6> <action>
    nft add rule inet filter <POLICY_NAME> ip6 daddr <destination_ip6> <protocol> sport <source_port> <action>
    nft add rule inet filter <POLICY_NAME> return

    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip6 daddr <destination_ip6> <protocol> sport <source_port> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> ip6 saddr <destination_ip6> <action>
    nft add rule inet nat PRE_NAT_<POLICY_NAME> return

    nft add rule inet nat POST_NAT_<POLICY_NAME> ip6 daddr <destination_ip6>  <protocol> sport <source_port> masquerade
    nft add rule inet nat POST_NAT_<POLICY_NAME> return

    ```

    USER LOGIN
    --

    # IPV4

    ```
    nft add element inet mangle user4_marks { <policy_users_ip> : 0x00<isp_id><tc_class_id> }
    nft add element inet filter <policy_users_set> { <policy_users_ip> }
    nft add element inet nat <policy_users_set> { <policy_users_ip> }   
    ```

    # IPV6

    ```
    nft add element inet mangle user6_marks { <policy_users_ip6> : 0x00<isp_id><tc_class_id> }
    nft add element inet filter <policy_users_set> { <policy_users_ip6> }
    nft add element inet nat <policy_users_set> { <policy_users_ip6> }   
    ```
    
    USER LOGOUT
    --
    For user logout we only need to remove ips of users from policy and mark sets

    # IPV4

    ```
    nft delete element inet mangle user4_marks { <policy_users_ip> : 0x00<isp_id><tc_class_id>}
    nft delete element inet filter <policy_users_set> { <policy_users_ip> }
    nft delete element inet nat <policy_users_set> { <policy_users_ip> }
    ```

    # IPV6

    ```
    nft delete element inet mangle user6_marks { <policy_users_ip6> : 0x00<isp_id><tc_class_id>}
    nft delete element inet filter <policy_users_set> { <policy_users_ip6> }
    nft delete element inet nat <policy_users_set> { <policy_users_ip6> }
    ```

Enforcement Rules
----------------------------

These rules apply to **all cases**:

1.  **Source IP is always specific**  
2.  **Protocol must be explicit (tcp/udp)**  
3.  **Unmatched traffic must hit default drop**  
4.  **Bidirectional rules are mandatory**  



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
