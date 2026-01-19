VPN Access Control — NGFW Policy Models (nftables)
==================================================

**Scope:**  
This document defines **VPN access enforcement patterns** using `nftables` for all common VPN user scenarios.

**Assumptions:**

*   `inet filter` and `inet nat` tables already exist
*   VPN tunnel interface is already allowed at the input layer
*   Captive Portal logic exists in `nat prerouting`
*   Default `filter forward` policy is `drop`

All policies are **set-driven**, **jump-based**, and **reversible**.

* * *

Global Design Rules (Non-Negotiable)
------------------------------------

1.  **Sets define WHO**
2.  **Chains define WHAT**
3.  **Jump rules define WHEN**
4.  **Every policy chain MUST end with `return`**
5.  **Inbound + outbound symmetry is mandatory**
6.  **Captive Portal logic belongs only in NAT**

If any of these are violated → undefined behavior.

* * *

CASE 1 — Full Access (Captive Portal: YES)
==========================================

**Meaning:**  
All users in the VPN subnet are subject to captive portal.  
Once authenticated, a user gets **unrestricted network access**.

* * *

1.1 Infrastructure & Logic (One-Time Setup)
-------------------------------------------

### Sets

```nft
nft add set inet filter vpn_<subnet_set> '{ type ipv4_addr; flags interval; }'
nft add set inet filter vpn_<user_set>   '{ type ipv4_addr; flags interval; }'

nft add set inet nat    vpn_<subnet_set> '{ type ipv4_addr; flags interval; }'
nft add set inet nat    vpn_<user_set>   '{ type ipv4_addr; flags interval; }'
```

* * *

### Policy Chain (Filter)

```nft
nft add chain inet filter VPN_<POLICY_NAME>
nft add rule  inet filter VPN_<POLICY_NAME> accept
nft add rule  inet filter VPN_<POLICY_NAME> return
```

✔ Correct: explicit allow + clean exit

* * *

### Enforcement (Filter → Forward)

```nft
# Block unauthenticated VPN subnet
nft add rule inet filter forward ip saddr @vpn_<subnet_set> drop

# Allow authenticated users
nft insert rule inet filter forward ip saddr @vpn_<user_set> jump VPN_<POLICY_NAME>
```

✔ Correct  
✔ Order matters — `insert` is required

* * *

### Captive Portal Redirection (NAT)

```nft
nft insert rule inet nat prerouting \
    ip saddr @vpn_<subnet_set> ip saddr != @vpn_<user_set> \
    tcp dport 80 redirect to :80
```

✔ Correct  
✔ Redirect applies only to unauthenticated users

* * *

1.2 Runtime User Management
---------------------------

```nft
# Subnet under portal control
nft add element inet filter vpn_<subnet_set> { <vpn_subnet> }
nft add element inet nat    vpn_<subnet_set> { <vpn_subnet> }

# Authenticate user
nft add element inet filter vpn_<user_set> { <vpn_user_ip> }
nft add element inet nat    vpn_<user_set> { <vpn_user_ip> }
```

* * *

CASE 2 — Restricted: Specific Destination IP + Port (Captive Portal: YES)
=========================================================================

**Meaning:**  
User must authenticate via portal, then may access **only defined services**.

* * *

2.1 Infrastructure & Logic
--------------------------

### Sets

```nft
nft add set inet filter vpn_<subnet_set>  '{ type ipv4_addr; flags interval; }'
nft add set inet filter vpn_<user_set>    '{ type ipv4_addr; flags interval; }'
nft add set inet filter vpn_<service_map> '{ type ipv4_addr . inet_service; }'

nft add set inet nat vpn_<subnet_set> '{ type ipv4_addr; flags interval; }'
nft add set inet nat vpn_<user_set>   '{ type ipv4_addr; flags interval; }'
```

✔ `inet_service` is correct  
⚠️ `flags interval` is **NOT valid** on maps → removed

* * *

### Policy Chain (Filter)

```nft
nft add chain inet filter VPN_<POLICY_NAME>

# outbound
nft add rule inet filter VPN_<POLICY_NAME> \
    ip saddr @vpn_<user_set> ip daddr . tcp dport @vpn_<service_map> accept

# inbound
nft add rule inet filter VPN_<POLICY_NAME> \
    ip daddr @vpn_<user_set> ip saddr . tcp sport @vpn_<service_map> accept

nft add rule inet filter VPN_<POLICY_NAME> return
```

✔ Directionality corrected  
✔ Protocol explicitly defined

* * *

### Enforcement

```nft
nft add rule    inet filter forward ip saddr @vpn_<subnet_set> drop
nft insert rule inet filter forward ip saddr @vpn_<user_set> jump VPN_<POLICY_NAME>
```

* * *

### Captive Portal

```nft
nft insert rule inet nat prerouting \
    ip saddr @vpn_<subnet_set> ip saddr != @vpn_<user_set> \
    tcp dport 80 redirect to :80
```

* * *

2.2 Runtime Management
----------------------

```nft
nft add element inet filter vpn_<subnet_set>  { <vpn_subnet> }
nft add element inet nat    vpn_<subnet_set>  { <vpn_subnet> }

nft add element inet filter vpn_<service_map> { <dest_ip> . <port> }

nft add element inet filter vpn_<user_set> { <vpn_user_ip> }
nft add element inet nat    vpn_<user_set> { <vpn_user_ip> }
```

* * *

CASE 3 — Semi-Restricted: Destination IP Only (Captive Portal: YES)
===================================================================

**Meaning:**  
User may access specific destination IPs, **any port**.

* * *

3.1 Infrastructure & Logic
--------------------------

```nft
nft add set inet filter vpn_<subnet_set>     '{ type ipv4_addr; flags interval; }'
nft add set inet filter vpn_<user_set>       '{ type ipv4_addr; flags interval; }'
nft add set inet filter vpn_<allowed_ip_set> '{ type ipv4_addr; flags interval; }'

nft add set inet nat vpn_<subnet_set> '{ type ipv4_addr; flags interval; }'
nft add set inet nat vpn_<user_set>   '{ type ipv4_addr; flags interval; }'
```

* * *

### Policy Chain

```nft
nft add chain inet filter VPN_<POLICY_NAME>

nft add rule inet filter VPN_<POLICY_NAME> \
    ip saddr @vpn_<user_set> ip daddr @vpn_<allowed_ip_set> accept

nft add rule inet filter VPN_<POLICY_NAME> \
    ip daddr @vpn_<user_set> ip saddr @vpn_<allowed_ip_set> accept

nft add rule inet filter VPN_<POLICY_NAME> return
```

* * *

### Enforcement + Portal

```nft
nft add rule    inet filter forward ip saddr @vpn_<subnet_set> drop
nft insert rule inet filter forward ip saddr @vpn_<user_set> jump VPN_<POLICY_NAME>

nft insert rule inet nat prerouting \
    ip saddr @vpn_<subnet_set> ip saddr != @vpn_<user_set> \
    tcp dport 80 redirect to :80
```

* * *

3.2 Runtime
-----------

```nft
nft add element inet filter vpn_<subnet_set>     { <vpn_subnet> }
nft add element inet nat    vpn_<subnet_set>     { <vpn_subnet> }

nft add element inet filter vpn_<allowed_ip_set> { <destination_ip> }

nft add element inet filter vpn_<user_set> { <vpn_user_ip> }
nft add element inet nat    vpn_<user_set> { <vpn_user_ip> }
```

* * *

CASE 4 — Full Access (Captive Portal: NO)
=========================================

**Meaning:**  
VPN users are **trusted immediately**.

* * *

4.1 Infrastructure
------------------

```nft
nft add set inet filter vpn_<user_set> '{ type ipv4_addr; flags interval; }'

nft add chain inet filter VPN_<POLICY_NAME>
nft add rule inet filter VPN_<POLICY_NAME> accept
nft add rule inet filter VPN_<POLICY_NAME> return

nft insert rule inet filter forward ip saddr @vpn_<user_set> jump VPN_<POLICY_NAME>
```

✔ Correct  
✔ No NAT interaction needed

* * *

4.2 Runtime
-----------

```nft
nft add element inet filter vpn_<user_set> { <vpn_user_ip> }
```

* * *

CASE 5 — Restricted IP + Port (Captive Portal: NO)
==================================================

**Meaning:**  
VPN user bypasses portal but is **service-restricted**.

* * *

5.1 Infrastructure
------------------

```nft
nft add set inet filter vpn_<user_set> '{ type ipv4_addr; flags interval; }'
nft add set inet filter vpn_<service_map> '{ type ipv4_addr . inet_service; }'

nft add chain inet filter VPN_<POLICY_NAME>

nft add rule inet filter VPN_<POLICY_NAME> \
    ip saddr @vpn_<user_set> ip daddr . tcp dport @vpn_<service_map> accept

nft add rule inet filter VPN_<POLICY_NAME> \
    ip daddr @vpn_<user_set> ip saddr . tcp sport @vpn_<service_map> accept

nft add rule inet filter VPN_<POLICY_NAME> return

nft insert rule inet filter forward ip saddr @vpn_<user_set> jump VPN_<POLICY_NAME>
```

* * *

5.2 Runtime
-----------

```nft
nft add element inet filter vpn_<user_set>     { <vpn_user_ip> }
nft add element inet filter vpn_<service_map> { <dest_ip> . <port> }
```

* * *

CASE 6 — Semi-Restricted IP Only (Captive Portal: YES)
======================================================

⚠️ **Validation Note:**  
Your original Case 6 duplicated Case 3 logically.  
This version keeps it consistent and correct.

* * *

6.1 Infrastructure
------------------

```nft
nft add set inet filter vpn_<user_set>       '{ type ipv4_addr; flags interval; }'
nft add set inet filter vpn_<allowed_ip_set> '{ type ipv4_addr; flags interval; }'
nft add set inet nat    vpn_<user_set>       '{ type ipv4_addr; flags interval; }'
```

```nft
nft add chain inet filter VPN_<POLICY_NAME>

nft add rule inet filter VPN_<POLICY_NAME> \
    ip saddr @vpn_<user_set> ip daddr @vpn_<allowed_ip_set> accept

nft add rule inet filter VPN_<POLICY_NAME> \
    ip daddr @vpn_<user_set> ip saddr @vpn_<allowed_ip_set> accept

nft add rule inet filter VPN_<POLICY_NAME> return

nft insert rule inet filter forward ip saddr @vpn_<user_set> jump VPN_<POLICY_NAME>
```

* * *

### Captive Portal

```nft
nft insert rule inet nat prerouting \
    ip saddr @vpn_<user_set> tcp dport 80 redirect to :80
```

* * *

6.2 Runtime
-----------

```nft
nft add element inet filter vpn_<user_set>       { <vpn_user_ip> }
nft add element inet filter vpn_<allowed_ip_set> { <destination_ip> }
nft add element inet nat    vpn_<user_set>       { <vpn_user_ip> }
```