* * *

Base Firewall Ruleset (Boot-Time Initialization)
================================================

**Purpose:**  
Initialize the nftables firewall at system boot.  
This file:

*   flushes any existing ruleset,
*   defines all core sets and maps,
*   establishes WAN/LAN identity,
*   enforces default-deny forwarding,
*   applies DNS filtering, anti-DoS protection, and
*   implements strict IP/MAC binding with logging.

> **Execution:**  
> This file is intended to be executed **once at boot** using the nftables interpreter.

```
#!/usr/sbin/nft -f
```

* * *

Safety Reset
------------

**Purpose:**  
Ensure a clean firewall state on every boot.  
Prevents duplicate or conflicting rules if the script is reloaded.

```
flush ruleset
```

* * *

Filter Table (`inet filter`)
----------------------------

**Purpose:**  
The `filter` table is responsible for all **allow / deny** decisions.  
Using the `inet` family allows a single ruleset to handle both IPv4 and IPv6.

```
table inet filter {}
```

* * *

Section 1: Whitelists & Identity Sets
-------------------------------------

### Allowed IPv4 Addresses

**Purpose:**  
Primary IPv4 whitelist.

```
set allowed_ip4 {
    type ipv4_addr
    flags interval
}
```

* * *

### Allowed IPv6 Addresses

**Purpose:**  
Primary IPv6 whitelist.

```
set allowed_ip6 {
    type ipv6_addr
    flags interval
}
```

* * *

### Allowed MAC Addresses

**Purpose:**  
MAC-based whitelist for devices that should always be allowed,  
regardless of IP continuity.

```
set allowed_macs {
    type ether_addr
}
```

> **Note:**  
> MAC intervals are not supported in nftables. IEEE allocation ranges  
> cannot be expressed as intervals here.

* * *

### WAN Interfaces

**Purpose:**  
Identify interfaces connected to the public internet.

```
set wan_ifaces {
    type ifname
}
```

* * *

### LAN Interfaces

**Purpose:**  
Identify interfaces connected to internal users.

```
set lan_ifaces {
    type ifname
}
```

* * *

Section 2: IP ↔ MAC Binding (Anti-Spoofing)
-------------------------------------------

### IPv4 + MAC Binding

**Purpose:**  
Bind a specific IPv4 address to a specific MAC address.  
Prevents IP spoofing or users stealing vacant IPs.

```
set allowed_ip4_mac {
    type ipv4_addr . ether_addr ;
}
```

* * *

### IPv6 + MAC Binding

**Purpose:**  
IPv6 equivalent of the IPv4 binding.

```
set allowed_ip6_mac {
    type ipv6_addr . ether_addr ;
}
```

* * *

Section 3: Watchlists (Logging Sets)
------------------------------------

### IPv4 Watchlist

**Purpose:**  
Log all nftables activity for selected IPv4 addresses.

```
set log_users_v4 {
    type ipv4_addr
    flags interval
}
```

* * *

### IPv6 Watchlist

**Purpose:**  
Log all nftables activity for selected IPv6 addresses.

```
set log_users_v6 {
    type ipv6_addr
    flags interval
}
```

* * *

### MAC Address Watchlist

**Purpose:**  
Log activity based on device hardware address.

```
set log_users_mac {
    type ether_addr
}
```

* * *

### Block User Set
**Purpose:**
Upon user logout the ip, ip-mac, mac is put into this set to mitigate conntrack percistance

```
set blocked_users_v4 {
  type ipv4_addr;
  flags interval;
} 

set blocked_users_macs {
    type ether_addr;
}

set blocked_users_v4_mac {
    type ipv4_addr . ether_addr;
}
```

### 1\. Define the Blocklist Set

```nft
  set perma_blocked_mac_users {
    type ether_addr;
  }
```

### Meaning

*   `type ether_addr` → matches raw MAC addresses
*   No interval flag (MAC ranges are rarely valid use cases)
*   Set-based for O(1) lookup

* * *

Section 4: Chains (Packet Processing Logic)
-------------------------------------------

Input Chain (Traffic Directed at the Firewall)
----------------------------------------------

**Purpose:**  
Handles traffic addressed **to the firewall itself**  
(e.g. management UI, local services).


```
chain input {
    type filter hook input priority 0; policy drop;
    ct state vmap { established : accept, related : accept, invalid : drop }
    iifname @lan_ifaces accept
  }
``` 

### Enforce Block in INPUT Chain

```nft
    ether saddr @perma_blocked_mac_users drop
```

### Effect

Blocks traffic **destined to the firewall itself** from blocked MACs.

This prevents:

*   Web UI access
*   SSH access
*   VPN negotiation
*   DNS access
*   Captive portal interaction

* * *

Prerouting Chain (Early Packet Inspection)
------------------------------------------

**Purpose:**  
Intercept packets **before routing decisions** are made.

```
chain prerouting {
    type filter hook prerouting priority -100; policy accept;
```

### DNS Interception (NFQUEUE)

**Purpose:**  
Send DNS queries to user-space filtering software.  
Fail open if the inspection engine crashes.

```
    udp dport 53 queue num 0 bypass
    tcp dport 53 queue num 0 bypass
```

* * *

Forward Chain (Core Security Checkpoint)
----------------------------------------

**Purpose:**  
Controls traffic flowing **from LAN → WAN**.  
Default policy is **deny**.

```
chain forward {
    type filter hook forward priority 0; policy drop;
```

### Enforce Block in FORWARD Chain

```nft
    ether saddr @perma_blocked_mac_users drop
```

### Effect

Blocks traffic being routed **through** the firewall.

This prevents:

*   Internet access
*   LAN-to-LAN routing
*   VPN traversal
*   Proxy access
*   Split-tunnel access

* * *

### Block User Set
**Purpose:**

Upon user logout the ip is put in blocked_user_v4, blocked_users_macs, blocked_users_v4_mac set and dropped here

```
    ip saddr @blocked_users_v4 drop
    ip daddr @blocked_users_v4 drop
    ether saddr @blocked_users_macs drop
    ether daddr @blocked_users_macs drop
    ip saddr . ether saddr @blocked_users_v4_mac drop
    ip daddr . ether daddr @blocked_users_v4_mac drop
```
* * *

### Conntrack State Handling

**Purpose:**  
Allow legitimate traffic, drop malformed packets.

```
    ct state vmap {
        established : accept,
        related     : accept,
        invalid     : drop
    }
```

* * *

Jump to NGFW Chain
------------------
**Purpose:**  
To keep rules sequenced in a formal and intended manner we dont add rules in current chain we jump all the traffic to a chain which includes all the rules for firewalling.
```
jump FILTER_FORWARD
```

Rule Group A: IPv4 + MAC Validation
-----------------------------------

**Purpose:**  
Log and validate IPv4 traffic based on IP+MAC binding.

```
    iifname @lan_ifaces oifname @wan_ifaces \
    ip saddr @log_users_v4 log prefix "[FW-FILTER-FWD-IPMAC] " \
    level info

    iifname @lan_ifaces oifname @wan_ifaces \
    ip saddr . ether saddr @allowed_ip4_mac \
    accept
```

* * *

Rule Group B: IPv6 + MAC Validation
-----------------------------------

```
    iifname @lan_ifaces oifname @wan_ifaces \
    ip6 saddr @log_users_v6 log prefix \
     "[FW-FILTER-FWD-IP6MAC] " level info
    
    iifname @lan_ifaces oifname @wan_ifaces \
    ip6 saddr . ether saddr @allowed_ip6_mac \
    accept
```

* * *

Rule Group C: MAC-Only Whitelist
--------------------------------

**Purpose:**  
Allow devices solely based on MAC address.

```
    iifname @lan_ifaces oifname @wan_ifaces \
        ether saddr @log_users_mac \
        log prefix "[FW-FILTER-FWD-MACONLY] " level info

    iifname @lan_ifaces oifname @wan_ifaces \
        ether saddr @allowed_macs accept
```

* * *

Rule Group D: IPv4-Only Whitelist
---------------------------------

```
    iifname @lan_ifaces oifname @wan_ifaces \
        ip saddr @log_users_v4 \
        log prefix "[FW-FILTER-FWD-IP4ONLY] ACCEPT " level info

    iifname @lan_ifaces oifname @wan_ifaces \
        ip saddr @allowed_ip4 accept
```

* * *

Rule Group E: IPv6-Only Whitelist
---------------------------------

```
    iifname @lan_ifaces oifname @wan_ifaces \
        ip6 saddr @log_users_v6 \
        log prefix "[FW-FILTER-FWD-IP6ONLY] ACCEPT " level info

    iifname @lan_ifaces oifname @wan_ifaces \
        ip6 saddr @allowed_ip6 accept
```

* * *

Drop Logging Trap
-----------------

**Purpose:**  
Log failures for watched users **before** the default drop policy triggers.

```
    ip   saddr @log_users_v4  log prefix "[FW-FILTER-FWD-DROP] "  level info
    ip6  saddr @log_users_v6  log prefix "[FW-FILTER-FWD-DROP6] " level info
    ether saddr @log_users_mac log prefix "[FW-FILTER-FWD-DROP-MAC] " level info
```


NGFW Chain
----------

**Purpose:**  
To keep rules sequenced in a formal and intended manner we dont add rules in current chain we jump all the traffic to a chain which includes all the rules for firewalling.
```
chain filter_forward{
```
### Protocol Suppression

**Purpose:**  
Prevent encrypted DNS and QUIC from bypassing inspection and QoS. Can be configured to be allowed from front.
>NOTE: These rules can be added / deleted from the firewall front on user request
```
    tcp dport 853 drop   # DNS over TLS
    udp dport 853 drop
    udp dport 443 drop   # QUIC / HTTP3
```

* * *
NAT, Captive Portal & DNS Redirection (nftables)
================================================

**Purpose:**  
Define all Network Address Translation (NAT) logic, including:

*   transparent DNS interception,
*   captive portal redirection,
*   authenticated-user bypass,
*   blocked-user DNS hijacking, and
*   outbound masquerading (internet sharing).

This table operates on **packet address manipulation**, not permission decisions.

* * *

NAT Table (`inet nat`)
----------------------

**Purpose:**  
The `nat` table rewrites packet **destination** (DNAT / redirect) and **source** (SNAT / masquerade) addresses.

```
table inet nat {
```

* * *

Section 1: Identity & Control Sets
----------------------------------

> **Important:**  
    >- Sets are duplicated here because **each nftables table is independent** and there is no global scope declaration of sets.
    >- The NAT table must know who is authenticated so it can decide **who to redirect** and **who to skip**.

* * *

### IPv4 Watchlist (Logging)

**Purpose:**  
Log NAT activity for selected IPv4 users.

```
set log_users_v4 {
    type ipv4_addr
    flags interval
}
```

* * *

### IPv6 Watchlist (Logging)

```
set log_users_v6 {
    type ipv6_addr
    flags interval
}
```

* * *

### MAC Address Watchlist (Logging)

```
set log_users_mac {
    type ether_addr
}
```

* * *

### Allowed IPv4 Users (Authenticated)

**Purpose:**  
Users who have already authenticated and should bypass the captive portal.

```
set allowed_ip4 {
    type ipv4_addr
    flags interval
}
```

* * *

### Allowed IPv6 Users (Authenticated)

```
set allowed_ip6 {
    type ipv6_addr
    flags interval
}
```

* * *

### Allowed MAC Addresses

**Purpose:**  
Devices allowed to bypass authentication purely by hardware identity.

```
set allowed_macs {
    type ether_addr
}
```

* * *

### IPv4 + MAC Binding Map

**Purpose:**  
Ensures the IPv4 address and MAC address pair is valid.

```
map allowed_ip4_mac {
    type ipv4_addr . ether_addr : verdict
}
```

* * *

### IPv6 + MAC Binding Map

```
map allowed_ip6_mac {
    type ipv6_addr . ether_addr : verdict
}
```

* * *

### WAN Interfaces

**Purpose:**  
Identify interfaces connected to the public internet.

```
set wan_ifaces {
    type ifname
}
```

* * *

### LAN Interfaces

**Purpose:**  
Identify interfaces connected to internal users.

```
set lan_ifaces {
    type ifname
}
```

* * *

Section 2: Prerouting (DNAT / Redirect Logic)
---------------------------------------------

**Purpose:**  
Executed **immediately when a packet arrives**, before routing decisions.  
Used to intercept DNS and HTTP(S) traffic.

```
chain prerouting {
    type nat hook prerouting priority 0; policy accept;
```

* * *

### DNS Hijacking (Blocked / Marked Users)

**Purpose:**  
Force DNS queries from **marked users** to a special DNS service (usually “blocked” page logic).

```
    iifname @lan_ifaces meta mark & 0x01000000 == 0x01000000 udp dport 53 redirect to :5300
    iifname @lan_ifaces meta mark & 0x01000000 == 0x01000000 tcp dport 53 redirect to :5300
```

**Logic:**  
If a packet carries the block mark, its DNS is forcibly redirected to port `5300`.

* * *

### Transparent DNS Proxy (All Users)

**Purpose:**  
Force all DNS traffic to use the firewall’s DNS resolver — regardless of client configuration.

```
    iifname @lan_ifaces udp dport 53 redirect to :53
    iifname @lan_ifaces tcp dport 53 redirect to :53
```

**Logic:**  
Clients cannot bypass filtering by using external DNS (e.g. `8.8.8.8`).

Jump to NGFW Chain
------------------
**Purpose:**  
To keep rules sequenced in a formal and intended manner we dont add rules in current chain we jump all the traffic to a chain which includes all the rules for firewalling.
```
jump NAT_POST_BASE
```

* * *
### Authentication Bypass (“Skip Rules”)

**Purpose:**  
Stop NAT processing for authenticated users so they reach the real internet.

```
    iifname @lan_ifaces ip saddr @allowed_ip4 accept
    iifname @lan_ifaces ip6 saddr @allowed_ip6 accept
    iifname @lan_ifaces ether saddr @allowed_macs accept
    iifname @lan_ifaces ip saddr . ether saddr @allowed_ip4_mac accept
    iifname @lan_ifaces ip6 saddr . ether saddr @allowed_ip6_mac accept
```

**Logic:**  
`accept` here means:

> “Stop evaluating NAT rules — do not redirect.”

* * *

### Captive Portal Redirection (Unauthenticated Users)

**Purpose:**  
Redirect all HTTP and HTTPS traffic to the local captive portal web server.
> TODO: Make it so that 443 goes to X443 (eg 6443) and 80 goes to xx80 (eg 8080). This is so captive portal doesn't take up our port 80 and 443, hence we can use it for hosting "this website has been blocked" webpage. and other sites as the user desiers.
```
    iifname @lan_ifaces tcp dport 443 redirect to :443
    iifname @lan_ifaces tcp dport 80  redirect to :80
```

**Logic:**  
If a packet reaches this point:

*   the user is **not authenticated**
*   every website request is hijacked
*   traffic is sent to the firewall’s local web service (login / splash page)

* * *

Section 3: Postrouting (SNAT / Masquerade)
------------------------------------------

**Purpose:**  
Executed **just before packets leave the firewall** toward the internet.

```
chain postrouting {
    type nat hook postrouting priority 100; policy accept;
```

* * *

### NAT Audit Logging

**Purpose:**  
Record which users are accessing the internet.
>TODO: Add rules for complex SNAT not just masquerade.

```
    oifname @wan_ifaces ip  saddr @log_users_v4  log prefix "[FW-NAT-SNAT] " level info
    oifname @wan_ifaces ip6 saddr @log_users_v6  log prefix "[FW-NAT-SNAT] " level info
    oifname @wan_ifaces ether saddr @log_users_mac log prefix "[FW-NAT-SNAT] " level info
```

* * *

### Internet Sharing (Masquerade)

**Purpose:**  
Enable multiple internal devices to share a single public IP.

```
    oifname @wan_ifaces ip saddr @allowed_ip4 masquerade
    oifname @wan_ifaces ip6 saddr @allowed_ip6 masquerade
    oifname @wan_ifaces ether saddr @allowed_macs masquerade
    oifname @wan_ifaces ip saddr . ether saddr @allowed_ip4_mac masquerade
    oifname @wan_ifaces ip6 saddr . ether saddr @allowed_ip6_mac masquerade
```

* * *

Packet Marking & QoS Classification (nftables)
==============================================

**Purpose:**  
Assign persistent packet marks to users based on:

*   IPv4 address,
*   IPv6 address, or
*   MAC address,

so downstream systems (TC, QoS, policy routing, logging) can reliably identify traffic **in both directions**.

This table **does not allow or deny traffic** — it only labels it.

* * *

Mangle Table (`inet mangle`)
----------------------------

**Purpose:**  
The `mangle` table modifies **packet metadata** (marks).  
Think of this as the labeling stage used by QoS, routing, and analytics.

```
table inet mangle {
```

* * *

Section 1: Tagging Watchlists (Logging)
---------------------------------------

**Purpose:**  
Define which users’ tagging activity should be logged.

* * *

### IPv4 Tagging Watchlist

```
set log_users_v4 {
    type ipv4_addr
    flags interval
}
```

* * *

### IPv6 Tagging Watchlist

```
set log_users_v6 {
    type ipv6_addr
    flags interval
}
```

* * *

### MAC Address Tagging Watchlist

```
set log_users_mac {
    type ether_addr
    flags interval
}
```

* * *

Section 2: Mark Lookup Maps
---------------------------

**Purpose:**  
Associate users with a **numeric mark**.

> **Mark format convention:**  
> `0x00<ISP_ID><TC_CLASS_ID>`  
> Example: `0x00ffFFFF`
> 
> *   `ff` → ISP identifier
> *   `FFFF` → Traffic control class
>     

* * *

### IPv4 → Mark Map

```
map user4_marks {
    type ipv4_addr : mark
}
```

* * *

### IPv4 . MAC → Mark Map

```
map user4_mac_marks {
    type ipv4_addr . ether_addr : mark
}
```

* * *

### IPv6 → Mark Map

```
map user6_marks {
    type ipv6_addr : mark
}
```

* * *

### MAC → Mark Map

```
map user_mac_marks {
    type ether_addr : mark
}
```

* * *

### vpn → Mark Map

```
set vpn_subnet {
    type ipv4_addr
    flags interval
}
```

* * *

Section 3: Tagging Logic (Chains)
---------------------------------

Prerouting Chain (Upload Traffic)
---------------------------------

**Purpose:**  
Tag packets **the instant they enter the firewall**.  
This covers traffic originating from users heading to the internet.

```
chain prerouting {
    type filter hook prerouting priority -150; policy accept;
```

* * *

### Upload Traffic Marking (User → Internet)

**Logic:**  
Identify the **sender** and apply their assigned mark.

```
    meta mark set ip  saddr map @user4_marks
    meta mark set ip6 saddr map @user6_marks
    meta mark set ether saddr map @user_mac_marks
    meta mark set ip saddr . ether saddr map @user4_mac_marks
    ip daddr @vpn_subnet iifname @lan_ifaces meta mark set 0x00000069
```

* * *

### Persist the Mark (Conntrack)

**Purpose:**  
Ensure the mark survives for the **entire lifetime of the connection**.

```
    ct mark set meta mark
```

* * *

Forward Chain (Download Traffic)
--------------------------------

**Purpose:**  
Tag packets flowing **from the internet to users**.

```
chain forward {
    type filter hook forward priority -150; policy accept;
```

* * *

### Download Traffic Marking (Internet → User)

**Logic:**  
Identify the **receiver** and apply their mark.

```
    meta mark set ip  daddr map @user4_marks
    meta mark set ip6 daddr map @user6_marks
    meta mark set ether daddr map @user_mac_marks
    meta mark set ip daddr . ether daddr map @user4_mac_marks
    ip saddr @vpn_subnet oifname @lan_ifaces meta mark set 0x00000069
```

* * *

### Persist the Mark (Conntrack)

```
    ct mark set meta mark
```

* * *

Postrouting Chain (Final Enforcement)
-------------------------------------

**Purpose:**  
Re-apply the mark **just before the packet leaves** the firewall.  
Protects against marks being stripped by NAT or other transformations.

```
chain postrouting {
    type filter hook postrouting priority -150;
```

```
    meta mark set ct mark
```

* * *

Web Traffic Inspection & NFQUEUE Handoff (nftables)
===================================================

**Purpose:**  
Intercept and selectively hand off **web traffic (HTTP/HTTPS)** to a user-space inspection engine via **NFQUEUE**, while:

*   restricting inspection to LAN users only,
*   supporting per-user inspection policies, and
*   failing open if the inspection engine crashes.

This table **does not block by itself** — it delegates decisions.

* * *

Webfilter Table (`inet webfilter`)
----------------------------------

**Purpose:**  
The `webfilter` table exists solely to decide **which packets are sent to NFQUEUE**  
for deep inspection by an external program.

```
table inet webfilter {
```

* * *

Section 1: Identity & Logging Sets
----------------------------------

* * *

### IPv4 Web Activity Watchlist

**Purpose:**  
Log web access attempts from selected IPv4 users.

```
set log_users_v4 {
    type ipv4_addr
    flags interval
}
```

* * *

### IPv6 Web Activity Watchlist

```
set log_users_v6 {
    type ipv6_addr
    flags interval
}
```

* * *

### MAC Address Web Activity Watchlist

```
set log_users_mac {
    type ether_addr
}
```

* * *

### Inspection Target List (`ALLOW_ACCESS`)

**Purpose:**  
Defines **which IPv4 users should have their web traffic inspected**.  
Only IPs in this set are sent to NFQUEUE.

```
set ALLOW_ACCESS {
    type ipv4_addr
    flags interval
}
```

> **Important:**  
> Despite the name, this set does **not** “allow” traffic —  
> it **flags users for inspection**.

* * *

### LAN Interfaces

**Purpose:**  
Ensure only traffic originating from the **internal network** is inspected.  
Prevents accidental interception of WAN or firewall-originated traffic.

```
set lan_ifaces {
    type ifname
}
```

* * *

Section 2: Webfilter Engine (Prerouting Chain)
----------------------------------------------

**Purpose:**  
Intercept packets **after mangle**, **before nat**, and decide whether to:

*   log them,
*   send them to NFQUEUE, or
*   ignore them entirely.

```
chain SYS_WEBFILTER {
    type filter hook prerouting priority -50; policy accept;
```

* * *

### Audit Logging (Watched Users)

**Purpose:**  
Record web activity for users on the logging watchlists.

```
    iifname @lan_ifaces ip  saddr @log_users_v4  log prefix "[FW-WEBFILTER] " level info
    iifname @lan_ifaces ip6 saddr @log_users_v6  log prefix "[FW-WEBFILTER] " level info
    iifname @lan_ifaces ether saddr @log_users_mac log prefix "[FW-WEBFILTER] " level info
```

**Logic:**  
If a watched user attempts to browse the web, an audit entry is written  
before any inspection or redirection occurs.

* * *

### NFQUEUE Handoff (HTTP / HTTPS)

**Purpose:**  
Send selected users’ web traffic to a user-space filtering engine.

```
    iifname @lan_ifaces ip saddr @ALLOW_ACCESS \
        tcp dport { 80, 443 } \
        queue num 0 bypass
```

**Logic:**

1.  **Source check** – user must be in `ALLOW_ACCESS`
2.  **Protocol check** – only TCP ports `80` and `443`
3.  **NFQUEUE** – packet is sent to queue `0`
4.  **Decision** – external program decides accept/drop
5.  **Fail-open** – if the program crashes, `bypass` lets traffic through

* * *

Geofencing & Country-Based Blocking (nftables)
==============================================

**Purpose:**  
Block traffic **to and from specific geographic regions** using large IP ranges, while:

*   dropping malicious traffic as early as possible,
*   minimizing CPU waste, and
*   logging all blocked attempts for audit and forensics.

This table enforces **hard borders** — no QoS, no redirection, no negotiation.

* * *

Geo Table (`inet geo`)
----------------------

**Purpose:**  
Dedicated table for country-level IP blocking.  
Optimized for **very large IP sets**.

```
table inet geo {
```

* * *

Section 1: Geographic Blacklists
--------------------------------

* * *

### IPv4 Country Blacklist

**Purpose:**  
Store IPv4 address ranges belonging to blocked countries.

```
set geo_v4 {
    type ipv4_addr
    flags interval
}
```

> **Why `interval` matters:**  
> Country-scale blocks involve thousands of contiguous ranges.  
> Without `interval`, this becomes unmanageable and slow.

* * *

### IPv6 Country Blacklist

```
set geo_v6 {
    type ipv6_addr
    flags interval
}
```

* * *

### WAN Interfaces

**Purpose:**  
Restrict geofencing to traffic that actually touches the internet.  
Prevents accidental blocking of internal traffic.

```
set wan_ifaces {
    type ifname
}
```

* * *

Section 2: Inbound Border Control (Prerouting)
----------------------------------------------

**Purpose:**  
Drop packets from blocked regions **before anything else touches them**.

```
chain prerouting {
    type filter hook prerouting priority -250; policy accept;
```

* * *

### Inbound Geo Blocks

```
    iifname @wan_ifaces ip  saddr @geo_v4 log prefix "[GEOFENCE-BLOCK-V4] " level info drop
    iifname @wan_ifaces ip6 saddr @geo_v6 log prefix "[GEOFENCE-BLOCK-V6] " level info drop
```

**Logic:**

1.  Packet arrives from a WAN-facing interface
2.  Source IP belongs to a blocked country
3.  Event is logged
4.  Packet is dropped immediately

**Design intent:**  
This chain runs at the **highest priority in the entire firewall**,  
ensuring hostile traffic never reaches NAT, mangle, or filter logic.

* * *

Section 3: Outbound Export Control (Forward Chain)
--------------------------------------------------

**Purpose:**  
Prevent internal devices from communicating with servers located in blocked regions  
(e.g., C2 infrastructure, malware update servers).

```
chain forward {
    type filter hook forward priority -250; policy accept;
```

* * *

### Outbound Geo Blocks

```
    oifname @wan_ifaces ip  daddr @geo_v4 log prefix "[GEOFENCE-BLOCK-V4] " level info drop
    oifname @wan_ifaces ip6 daddr @geo_v6 log prefix "[GEOFENCE-BLOCK-V6] " level info drop
```

**Logic:**

1.  Packet is about to leave toward the internet
2.  Destination IP belongs to a blocked country
3.  Event is logged
4.  Connection is terminated

>For further info refer [geo_setup.md](Customizations/geo_setup.md)  
* * *

Refer [nftables](nftables.conf) for a more granular explanation of the rules.