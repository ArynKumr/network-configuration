VPN Policy Matrix — Split Tunnel & Full Tunnel
==============================================

_(With and Without Captive Portal)_

**Purpose:**  
Define **VPN user traffic behavior** across all supported modes:

*   Split Tunnel vs Full Tunnel
*   With Captive Portal vs Without
*   IP-only vs IP+Port restrictions

This document maps **12 operational cases** to their intent and rule groups.

* * *

Global Assumptions (Applies to All Cases)
-----------------------------------------

*   `lan_ifaces` includes LAN and optionally VPN interface
*   `wan_ifaces` includes internet-facing interface
*   Default `forward` policy is `drop`
*   VPN users are identified by **IP or IP+Port**
*   QoS & ISP routing are always enforced via `mangle`

* * *

AXIS DEFINITIONS (Read Once)
----------------------------

### Tunnel Mode

*   **Split Tunnel** → VPN users access **only selected destinations**
*   **Full Tunnel** → VPN users route **all traffic** through VPN

### Access Control

*   **Unrestricted** → All traffic allowed
*   **Restricted** → Limited by IP / Port / Protocol

### Captive Portal

*   **Enabled** → Non-auth VPN users redirected to portal
*   **Disabled** → No redirection

* * *

SPLIT TUNNEL CASES (1–6)
========================

* * *

Case 1 — Split Tunnel, No Restrictions, No Portal
-------------------------------------------------

**Intent:**  
VPN user can access **only permitted LAN paths**, no portal, no filtering.

**Key Characteristics**

*   IP-based allow
*   Forward accept both directions
*   No policy chains

**Used when:**  
Trusted VPN admin or internal staff.

```
nft add set inet filter <vpn_user_set> '{ type ipv4_addr; flags interval; }'
nft add element inet filter <vpn_user_set> { <vpn_user_ip> }
nft insert rule inet filter forward ip saddr @<vpn_user_set> accept
nft insert rule inet filter forward ip daddr @<vpn_user_set> accept
```

* * *

Case 2 — Split Tunnel, IP+Port Restricted, No Portal
----------------------------------------------------

**Intent:**  
VPN user can access **specific services only**.

**Mechanism**

*   `ipv4_addr . inet_service` maps
*   Dedicated filter chain
*   Default drop inside policy

**Used when:**  
Service-specific access (DB, API, SSH).

```
nft add set inet filter vpn_<vpn_policy_user_map_name> '{ type ipv4_addr . inet_service; flags interval; }'
nft add set inet filter vpn_<allowed_ip_port_map> '{ type ipv4_addr . inet_service; flags interval; }'
nft add chain inet filter VPN_<vpn_policy_name>
nft add element inet filter vpn_<vpn_policy_user_map_name> { <vpn_user_ip> . <vpn_user_port> }
nft add element inet filter vpn_<allowed_ip_port_map> { <destination_ip> . <destination_port> }
nft add rule inet filter VPN_<vpn_policy_name> ip daddr . tcp dport @vpn_<allowed_ip_port_map> accept
nft add rule inet filter VPN_<vpn_policy_name> ip saddr . tcp sport @vpn_<allowed_ip_port_map> accept
nft add rule inet filter VPN_<vpn_policy_name> drop
nft insert rule inet filter forward  ip saddr . tcp sport @vpn_<vpn_policy_user_map_name>  oifname @lan_ifaces jump VPN_<vpn_policy_name>
nft insert rule inet filter forward  ip daddr . tcp dport @vpn_<vpn_policy_user_map_name> iifname @lan_ifaces jump VPN_<vpn_policy_name>
```

* * *

Case 3 — Split Tunnel, IP-Only Restricted, No Portal
----------------------------------------------------

**Intent:**  
VPN user can reach **only one destination IP**.

**Mechanism**

*   IP-only allow list
*   No port granularity

**Used when:**  
Partner system or fixed backend.
```

nft add set inet filter <vpn_user_set> '{ type ipv4_addr; flags interval; }'  
nft add set inet filter <allowed_ips_set> '{ type ipv4_addr; flags interval; }'                                                                 
nft add chain inet filter VPN_<vpn_policy_name>
nft add element inet filter <vpn_user_set> { <vpn_user_ip> }
nft add element inet filter <allowed_ips_set> { <destination_ip> }
nft add rule inet filter VPN_<vpn_policy_name> ip daddr @<allowed_ips_set> accept
nft add rule inet filter VPN_<vpn_policy_name> ip saddr @<allowed_ips_set> accept
nft add rule inet filter VPN_<vpn_policy_name> drop
nft insert rule inet filter forward ip saddr @<vpn_user_set> jump VPN_<vpn_policy_name>
nft insert rule inet filter forward ip daddr @<vpn_user_set> jump VPN_<vpn_policy_name>
```
* * *

Case 4 — Split Tunnel, No Restrictions, With Portal
---------------------------------------------------

**Intent:**  
VPN subnet blocked until user authenticates.

**Mechanism**

*   Drop entire VPN subnet in `filter`
*   Portal redirect in `nat prerouting`
*   User IP exemption post-login
```
nft add set inet filter <vpn_subnet> '{ type ipv4_addr; flags interval; }'
nft add element inet filter <vpn_subnet> { <<vpn_subnet>> }
nft add set inet filter <vpn_user_set> '{ type ipv4_addr; flags interval; }'
nft insert rule inet filter forward ip saddr @<vpn_subnet> drop
nft insert rule inet filter forward ip saddr @<vpn_user_set> accept

nft add set inet nat <vpn_subnet> '{ type ipv4_addr; flags interval; }'
nft add element inet nat <vpn_subnet> { <<vpn_subnet>> }
nft add set inet nat <vpn_user_set> '{ type ipv4_addr; flags interval; }'
nft insert rule inet nat prerouting ip saddr @<vpn_subnet> ip saddr != @<vpn_user_set> tcp dport 80 redirect to :80

nft add element inet filter <vpn_user_set> { <vpn_user_ip> }
nft add element inet nat <vpn_user_set> { <vpn_user_ip> }
```
* * *

Case 5 — Split Tunnel, IP+Port Restricted, With Portal
------------------------------------------------------

**Intent:**  
Unauthenticated VPN users see portal, authenticated users get **service-limited access**.

**Mechanism**

*   Portal redirection for subnet
*   Service policy chain for authenticated users
```
nft add set inet filter <vpn_subnet> '{ type ipv4_addr; flags interval; }'
nft add element inet filter <vpn_subnet> { <<vpn_subnet>> }
nft add set inet filter vpn_<vpn_policy_user_map_name> '{ type ipv4_addr . inet_service; flags interval; }'
nft insert rule inet filter forward ip saddr @<vpn_subnet> drop
nft add set inet filter vpn_<allowed_ip_port_map> '{ type ipv4_addr . inet_service; flags interval; }'
nft add chain inet filter VPN_<vpn_policy_name>
nft add element inet filter vpn_<allowed_ip_port_map> { <destination_ip> . <destination_port> }
nft add rule inet filter VPN_<vpn_policy_name> ip daddr . tcp dport @vpn_<allowed_ip_port_map> accept
nft add rule inet filter VPN_<vpn_policy_name> ip saddr . tcp sport @vpn_<allowed_ip_port_map> accept
nft add rule inet filter VPN_<vpn_policy_name> drop
nft insert rule inet filter forward  ip saddr . tcp sport @vpn_<vpn_policy_user_map_name>  oifname @lan_ifaces jump VPN_<vpn_policy_name>
nft insert rule inet filter forward  ip daddr . tcp dport @vpn_<vpn_policy_user_map_name> iifname @lan_ifaces jump VPN_<vpn_policy_name>

nft add set inet nat <vpn_subnet> '{ type ipv4_addr; flags interval; }'
nft add element inet nat <vpn_subnet> { <<vpn_subnet>> }
nft add set inet nat <vpn_user_set> '{ type ipv4_addr; flags interval; }'
nft insert rule inet nat prerouting ip saddr @<vpn_subnet> ip saddr != @<vpn_user_set> tcp dport 80 redirect to :80

nft add element inet filter vpn_<vpn_policy_user_map_name> { <vpn_user_ip> . <vpn_user_port> }
nft add element inet nat <vpn_user_set> { <vpn_user_ip> }
```
* * *

Case 6 — Split Tunnel, IP-Only Restricted, With Portal
------------------------------------------------------

**Intent:**  
Authenticated VPN users can reach **only selected IPs**; others redirected.

**Mechanism**

*   Portal for subnet
*   IP-only policy chain
```
nft add set inet filter <vpn_subnet> '{ type ipv4_addr; flags interval; }'
nft add element inet filter <vpn_subnet> { <<vpn_subnet>> }
nft add set inet filter <vpn_user_set> '{ type ipv4_addr; flags interval; }' 
nft add rule inet filter forward ip saddr @<vpn_subnet> drop 
nft add set inet filter <allowed_ips_set> '{ type ipv4_addr; flags interval; }'                                                                 
nft add chain inet filter VPN_<vpn_policy_name>
nft add element inet filter <allowed_ips_set> { <destination_ip> }
nft add rule inet filter VPN_<vpn_policy_name> ip daddr @<allowed_ips_set> accept
nft add rule inet filter VPN_<vpn_policy_name> ip saddr @<allowed_ips_set> accept
nft add rule inet filter VPN_<vpn_policy_name> drop
nft insert rule inet filter forward  ip saddr @<vpn_user_set>  oifname @lan_ifaces jump VPN_<vpn_policy_name>
nft insert rule inet filter forward  ip daddr @<vpn_user_set> iifname @lan_ifaces jump VPN_<vpn_policy_name>

nft add set inet nat <vpn_subnet> '{ type ipv4_addr; flags interval; }'
nft add element inet nat <vpn_subnet> { <<vpn_subnet>> }
nft add set inet nat <vpn_user_set> '{ type ipv4_addr; flags interval; }'
nft insert rule inet nat prerouting ip saddr @<vpn_subnet> ip saddr != @<vpn_user_set> tcp dport 80 redirect to :80

nft add element inet filter <vpn_user_set> { <vpn_user_ip> }
nft add element inet nat <vpn_user_set> { <vpn_user_ip> }
```
* * *

FULL TUNNEL CASES (7–12)
========================

* * *

Case 7 — Full Tunnel, No Restrictions, No Portal
------------------------------------------------

**Intent:**  
VPN user behaves like a **LAN user**.

**Mechanism**

*   VPN interface added to `lan_ifaces`
*   `allowed_ip4` bypass
*   Full QoS + routing marks

**Used when:**  
Corporate VPN, full trust.
```
nft add element inet filter lan_ifaces {"<lan_iface>", "<vpn_iface>" }
nft add element inet nat lan_ifaces { "<lan_iface>", "<vpn_iface>" }


nft add set inet filter <vpn_user_set> '{ type ipv4_addr; flags interval; }'
nft add element inet filter <vpn_user_set> { <vpn_user_ip> }
nft insert rule inet filter forward ip saddr @<vpn_user_set> accept
nft add element inet filter allowed_ip4 { <vpn_user_ip> }
nft add element inet nat allowed_ip4 { <vpn_user_ip> }
nft add element inet mangle user4_marks { <vpn_user_ip> : 0x00<isp_id><tc_class_id> }
```
* * *

Case 8 — Full Tunnel, IP+Port Restricted, No Portal
---------------------------------------------------

**Intent:**  
All traffic goes through VPN, but **only specific services allowed**.

**Mechanism**

*   Service-based policy chain
*   Drop everything else
```
nft add element inet filter lan_ifaces {"<lan_iface>", "<vpn_iface>" }
nft add element inet nat lan_ifaces { "<lan_iface>", "<vpn_iface>" }

nft add set inet filter vpn_<vpn_policy_user_map_name> '{ type ipv4_addr . inet_service; flags interval; }'
nft add set inet filter vpn_<allowed_ip_port_map> '{ type ipv4_addr . inet_service; flags interval; }'
nft add chain inet filter VPN_<vpn_policy_name>
nft add element inet filter vpn_<vpn_policy_user_map_name> { <vpn_user_ip> . <vpn_user_port> }
nft add element inet filter vpn_<allowed_ip_port_map> { <destination_ip> . <destination_port> }
nft add rule inet filter VPN_<vpn_policy_name> ip daddr . tcp dport @vpn_<allowed_ip_port_map> accept
nft add rule inet filter VPN_<vpn_policy_name> ip saddr . tcp sport @vpn_<allowed_ip_port_map> accept
nft add rule inet filter VPN_<vpn_policy_name> drop
nft insert rule inet filter forward  ip saddr . tcp sport @vpn_<vpn_policy_user_map_name>  oifname @lan_ifaces jump VPN_<vpn_policy_name>
nft insert rule inet filter forward  ip daddr . tcp dport @vpn_<vpn_policy_user_map_name> iifname @lan_ifaces jump VPN_<vpn_policy_name>
nft add element inet filter allowed_ip4 { <vpn_user_ip> }
nft add element inet nat allowed_ip4 { <vpn_user_ip> }
nft add element inet mangle user4_marks { <vpn_user_ip> : 0x00<isp_id><tc_class_id> }
```
* * *

Case 9 — Full Tunnel, IP-Only Restricted, No Portal
---------------------------------------------------

**Intent:**  
Full tunnel, but user can talk **only to specific IPs**.

**Mechanism**

*   IP-only allow list
*   Explicit WAN/LAN enforcement
```
nft add element inet filter lan_ifaces {"<lan_iface>", "<vpn_iface>" }
nft add element inet nat lan_ifaces { "<lan_iface>", "<vpn_iface>" }

nft add element inet filter allowed_ip4 { <vpn_user_ip> }
nft add set inet filter <vpn_user_set> '{ type ipv4_addr; flags interval; }'  
nft add set inet filter <allowed_ips_set> '{ type ipv4_addr; flags interval; }'                                                                 
nft add chain inet filter VPN_<vpn_policy_name>
nft add element inet filter <vpn_user_set> { <vpn_user_ip> }
nft add element inet filter <allowed_ips_set> { <destination_ip> }
nft add rule inet filter VPN_<vpn_policy_name> ip daddr @<allowed_ips_set> accept
nft add rule inet filter VPN_<vpn_policy_name> ip saddr @<allowed_ips_set> accept
nft add rule inet filter VPN_<vpn_policy_name> oifname @lan_ifaces drop
nft add rule inet filter VPN_<vpn_policy_name> oifname @wan_ifaces accept
nft add rule inet filter VPN_<vpn_policy_name> drop
nft insert rule inet filter forward  ip saddr @<vpn_user_set>  oifname @lan_ifaces jump VPN_<vpn_policy_name>
nft insert rule inet filter forward  ip daddr @<vpn_user_set> iifname @lan_ifaces jump VPN_<vpn_policy_name>
nft add element inet nat allowed_ip4 { <vpn_user_ip> }
nft add element inet mangle user4_marks { <vpn_user_ip> : 0x00<isp_id><tc_class_id> }
```
* * *

Case 10 — Full Tunnel, No Restrictions, With Portal
---------------------------------------------------

**Intent:**  
VPN users must authenticate before gaining **full internet access**.

**Mechanism**

*   VPN subnet forced to portal
*   User IP exemption post-login
*   Full NAT + QoS applied
```
nft add element inet filter lan_ifaces {"<lan_iface>", "<vpn_iface>" }
nft add element inet nat lan_ifaces { "<lan_iface>", "<vpn_iface>" }

nft add set inet filter <vpn_subnet> '{ type ipv4_addr; flags interval; }'
nft add element inet filter <vpn_subnet> { <<vpn_subnet>> }
nft add set inet filter <vpn_user_set> '{ type ipv4_addr; flags interval; }'
nft add rule inet filter forward ip saddr @<vpn_subnet> drop
nft insert rule inet filter forward ip saddr @<vpn_user_set> accept
nft add set inet nat <vpn_subnet> '{ type ipv4_addr; flags interval; }'
nft add element inet nat <vpn_subnet> { <<vpn_subnet>> }
nft add set inet nat <vpn_user_set> '{ type ipv4_addr; flags interval; }'
nft insert rule inet nat prerouting ip saddr @<vpn_subnet> ip saddr != @<vpn_user_set> tcp dport 80 redirect to :80

nft add element inet filter <vpn_user_set> { <vpn_user_ip> }
nft add element inet nat <vpn_user_set> { <vpn_user_ip> }
nft add element inet filter allowed_ip4 { <vpn_user_ip> }
nft add element inet nat allowed_ip4 { <vpn_user_ip> }
nft add element inet mangle user4_marks { <vpn_user_ip> : 0x00<isp_id><tc_class_id> }
```
* * *

Case 11 — Full Tunnel, IP+Port Restricted, With Portal
------------------------------------------------------

**Intent:**  
Authenticated VPN users get **service-level access only**, others redirected.

**Mechanism**

*   Portal for subnet
*   Service-based policy chain after login
```
nft add element inet filter lan_ifaces {"<lan_iface>", "<vpn_iface>" }
nft add element inet nat lan_ifaces { "<lan_iface>", "<vpn_iface>" }

nft add set inet filter <vpn_subnet> '{ type ipv4_addr; flags interval; }'
nft add element inet filter <vpn_subnet> { <<vpn_subnet>> }
nft add set inet filter vpn_<vpn_policy_user_map_name> '{ type ipv4_addr . inet_service; flags interval; }'
nft add rule inet filter forward ip saddr @<vpn_subnet> drop
nft add set inet filter vpn_<allowed_ip_port_map> '{ type ipv4_addr . inet_service; flags interval; }'
nft add chain inet filter VPN_<vpn_policy_name>
nft add element inet filter vpn_<allowed_ip_port_map> { <destination_ip> . <destination_port> }
nft add rule inet filter VPN_<vpn_policy_name> ip daddr . tcp dport @vpn_<allowed_ip_port_map> accept
nft add rule inet filter VPN_<vpn_policy_name> ip saddr . tcp sport @vpn_<allowed_ip_port_map> accept
nft add rule inet filter VPN_<vpn_policy_name> drop
nft insert rule inet filter forward  ip saddr . tcp sport @vpn_<vpn_policy_user_map_name>  oifname @lan_ifaces jump VPN_<vpn_policy_name>
nft insert rule inet filter forward  ip daddr . tcp dport @vpn_<vpn_policy_user_map_name> iifname @lan_ifaces jump VPN_<vpn_policy_name>

nft add set inet nat <vpn_subnet> '{ type ipv4_addr; flags interval; }'
nft add element inet nat <vpn_subnet> { <<vpn_subnet>> }
nft add set inet nat <vpn_user_set> '{ type ipv4_addr; flags interval; }'
nft insert rule inet nat prerouting ip saddr @<vpn_subnet> ip saddr != @<vpn_user_set> tcp dport 80 redirect to :80

nft add element inet nat <vpn_user_set> { <vpn_user_ip> }
nft add element inet filter vpn_<vpn_policy_user_map_name> { <vpn_user_ip> . <vpn_user_port> }
nft add element inet filter allowed_ip4 { <vpn_user_ip> }
nft add element inet nat allowed_ip4 { <vpn_user_ip> }
nft add element inet mangle user4_marks { <vpn_user_ip> : 0x00<isp_id><tc_class_id> }
```
* * *

Case 12 — Full Tunnel, IP-Only Restricted, With Portal
------------------------------------------------------

**Intent:**  
Authenticated VPN users can reach **specific IPs only**, all others blocked.

**Mechanism**

*   Portal redirect until login
*   IP-only policy after login
```
nft add element inet filter lan_ifaces {"<lan_iface>", "<vpn_iface>" }
nft add element inet nat lan_ifaces { "<lan_iface>", "<vpn_iface>" }

nft add set inet filter <vpn_subnet> '{ type ipv4_addr; flags interval; }'
nft add element inet filter <vpn_subnet> { <<vpn_subnet>> }
nft add set inet filter <vpn_user_set> '{ type ipv4_addr; flags interval; }' 
nft add rule inet filter forward ip saddr @<vpn_subnet> drop 
nft add set inet filter <allowed_ips_set> '{ type ipv4_addr; flags interval; }'                                                                 
nft add chain inet filter VPN_<vpn_policy_name>
nft add element inet filter <allowed_ips_set> { <destination_ip> }
nft add rule inet filter VPN_<vpn_policy_name> ip daddr @<allowed_ips_set> accept
nft add rule inet filter VPN_<vpn_policy_name> ip saddr @<allowed_ips_set> accept
nft add rule inet filter VPN_<vpn_policy_name> drop
nft insert rule inet filter forward  ip saddr @<vpn_user_set>  oifname @lan_ifaces jump VPN_<vpn_policy_name>
nft insert rule inet filter forward  ip daddr @<vpn_user_set> iifname @lan_ifaces jump VPN_<vpn_policy_name>

nft add set inet nat <vpn_subnet> '{ type ipv4_addr; flags interval; }'
nft add element inet nat <vpn_subnet> { <<vpn_subnet>> }
nft add set inet nat <vpn_user_set> '{ type ipv4_addr; flags interval; }'
nft insert rule inet nat prerouting ip saddr @<vpn_subnet> ip saddr != @<vpn_user_set> tcp dport 80 redirect to :80

nft add element inet filter <vpn_user_set> { <vpn_user_ip> }
nft add element inet nat <vpn_user_set> { <vpn_user_ip> }
nft add element inet filter allowed_ip4 { <vpn_user_ip> }
nft add element inet nat allowed_ip4 { <vpn_user_ip> }
nft add element inet mangle user4_marks { <vpn_user_ip> : 0x00<isp_id><tc_class_id> }
```
* * *

COMMON BUILDING BLOCKS (Used Across All 12)
===========================================

Identity
--------

*   `<vpn_user_set>` → authenticated VPN users
*   `<vpn_subnet>` → all VPN clients (pre-auth)

Control
-------

*   Filter `forward` → access enforcement
*   NAT `prerouting` → portal redirection
*   NAT `postrouting` → masquerade

Enforcement
-----------

*   Policy chains (`VPN_<policy_name>`)
*   Default `drop` inside chains
*   Mandatory `return`

Traffic Shaping
---------------

```
nft add element inet mangle user4_marks {
  <vpn_user_ip> : 0x00<isp_id><tc_class_id>
}
```

* * *

OPERATOR RULES (NON-NEGOTIABLE)
===============================

1.  **Never forget `return` in policy chains**
2.  **Always mirror forward rules both directions**
3.  **Portal logic always lives in NAT prerouting**
4.  **VPN interface must be in `lan_ifaces` for full tunnel**
5.  **QoS marks are mandatory in all cases**
6.  **Split tunnel ≠ NAT exemption**

Break any of these and the behavior becomes undefined.

* * *

Quick Selection Table
---------------------

| Case | Tunnel | Portal | Restriction |
| --- | --- | --- | --- |
| 1 | Split | No | None |
| 2 | Split | No | IP+Port |
| 3 | Split | No | IP |
| 4 | Split | Yes | None |
| 5 | Split | Yes | IP+Port |
| 6 | Split | Yes | IP |
| 7 | Full | No | None |
| 8 | Full | No | IP+Port |
| 9 | Full | No | IP |
| 10 | Full | Yes | None |
| 11 | Full | Yes | IP+Port |
| 12 | Full | Yes | IP |

* * *