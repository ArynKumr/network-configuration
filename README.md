# Draco Firewall Setup

The following document describes how to set up the networking, DHCP, DNS and nftables in Draco Firewall. The steps are as follows:


## Core Infrastucture
1. Setup interfaces
    We must set up all the interfaces first before doing anything else. you can find the information on how to setup all types of interfaces [here](interfaces_setup.md)


1. DNS & DHCP

    You must set up DHCP. you can find the information regarding it [here](dhcp/dhcp-server-config.md)

    For DNS, follow these steps:

    ```bash
    sudo apt install dnsdist
    ```

    then make this file:
    ```lua
    -- in /etc/dnsdist/dnsdist.conf
    setSecurityPollSuffix("")
    setMaxUDPOutstanding(10240)
    newServer("8.8.8.8") -- this is the upstream server

    addLocal("192.168.1.1") -- this is what we listen to.
    ```

    `systemctl restart dnsdist`


1. Basic nftables

    1. Install nftables
        ```
        apt install nftables
        ```
    1. Enable at boot:
        ```
        systemctl enable nftables
        nft list ruleset
        ```

    1. Applying nftables Rules

        Ensure `/etc/nftables.conf` contains everything by running the command below. You can find the file nftables.conf [here](./nftables.conf)
        ```
        less /etc/nftables.conf
        ```
        After confirming the rules are stored in the location `/etc/nftables.conf`, run the command below
        ```
        nft -f /etc/nftables.conf
        ```

        To enable loading at boot:
        ```
        systemctl enable nftables
        ```

1. Setting up ifaces in nftables
    [How to configure interfaces](./Customizations/iface_setup.md)
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



## Routing & ISP Management

1. Routing & policy routing
    * [How to configure ip route and ip rules](./Customizations/route_rule_setup.md)
    ```
    ip rule show
    ip route show table main
    ip route show table <isp_table>
    ```

    ✔ ISP rules present  
    ✔ Default routes exist in ISP tables  
    ✘ No routes = traffic will blackhole


1. Multi-ISP / Policy Routing

    Refer [route_rule_setup.md](Customizations/route_rule_setup.md)

    1. Force ISP selection (via mark)

        Ensure user has ISP mark applied.

        ```
        ip route get 8.8.8.8 mark 0x00<isp_mark>0000
        ```

        ✔ Correct ISP interface shown  
        ✘ Wrong interface → ip rule / mask wrong


    1. Live verification

        ```
        tcpdump -i <isp_iface>
        ```

        ✔ User traffic exits expected ISP  
        ✘ Traffic leaks → routing broken


1. ISP Aggrigation

    Refer [isp_aggrigation.md](Customizations/isp_aggrigation.md) for more details

    **Purpose:**
    This creates **a single default route** in a **non-main routing table** that contains **multiple next hops**.

    Linux treats this as:

    *   **ECMP (Equal/Weighted Cost Multi-Path) routing**
    *   **Per-flow load balancing**, _not_ per-packet
    *   **Stateless distribution**, decided at connection start


1. ISP Failover

    Refer [isp_failover.md](Customizations/isp_failover.md) for more details

    **Purpose:**

    Ensure that traffic **marked for ISP-1** (`fwmark 0x00<isp1_mark>0000/0x00ff0000`) is **automatically rerouted via ISP-2** when ISP-1 becomes unavailable — **without changing nftables rules or user marks**.



1. Policy Based Routing

    Refer [policy_based_route.md](Customizations/policy_based_route.md) for more details

    **Purpose:**
    This module implements **forced next-hop routing** for:

    *   relayed subnets,
    *   downstream switches,
    *   L3 hops behind intermediate gateways,

    It is used when traffic **must pass through a specific L3 device** before reaching its final destination.



## Traffic Management

1. Traffic control

    * [How to configure tc](./Customizations/tc_setup.md)

        ```
        tc qdisc show
        tc class show dev <iface>
        ```

        ✔ HTB root exists  
        ✔ Default class exists  
        ✘ No qdisc = QoS is fiction


1. Bandwidth quota

    Refer [Bandwidth_Quota.md](Customizations/Bandwidth_Quota.md) for more details

    **Purpose:**  
    Perposal for how can we handle bandwidth quota:



1. QoS / Speed Limit
    Refer [tc_setup.md](Customizations/tc_setup.md)

    1. Check packet marking

        ```
        conntrack -L
        ```

        or

        ```
        tcpdump -i <iface> -e
        ```

        ✔ Packets carry expected `mark`  
        ✘ No mark → mangle logic broken

    1. Check class counters

        ```
        tc -s class show dev <iface>
        ```

        ✔ User class counters increase  
        ✔ Default class stays low  
        ✘ All traffic in default class → tc filter broken


    1. Throughput test

        ```
        iperf3 -c <server>
        ```

        ✔ Speed capped at plan limit  
        ✘ Full line speed → QoS not enforced



## User Access & Authentication

1. Captive Portal

    1. Connect a new device
        *   No IP/MAC present in any `allowed_*` set

    2. Try browsing

        ```
        curl http://example.com
        ```

        ✔ Redirected to login page  
        ✘ Loads real website → NAT logic broken


1. Login

    Refer [user_login.md](Customizations/user_login.md)
    After user logs in and login-time rules are applied:

    1. Verify set membership

        ```
        nft list set inet filter allowed_ip4
        nft list set inet nat allowed_ip4
        nft list map inet mangle user4_marks
        nft list set inet webfilter ALLOW_ACCESS
        ```

        ✔ User appears in all expected sets  
        ✘ Missing entry = partial access / weird bugs


    1. Verify internet access

        ```
        curl https://example.com
        ```

        ✔ Real website loads  
        ✘ Still redirected → NAT skip broken


1. Logout / Expiry

    Remove user entries:

    ```bash
    nft delete element inet filter allowed_ip4 { <client_ip> }
    nft delete element inet nat allowed_ip4 { <client_ip> }
    nft delete element inet mangle user4_marks { <client_ip> }
    nft delete element inet webfilter ALLOW_ACCESS { <client_ip> }
    ```

    > Note: we MUST also remove the policy entry during logout

    ```bash
    nft delete element inet mangle user4_marks {<policy_users_ip> : 0x00<isp_id><tc_class_id>}
    nft delete element inet filter <policy_users_set> { <policy_users_ip> }
    nft delete element inet nat <policy_users_set> { <policy_users_ip> }
    ```

    ✔ User immediately loses access  
    ✘ Still online → teardown incomplete



## Security & Network Policies

1. NGFW_rules
    Refer [ngfw_rules.md](Customizations/ngfw_rules.md) for more details

    **Purpose:**  
    Apply **explicit firewall overrides** for selected users **after identity is known**.  
    These rules intentionally bypass or partially bypass the default NGFW pipeline.

    This layer is used for:

    *   trusted devices,
    *   administrators,
    *   exceptions,
    *   controlled partner access.

1. NGFW Policy Override

    Refer [ngfw_policy.md](Customizations/ngfw_policy.md) for more details

    1. Add user to policy set

        ```
        nft add element inet nat <policy_user_set> { <client_ip> }
        ```

    1. Verify jump

        ```
        nft monitor trace
        ```

        ✔ Packet jumps to policy chain  
        ✘ No jump → trigger rule broken


    1. Verify policy effect

        *   NAT behavior changes
        *   Router access changes
        *   Destination-specific behavior enforced

    If nothing changes → policy chain logic wrong


1. Allow Traffic To Firewall

    Refer [allow_traffic_to_firewall.md](Customizations/allow_traffic_to_firewall.md) for more details

    **Purpose:**  
    Define which traffic is allowed or now to the firewall itself:


1. DMZ
    Refer [dmz.md](Customizations/DMZ_Rules.md) for more details

    **Purpose:**  
    Provide runnable nftables templates for:

    * selective port forwarding (TCP, UDP, or both), and
    * full DMZ (all incoming traffic redirected to a single internal host), with optional QoS marking.


1. SNAT

    Refer [SNAT_setup.md](Customizations/SNAT_setup.md) for more details

    **Purpose:**
    This document describes **Source NAT (SNAT) using nftables maps**.

    It also explains the **routing and ISP-ID constraints** that **must** be respected for correctness.


1. TCP/UDP Reverse Proxy


    Refer [TCP_UDP_reverse_proxy.md](Customizations/TCP_UDP_reverse_proxy.md) for more details

    **Purpose:**
    This module enables **Layer-4 reverse proxying** (TCP/UDP) using NGINX **stream** mode.

    Typical use cases:

    *   exposing internal services behind a firewall
    *   proxying non-HTTP protocols (VPNs, game servers, custom daemons)
    *   decoupling public ISP IP from backend service IP
    *   controlling access via nftables instead of application logic


1. Web Filtering (NFQUEUE)

        Refer [user_login.md](Customizations/user_login.md) and [nftables.md](nftables.md)

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


1. Geo-Blocking

    Refer [geo_setup.md](Customizations/geo_setup.md)

    1. Inbound test (from blocked region)

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


    1. Outbound test

        ```
        curl http://<blocked_country_ip>
        ```

        ✔ Connection blocked  
        ✔ Log entry exists  
        ✘ Connection succeeds → forward geo logic broken



## VPN & Remote Access
1. VPN Connectivity

    Refer [vpn_setup.md](Customizations/vpn_setup.md)

    1. Tunnel establishment

        ```
        wg show
        or
        openvpn --status
        ```

        ✔ Handshake successful  
        ✘ No handshake → input rule missing

    1. VPN traffic forwarding

        From VPN client:

        ```
        ping 192.168.1.1
        ping 8.8.8.8
        ```

        ✔ LAN reachable  
        ✔ Internet reachable (if allowed)  
        ✘ Connects but no traffic → forward rules broken


1. VPN Policy

    Refer [vpn_policy.md](Customizations/vpn_policy.md) for more details

    **Purpose:**  
    Define **VPN user traffic behavior** across all supported modes:

    *   Split Tunnel vs Full Tunnel
    *   With Captive Portal vs Without
    *   IP-only vs IP+Port restrictions

    This document maps **12 operational cases** to their intent and rule groups.




## Monitoring & Logging
1. logging
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