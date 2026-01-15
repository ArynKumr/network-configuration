## Response:
Below is a **clean, corrected, and fully documented `.md`** for the **three NGFW policy cases you defined**, rewritten to be **logically precise**, **directionally correct**, and **operationally safe**.

I fixed wording issues, clarified intent, and corrected subtle mistakes (like ambiguous NAT directions and typos such as `ccept`).  
No features added. No assumptions changed.

* * *

NGFW User Policy Models (Set-Driven Policy Enforcement)
=======================================================

**Purpose:**  
Define **user-scoped firewall policies** using nftables **sets + jump chains**, without touching global firewall logic.

These policies are applied **after user identity is known** and are designed to be:

*   reusable,
*   auditable,
*   reversible.

* * *

Common Design Principles (Read Once)
------------------------------------

1.  **Sets define WHO the policy applies to**
2.  **Chains define WHAT the policy does**
3.  **Jump rules define WHEN the policy is evaluated**
4.  **`return` is mandatory** — missing it causes policy blackholes
5.  **QoS / ISP marks are always applied**, regardless of restriction level

* * *

CASE 1 — No Restrictions (All Traffic Allowed)
==============================================

**Use case:**  
Trusted users who should bypass all firewall restrictions while still:

*   using NAT correctly,
*   obeying ISP routing,
*   obeying QoS limits.

This is **full trust**, not filtering.

* * *

1\. Define Policy User Sets
---------------------------

```
nft add set inet filter <policy_users_set> { type ipv4_addr; flags interval; }
nft add set inet nat    <policy_users_set> { type ipv4_addr; flags interval; }
```

* * *

2\. Forward Chain Triggers (Bidirectional)
------------------------------------------

**Purpose:**  
Allow traffic **from and to** these users without restriction.

```
nft insert rule inet filter forward ip saddr @<policy_users_set> <action>
nft insert rule inet filter forward ip daddr @<policy_users_set> <action>
```

Typical `<action>`: `accept`

* * *

3\. NAT Prerouting Triggers
---------------------------

**Purpose:**  
Ensure these users bypass captive portal, DNS hijack, or other NAT logic.

```
nft insert rule inet nat prerouting ip saddr @<policy_users_set> <action>
nft insert rule inet nat prerouting ip daddr @<policy_users_set> <action>
```

* * *

4\. NAT Postrouting (Internet Access)
-------------------------------------

**Purpose:**  
Ensure outbound traffic is source-NATed.

```
nft insert rule inet nat postrouting \
    oifname @wan_ifaces ip saddr @<policy_users_set> masquerade
```

* * *

5\. QoS / ISP Routing Mark
--------------------------

```
nft add element inet mangle user4_marks {
    <policy_users_ip> : 0x00<isp_id><tc_class_id>
}
```

* * *

6\. Add User to Policy Set
--------------------------

```
nft add element inet filter <policy_users_set> { <policy_users_ip> }
nft add element inet nat    <policy_users_set> { <policy_users_ip> }
```

* * *

### Resulting Behavior

*   No firewall restrictions
*   No portal interception
*   QoS + ISP routing still enforced

⚠️ **This is maximum privilege**

* * *

CASE 2 — Restricted to Specific IP + Protocol + Port
====================================================

**Use case:**  
User may communicate **only** with a specific destination **and** specific services.

This is **tight, explicit trust**.

* * *

1\. Define Policy User Sets
---------------------------

```
nft add set inet filter <policy_users_set> '{ type ipv4_addr; flags interval; }'
nft add set inet nat    <policy_users_set> '{ type ipv4_addr; flags interval; }'
```

* * *

2\. Define Policy Chains
------------------------

```
nft add chain inet filter <user_policy>
nft add chain inet nat    PRE_NAT_<POLICY_NAME>
nft add chain inet nat    POST_NAT_<POLICY_NAME>
```

* * *

3\. Forward Chain Triggers
--------------------------

```
nft insert rule inet filter forward ip saddr @<policy_users_set> jump <user_policy>
nft insert rule inet filter forward ip daddr @<policy_users_set> jump <user_policy>
```

* * *

4\. NAT Prerouting Triggers
---------------------------

```
nft insert rule inet nat prerouting ip saddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>
nft insert rule inet nat prerouting ip daddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>
```

* * *

5\. NAT Postrouting Trigger
---------------------------

```
nft insert rule inet nat postrouting \
    oifname @wan_ifaces ip saddr @<policy_users_set> jump POST_NAT_<POLICY_NAME>
```

* * *

6\. FILTER Policy (Service-Level Control)
-----------------------------------------

```
nft add rule inet filter <user_policy> \
    ip daddr <destination_ip> <protocol> sport <source_port> <action>

nft add rule inet filter <user_policy> \
    ip saddr <destination_ip> <protocol> dport <destination_port> <action>

nft add rule inet filter <user_policy> return
```

* * *

7\. NAT-PREROUTING Policy
-------------------------

```
nft add rule inet nat PRE_NAT_<POLICY_NAME> \
    ip saddr <destination_ip> <protocol> dport <destination_port> <action>

nft add rule inet nat PRE_NAT_<POLICY_NAME> \
    ip daddr <destination_ip> <protocol> sport <source_port> <action>

nft add rule inet nat PRE_NAT_<POLICY_NAME> return
```

* * *

8\. NAT-POSTROUTING Policy
--------------------------

```
nft add rule inet nat POST_NAT_<POLICY_NAME> \
    ip daddr <destination_ip> <protocol> dport <destination_port> masquerade

nft add rule inet nat POST_NAT_<POLICY_NAME> return
```

* * *

9\. QoS Mark + Set Membership
-----------------------------

```
nft add element inet mangle user4_marks {
    <policy_users_ip> : 0x00<isp_id><tc_class_id>
}

nft add element inet filter <policy_users_set> { <policy_users_ip> }
nft add element inet nat    <policy_users_set> { <policy_users_ip> }
```

* * *

### Resulting Behavior

*   Only specified services reachable
*   Everything else dropped by default policy

* * *

CASE 3 — Restricted to a Single Destination IP (Protocol-Agnostic)
==================================================================

**Use case:**  
User may talk **only** to one destination IP, regardless of protocol/port.

* * *

1\. Define Policy User Sets
---------------------------

```
nft add set inet filter <policy_users_set> { type ipv4_addr; flags interval; }
nft add set inet nat    <policy_users_set> { type ipv4_addr; flags interval; }
```

* * *

2\. Define Policy Chains
------------------------

```
nft add chain inet filter <user_policy>
nft add chain inet nat    PRE_NAT_<POLICY_NAME>
nft add chain inet nat    POST_NAT_<POLICY_NAME>
```

* * *

3\. Trigger Jumps (Forward)
---------------------------

```
nft insert rule inet filter forward ip saddr @<policy_users_set> jump <user_policy>
nft insert rule inet filter forward ip daddr @<policy_users_set> jump <user_policy>
```

* * *

4\. Trigger Jumps (NAT)
-----------------------

```
nft insert rule inet nat prerouting ip saddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>
nft insert rule inet nat prerouting ip daddr @<policy_users_set> jump PRE_NAT_<POLICY_NAME>

nft insert rule inet nat postrouting \
    oifname @wan_ifaces ip saddr @<policy_users_set> jump POST_NAT_<POLICY_NAME>
```

* * *

5\. FILTER Policy (IP-Only)
---------------------------

```
nft add rule inet filter <user_policy> ip daddr <destination_ip> <action>
nft add rule inet filter <user_policy> ip saddr <destination_ip> <action>
nft add rule inet filter <user_policy> return
```

* * *

6\. NAT-PREROUTING Policy
-------------------------

```
nft add rule inet nat PRE_NAT_<POLICY_NAME> ip saddr <destination_ip> accept
nft add rule inet nat PRE_NAT_<POLICY_NAME> ip daddr <destination_ip> <action>
nft add rule inet nat PRE_NAT_<POLICY_NAME> return
```

* * *

7\. NAT-POSTROUTING Policy
--------------------------

```
nft add rule inet nat POST_NAT_<POLICY_NAME> \
    ip daddr <destination_ip> masquerade

nft add rule inet nat POST_NAT_<POLICY_NAME> return
```

* * *

8\. QoS Mark + Set Membership
-----------------------------

```
nft add element inet mangle user4_marks {
    <policy_users_ip> : 0x00<isp_id><tc_class_id>
}

nft add element inet filter <policy_users_set> { <policy_users_ip> }
nft add element inet nat    <policy_users_set> { <policy_users_ip> }
```

* * *

### Resulting Behavior

*   User can talk only to `<destination_ip>`
*   All other destinations silently blocked

* * *