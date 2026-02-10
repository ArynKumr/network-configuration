
0\. Pre-Flight Sanity Checks (DO NOT SKIP)
------------------------------------------

Ensure all the steps in [Network Setup](network_setup.md) are followed
If these fail, stop immediately.

### nftables state

```
nft list ruleset
```

✔ All tables present: `filter`, `nat`, `mangle`, `webfilter`, `geo`  
✘ Missing table = boot logic failed

* * *

### Routing & policy routing

* [How to configure ip route and ip rules](./Customizations/route_rule_setup.md)

```
ip rule show
ip route show table main
ip route show table <isp_table>
```

✔ ISP rules present  
✔ Default routes exist in ISP tables  
✘ No routes = traffic will blackhole


* * *

* * *

### Setting up ifaces

* [How to configure interfaces](./Customizations/iface_setup.md)
```
nft add element inet filter wan_ifaces { "<wan_iface1>", "<wan_iface2>" }
nft add element inet nat wan_ifaces { "<wan_iface1>", "<wan_iface2>" }
nft add element inet geo wan_ifaces { "<wan_iface1>", "<wan_iface2>" }
nft add element inet filter lan_ifaces { "<lan_iface1>", "<lan_iface2>" }
nft add element inet nat lan_ifaces { "<lan_iface1>", "<lan_iface2>" }
nft add element inet webfilter lan_ifaces { "<lan_iface1>", "<lan_iface2>" }
```
✔ LAN WAN interfaces present in NFT  
✘ No interfaces = traffic will blackhole


* * *

### Traffic control

* [How to configure tc](./Customizations/tc_setup.md)

```
tc qdisc show
tc class show dev <iface>
```

✔ HTB root exists  
✔ Default class exists  
✘ No qdisc = QoS is fiction

* * *

1\. Unauthenticated User Test (Captive Portal)
----------------------------------------------

### Step 1: Connect a new device

*   No IP/MAC present in any `allowed_*` set

### Step 2: Try browsing

```
curl http://example.com
```

✔ Redirected to login page  
✘ Loads real website → NAT logic broken

### Step 3: DNS enforcement

```
dig @8.8.8.8 google.com
```

✔ DNS still resolves via router  
✘ External DNS works → DNS hijack broken

* * *

2\. Authentication Flow Test (Login Hook)
-----------------------------------------
Refer [user_login.md](Customizations/user_login.md)
After user logs in and login-time rules are applied:

### Verify set membership

```
nft list set inet filter allowed_ip4
nft list set inet nat allowed_ip4
nft list map inet mangle user4_marks
nft list set inet webfilter ALLOW_ACCESS
```

✔ User appears in all expected sets  
✘ Missing entry = partial access / weird bugs

* * *

### Verify internet access

```
curl https://example.com
```

✔ Real website loads  
✘ Still redirected → NAT skip broken

* * *

3\. Web Filtering (NFQUEUE)
---------------------------
Refer [user_login.md](Customizations/user_login.md) and [nftables.md](nftables.md)
### Trigger inspection

```
curl http://example.com
```

✔ NFQUEUE daemon logs packet  
✔ Page allowed or blocked by policy

If daemon is stopped:

```
systemctl stop <webfilter_service>
```
>Currently the service planned for it is `netifyd`.
✔ Traffic still flows (bypass works)  
✘ Internet dies → `bypass` missing (critical bug)

* * *

4\. QoS / Speed Limit Testing
-----------------------------
Refer [tc_setup.md](Customizations/tc_setup.md)

### Check packet marking

```
conntrack -L
```

or

```
tcpdump -i <iface> -e
```

✔ Packets carry expected `mark`  
✘ No mark → mangle logic broken

* * *

### Check class counters

```
tc -s class show dev <iface>
```

✔ User class counters increase  
✔ Default class stays low  
✘ All traffic in default class → tc filter broken

* * *

### Throughput test

```
iperf3 -c <server>
```

✔ Speed capped at plan limit  
✘ Full line speed → QoS not enforced

* * *

5\. Multi-ISP / Policy Routing Test
-----------------------------------
Refer [route_rule_setup.md](Customizations/route_rule_setup.md)
### Force ISP selection (via mark)

Ensure user has ISP mark applied.

```
ip route get 8.8.8.8 mark 0x00<isp_mark>0000
```

✔ Correct ISP interface shown  
✘ Wrong interface → ip rule / mask wrong

* * *

### Live verification

```
tcpdump -i <isp_iface>
```

✔ User traffic exits expected ISP  
✘ Traffic leaks → routing broken

* * *

6\. Geo-Blocking Test
---------------------
Refer [geo_setup.md](Customizations/geo_setup.md)
### Inbound test (from blocked region)

From a blocked country IP:

```
nc -vz <public_ip> 80
```

✔ Connection dropped  
✔ Log entry:

```
[GEOFENCE-BLOCK-V4]
```

✘ Connection succeeds → geo table not active

* * *

### Outbound test

```
curl http://<blocked_country_ip>
```

✔ Connection blocked  
✔ Log entry exists  
✘ Connection succeeds → forward geo logic broken

* * *

7\. VPN Connectivity Test
-------------------------

Refer [vpn_setup.md](Customizations/vpn_setup.md)

### Tunnel establishment

```
wg show
# or
openvpn --status
```

✔ Handshake successful  
✘ No handshake → input rule missing

* * *

### VPN traffic forwarding

From VPN client:

```
ping 192.168.1.1
ping 8.8.8.8
```

✔ LAN reachable  
✔ Internet reachable (if allowed)  
✘ Connects but no traffic → forward rules broken

* * *

8\. NGFW Policy Override Test
-----------------------------
Refer [ngfw_policy.md](Customizations/ngfw_policy.md) for more details
### Add user to policy set

```
nft add element inet nat <policy_user_set> { <client_ip> }
```

### Verify jump

```
nft monitor trace
```

✔ Packet jumps to policy chain  
✘ No jump → trigger rule broken

* * *

### Verify policy effect

*   NAT behavior changes
*   Router access changes
*   Destination-specific behavior enforced

If nothing changes → policy chain logic wrong

* * *

9\. Logout / Expiry Test (CRITICAL)
-----------------------------------

Remove user entries:

```
nft delete element inet filter allowed_ip4 { <client_ip> }
nft delete element inet nat allowed_ip4 { <client_ip> }
nft delete element inet mangle user4_marks { <client_ip> }
nft delete element inet webfilter ALLOW_ACCESS { <client_ip> }
```

✔ User immediately loses access  
✘ Still online → teardown incomplete

* * *


9\. DMZ
-----------------------------------
Refer [dmz.md](Customizations/DMZ_Rules.md) for more details
**Purpose:**  
Provide runnable nftables templates for:

*   selective port forwarding (TCP, UDP, or both), and
*   full DMZ (all incoming traffic redirected to a single internal host),  
    with optional QoS marking.

* * *

10\. logging
-----------------------------------
Refer [logging_setup.md](Customizations/logging_setup.md) for more details
**Purpose:**  
Provide **controlled, opt-in visibility** into:

*   user traffic behavior
*   firewall decisions (accept / drop / redirect)
*   NAT activity
*   geofencing enforcement
*   packet marking (QoS / ISP routing)

Logging is **diagnostic**, not enforcement.  
Removing logging **must not change traffic behavior**.

* * *

10\. NGFW_rules
-----------------------------------
Refer [ngfw_rules.md](Customizations/ngfw_rules.md) for more details

**Purpose:**  
Apply **explicit firewall overrides** for selected users **after identity is known**.  
These rules intentionally bypass or partially bypass the default NGFW pipeline.

This layer is used for:

*   trusted devices,
*   administrators,
*   exceptions,
*   controlled partner access.
* * *

11\. VPN Policy
-----------------------------------
Refer [vpn_policy.md](Customizations/vpn_policy.md) for more details

_(With and Without Captive Portal)_

**Purpose:**  
Define **VPN user traffic behavior** across all supported modes:

*   Split Tunnel vs Full Tunnel
*   With Captive Portal vs Without
*   IP-only vs IP+Port restrictions

This document maps **12 operational cases** to their intent and rule groups.

12\. Allow Traffic To Firewall
-----------------------------------

Refer [allow_traffic_to_firewall.md](Customizations/allow_traffic_to_firewall.md) for more details

**Purpose:**  
Define which traffic is allowed or now to the firewall itself:

13\. Bandwidth quota
--
Refer [Bandwidth_Quota.md](Customizations/Bandwidth_Quota.md) for more details

**Purpose:**  
Perposal for how can we handle bandwidth quota:

13\. ISP Aggrigation
--
Refer [isp_aggrigation.md](Customizations/isp_aggrigation.md) for more details

**Purpose:**
This creates **a single default route** in a **non-main routing table** that contains **multiple next hops**.

Linux treats this as:

*   **ECMP (Equal/Weighted Cost Multi-Path) routing**
*   **Per-flow load balancing**, _not_ per-packet
*   **Stateless distribution**, decided at connection start

14\. ISP Failover
--
Refer [isp_failover.md](Customizations/isp_failover.md) for more details

**Purpose:**

Ensure that traffic **marked for ISP-1** (`fwmark 0x00<isp1_mark>0000/0x00ff0000`) is **automatically rerouted via ISP-2** when ISP-1 becomes unavailable — **without changing nftables rules or user marks**.

* * *

15\.Policy Based Routing
--
Refer [policy_based_route.md](Customizations/policy_based_route.md) for more details

**Purpose:**
This module implements **forced next-hop routing** for:

*   relayed subnets,
*   downstream switches,
*   L3 hops behind intermediate gateways,

It is used when traffic **must pass through a specific L3 device** before reaching its final destination.

16\. SNAT
--

Refer [SNAT_setup.md](Customizations/SNAT_setup.md) for more details

**Purpose:**
This document describes **Source NAT (SNAT) using nftables maps**.

It also explains the **routing and ISP-ID constraints** that **must** be respected for correctness.

* * *

17\. TCP/UDP Reverse Proxy


Refer [TCP_UDP_reverse_proxy.md](Customizations/TCP_UDP_reverse_proxy.md) for more details

**Purpose:**
This module enables **Layer-4 reverse proxying** (TCP/UDP) using NGINX **stream** mode.

Typical use cases:

*   exposing internal services behind a firewall
*   proxying non-HTTP protocols (VPNs, game servers, custom daemons)
*   decoupling public ISP IP from backend service IP
*   controlling access via nftables instead of application logic

* * *