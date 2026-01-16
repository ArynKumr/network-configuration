* * *

VPN Policy Enforcement (NGFW-Aligned Model)
===========================================

**Purpose:**  
Apply **user-scoped firewall policies** to **VPN-connected users** using a  **similar NGFW design language** as LAN users.

This ensures:

*   VPN users are **not implicitly trusted**
*   VPN access is **explicit, auditable, and reversible**
*   VPN traffic obeys **QoS, routing, and restriction rules**

* * *

Common Assumptions
------------------

*   VPN interface exists (e.g. `wg0`, `tun0`)
*   VPN users receive **IPv4 addresses**
*   VPN traffic enters the firewall via `<vpn_iface>`
>   Default `forward` policy is `drop`

* * *

Shared Concepts (Same as NGFW)
------------------------------

| Component | Meaning |
| --- | --- |
| Set | Who the policy applies to |
| Chain | What rules apply |
| Jump | When policy is evaluated |
| Return | Exit back to global logic |
| Mark | ISP + QoS enforcement |

* * *

VPN CASE 1 — Full VPN Access (No Restrictions)
==============================================

**Use case:**  
Trusted VPN users (admins, site-to-site peers) with **full LAN + Internet access**.

This is equivalent to **NGFW Case 1**, but scoped to VPN ingress.

* * *

1\. Define VPN Policy User Sets
-------------------------------

```
nft add set inet filter <vpn_user_set> '{ type ipv4_addr; flags interval; }'
nft add set inet nat    <vpn_user_set> { type ipv4_addr; flags interval; }
```

* * *

2\. Forward Chain Triggers (VPN ↔ LAN/WAN)
------------------------------------------

```
nft insert rule inet filter forward \
    iifname "<vpn_iface>" ip saddr @<vpn_user_set> accept

nft insert rule inet filter forward \
    oifname "<vpn_iface>" ip daddr @<vpn_user_set> accept
```

* * *

3\. NAT Handling (Internet Access)
----------------------------------

```
nft insert rule inet nat postrouting \
    oifname @wan_ifaces ip saddr @<vpn_user_set> masquerade
```

* * *

4\. QoS / ISP Marking
---------------------

```
nft add element inet mangle user4_marks {
    <vpn_user_ip> : 0x00<isp_id><tc_class_id>
}
```

* * *

5\. Add User to Policy
----------------------

```
nft add element inet filter <vpn_user_set> { <vpn_user_ip> }
nft add element inet nat    <vpn_user_set> { <vpn_user_ip> }
```

* * *

### Resulting Behavior

*   VPN user behaves like a trusted LAN host
*   Full routing + NAT
*   QoS enforced
*   No firewall restriction

⚠️ **Maximum privilege – use sparingly**

* * *

VPN CASE 2 — VPN Access Restricted to Specific IP + Port + Protocol
===================================================================

**Use case:**  
Contractors, partners, or service VPN users allowed to access **only specific services**.

Equivalent to **NGFW Case 2**.

* * *

1\. Define Sets
---------------

```
nft add set inet filter <vpn_user_set>  { type ipv4_addr; flags interval; }
nft add set inet nat    <vpn_user_set>  { type ipv4_addr; flags interval; }
```

* * *

2\. Define Policy Chains
------------------------

```
nft add chain inet filter VPN_USER_POLICY
nft add chain inet nat    VPN_PRE_NAT
nft add chain inet nat    VPN_POST_NAT
```

* * *

3\. Forward Chain Triggers
--------------------------

```
nft insert rule inet filter forward \
    iifname <vpn_iface> ip saddr @<vpn_user_set>  jump VPN_USER_POLICY

nft insert rule inet filter forward \
    oifname <vpn_iface> ip daddr @<vpn_user_set>  jump VPN_USER_POLICY
```

* * *

4\. NAT Triggers
----------------

```
nft insert rule inet nat prerouting \
    ip saddr @<vpn_user_set>  jump VPN_PRE_NAT

nft insert rule inet nat postrouting \
    oifname @wan_ifaces ip saddr @<vpn_user_set>  jump VPN_POST_NAT
```

* * *

5\. FILTER Policy (Service-Level)
---------------------------------

```
nft add rule inet filter VPN_USER_POLICY \
    ip daddr <destination_ip> <protocol> dport <destination_port> accept

nft add rule inet filter VPN_USER_POLICY \
    ip saddr <destination_ip> <protocol> sport <destination_port> accept

nft add rule inet filter VPN_USER_POLICY return
```

* * *

6\. NAT-PREROUTING Policy
-------------------------

```
nft add rule inet nat VPN_PRE_NAT \
    ip daddr <destination_ip> accept

nft add rule inet nat VPN_PRE_NAT return
```

* * *

7\. NAT-POSTROUTING Policy
--------------------------

```
nft add rule inet nat VPN_POST_NAT \
    ip daddr <destination_ip> masquerade

nft add rule inet nat VPN_POST_NAT return
```

* * *

8\. QoS Mark + Membership
-------------------------

```
nft add element inet mangle user4_marks {
    <vpn_user_ip> : 0x00<isp_id><tc_class_id>
}

nft add element inet filter <vpn_user_set>  { <vpn_user_ip> }
nft add element inet nat    <vpn_user_set>  { <vpn_user_ip> }
```

* * *

### Resulting Behavior

*   VPN user can access **only specified services**
*   No lateral movement
*   Internet optional (depending on NAT)

* * *

VPN CASE 3 — VPN Access Restricted to a Single Destination IP
=============================================================

**Use case:**  
Site-to-site tunnels, monitoring systems, backup endpoints.

Equivalent to **NGFW Case 3**.

* * *

1\. Define Sets
---------------

```
nft add set inet filter <vpn_user_set>   { type ipv4_addr; flags interval; }
nft add set inet nat    <vpn_user_set>   { type ipv4_addr; flags interval; }
```

* * *

2\. Define Chains
-----------------

```
nft add chain inet filter VPN_IP_ONLY
nft add chain inet nat    VPN_PRE_NAT_IP
nft add chain inet nat    VPN_POST_NAT_IP
```

* * *

3\. Forward Triggers
--------------------

```
nft insert rule inet filter forward \
    iifname <vpn_iface> ip saddr @<vpn_user_set>   jump VPN_IP_ONLY

nft insert rule inet filter forward \
    oifname <vpn_iface> ip daddr @<vpn_user_set>   jump VPN_IP_ONLY
```

* * *

4\. NAT Triggers
----------------

```
nft insert rule inet nat prerouting \
    ip saddr @<vpn_user_set>   jump VPN_PRE_NAT_IP

nft insert rule inet nat postrouting \
    oifname @wan_ifaces ip saddr @<vpn_user_set>   jump VPN_POST_NAT_IP
```

* * *

5\. FILTER Policy (IP-Only)
---------------------------

```
nft add rule inet filter VPN_IP_ONLY ip daddr <destination_ip> accept
nft add rule inet filter VPN_IP_ONLY ip saddr <destination_ip> accept
nft add rule inet filter VPN_IP_ONLY return
```

* * *

6\. NAT Policies
----------------

```
nft add rule inet nat VPN_PRE_NAT_IP ip daddr <destination_ip> accept
nft add rule inet nat VPN_PRE_NAT_IP return
```

```
nft add rule inet nat VPN_POST_NAT_IP ip daddr <destination_ip> masquerade
nft add rule inet nat VPN_POST_NAT_IP return
```

* * *

7\. QoS + Membership
--------------------

```
nft add element inet mangle user4_marks {
    <vpn_user_ip> : 0x00<isp_id><tc_class_id>
}

nft add element inet filter <vpn_user_set>   { <vpn_user_ip> }
nft add element inet nat    <vpn_user_set>   { <vpn_user_ip> }
```

* * *

### Resulting Behavior

*   VPN user can talk **only to one IP**
*   No scanning
*   No lateral access
*   Ideal for automation endpoints

* * *