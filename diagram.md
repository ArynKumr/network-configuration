# NGFW Architecture Diagram

```
                            ╔═══════════════════════════════════════════════════════════════╗
                            ║                    INTERNET / ISP                             ║
                            ║            (Multiple ISPs supported via policy routing)       ║
                            ╚═══════════════════════════════════════════════════════════════╝
                                                            │
                                                            │
                                    ┌───────────────────────┴───────────────────────┐
                                    │          WAN Interface(s)                     │
                                    │        (@wan_ifaces set)                      │
                                    │   eth0, ppp0, etc. (configurable)             │
                                    └───────────────────────┬───────────────────────┘
                                                            │
                    ┌───────────────────────────────────────┼───────────────────────────────────────┐
                    │                                       │                                       │
                    │                    LINUX KERNEL NETFILTER HOOKS                               │
                    │                                                                               │
                    │   ┌──────────────────────────────────────────────────────────────────────┐    │
                    │   │                                                                      │    │
                    │   │  PREROUTING (First point of contact)                                 │    │
                    │   │  ════════════════════════════════════                                │    │
                    │   │                                                                      │    │
                    │   │  1. [inet geo prerouting] ──────► GeoIP Enforcement                  │    │
                    │   │     │                              - Check geo_v4/geo_v6 sets        │    │
                    │   │     │                              - Drop blocked countries          │    │
                    │   │     │                              - Log violations                  │    │
                    │   │     │                                                                │    │
                    │   │     ▼                                                                │    │
                    │   │  2. [inet nat prerouting] ──────► NAT/Redirection Logic              │    │
                    │   │     │                              - Captive portal redirect         │    │
                    │   │     │                              - Port forwarding (DNAT)          │    │
                    │   │     │                              - DMZ rules                       │    │
                    │   │     │                              - Check allowed_ip4/ip6/macs      │    │
                    │   │     │                              - Check allowed_ip4_mac map       │    │
                    │   │     │                                                                │    │
                    │   │     ▼                                                                │    │
                    │   │  3. [inet mangle prerouting] ───► Packet Marking (QoS + Routing)     │    │
                    │   │     │                              - Apply user4_marks/user6_marks   │    │
                    │   │     │                              - Apply user_mac_marks            │    │
                    │   │     │                              - Mark: 0x00[ISP][TC_CLASS]       │    │
                    │   │     │                              - Enable policy routing           │    │
                    │   │     │                                                                │    │
                    │   └─────┼────────────────────────────────────────────────────────────────┘    │
                    │         │                                                                     │
                    │         ▼                                                                     │
                    │   ┌─────────────────────────────────────────────────────────────────────┐     │
                    │   │  ROUTING DECISION (Policy-Based)                                    │     │
                    │   │  ═══════════════════════════════════                                │     │
                    │   │                                                                     │     │
                    │   │  - Check fwmark (packet mark from mangle)                           │     │
                    │   │  - ip rule lookup: fwmark 0x00XX0000/0x00ff0000 → table N           │     │
                    │   │  - Route via specific ISP gateway                                   │     │
                    │   │  - Main table for unmarked traffic                                  │     │
                    │   │                                                                     │     │
                    │   └─────────────────────────────────────────────────────────────────────┘     │
                    │         │                                                                     │
                    │         ▼                                                                     │
                    │   ┌─────────────────────────────────────────────────────────────────────┐     │
                    │   │                                                                     │     │
                    │   │  FORWARD CHAIN (Security Gatekeeper)                                │     │
                    │   │  ════════════════════════════════════                               │     │
                    │   │                                                                     │     │
                    │   │  1. [inet filter forward] ──────► Core Security Logic               │     │
                    │   │     │                              - Anti-DDoS (connlimit, pktrate) │     │
                    │   │     │                              - Interface validation           │     │
                    │   │     │                              - WAN→LAN / LAN→WAN checks       │     │
                    │   │     │                              - IP/MAC binding verification    │     │
                    │   │     │                              - Whitelist checks:              │     │
                    │   │     │                                * allowed_ip4/ip6              │     │
                    │   │     │                                * allowed_macs                 │     │
                    │   │     │                                * allowed_ip4_mac map          │     │
                    │   │     │                              - Logging for watched users      │     │
                    │   │     │                              - Default policy: DROP           │     │
                    │   │     │                                                               │     │
                    │   │     ▼                                                               │     │
                    │   │  2. [inet mangle forward] ───────► Download Traffic Marking         │     │
                    │   │     │                              - Mark incoming per-user traffic │     │
                    │   │     │                              - Port-forwarding QoS            │     │
                    │   │     │                                                               │     │
                    │   │     ▼                                                               │     │
                    │   │  3. [inet webfilter forward] ────► NFQUEUE Inspection               │     │
                    │   │     │                              - HTTP/HTTPS to queue 1          │     │
                    │   │     │                              - Only for ALLOW_ACCESS set      │     │
                    │   │     │                              - External filter processes it   │     │
                    │   │     │                                                               │     │
                    │   └─────┼───────────────────────────────────────────────────────────────┘     │
                    │         │                                                                     │
                    │         ▼                                                                     │
                    │   ┌─────────────────────────────────────────────────────────────────────┐     │
                    │   │                                                                     │     │
                    │   │  POSTROUTING (Last stage before exit)                               │     │
                    │   │  ══════════════════════════════════                                 │     │
                    │   │                                                                     │     │
                    │   │  1. [inet nat postrouting] ──────► Source NAT (Masquerade)          │     │
                    │   │     │                              - SNAT for WAN interfaces        │     │
                    │   │     │                              - Hide internal IPs              │     │
                    │   │     │                              - Logging for watched users      │     │
                    │   │     │                                                               │     │
                    │   │     ▼                                                               │     │
                    │   │  2. [inet mangle postrouting] ───► Final Mark Application           │     │
                    │   │                                    - Ensure marks survive NAT       │     │
                    │   │                                                                     │     │
                    │   └─────────────────────────────────────────────────────────────────────┘     │
                    │                                       │                                       │
                    └───────────────────────────────────────┼───────────────────────────────────────┘
                                                            │
                                                            ▼
                                    ┌───────────────────────────────────────────┐
                                    │   TRAFFIC CONTROL (TC/QoS)                │
                                    │   ═══════════════════════════             │
                                    │                                           │
                                    │   • HTB qdisc (Hierarchical Token Bucket) │
                                    │   • Match fwmark → flowid (class)         │
                                    │   • Per-user bandwidth enforcement        │
                                    │   • Upload: WAN interface TC              │
                                    │   • Download: LAN interface TC            │
                                    │   • SFQ for fairness                      │
                                    │                                           │
                                    └───────────────────────────────────────────┘
                                                            │
                                                            │
                                    ┌───────────────────────┴───────────────────────┐
                                    │          LAN Interface(s)                     │
                                    │        (@lan_ifaces set)                      │
                                    │   eth1, br0, etc. (configurable)              │
                                    └───────────────────────┬───────────────────────┘
                                                            │
                                                            ▼
                            ╔═══════════════════════════════════════════════════════════════╗
                            ║              INTERNAL NETWORK / CLIENTS                       ║
                            ║                                                               ║
                            ║   • Authenticated users (via captive portal)                  ║
                            ║   • Whitelisted IPs/MACs                                      ║
                            ║   • IP+MAC bound devices (highest security)                   ║
                            ║   • VPN clients (via VPN interface)                           ║
                            ║                                                               ║
                            ╚═══════════════════════════════════════════════════════════════╝
```

---

## Component Breakdown

### 1. Tables & Their Responsibilities

```
┌──────────────┬────────────────────────────────────────────────────────────────┐
│   TABLE      │   PURPOSE                                                      │
├──────────────┼────────────────────────────────────────────────────────────────┤
│ inet filter  │ Security decisions (ACCEPT/DROP)                               │
│              │ - IP/MAC binding enforcement                                   │
│              │ - Whitelist validation                                         │
│              │ - Anti-DDoS protection                                         │
│              │ - Logging (opt-in watchlists)                                  │
│              │ - Default policy: DROP                                         │
├──────────────┼────────────────────────────────────────────────────────────────┤
│ inet nat     │ Address translation & redirection                              │
│              │ - Captive portal (redirect to login page)                      │
│              │ - Port forwarding (DNAT)                                       │
│              │ - DMZ configuration                                            │
│              │ - Masquerade (SNAT) for WAN                                    │
├──────────────┼────────────────────────────────────────────────────────────────┤
│ inet mangle  │ Packet metadata manipulation                                   │
│              │ - QoS marking (TC class assignment)                            │
│              │ - ISP routing mark (policy-based routing)                      │
│              │ - Combined mark: 0x00[ISP][TC_CLASS]                           │
├──────────────┼────────────────────────────────────────────────────────────────┤
│ inet         │ Web content inspection handoff                                 │
│ webfilter    │ - HTTP/HTTPS → NFQUEUE (queue 1)                               │
│              │ - Only for authorized users (ALLOW_ACCESS set)                 │
│              │ - External userspace filter processes traffic                  │
├──────────────┼────────────────────────────────────────────────────────────────┤
│ inet geo     │ GeoIP-based border enforcement                                 │
│              │ - Block traffic from specific countries                        │
│              │ - geo_v4 / geo_v6 subnet sets                                  │
│              │ - Applied at PREROUTING (earliest possible)                    │
└──────────────┴────────────────────────────────────────────────────────────────┘
```

---

### 2. User Authentication Flow

```
                        ┌─────────────────────────┐
                        │   New Client Connects   │
                        │   (Unknown IP/MAC)      │
                        └───────────┬─────────────┘
                                    │
                                    ▼
                        ┌─────────────────────────┐
                        │  Filter: DROP (default) │
                        │  NAT: Redirect to       │
                        │  Captive Portal         │
                        └───────────┬─────────────┘
                                    │
                                    ▼
                        ┌─────────────────────────┐
                        │  User Authenticates     │
                        │  (Web login / 802.1X)   │
                        └───────────┬─────────────┘
                                    │
                                    ▼
                    ┌───────────────┴───────────────┐
                    │                               │
         ┌──────────▼─────────┐          ┌──────────▼─────────┐
         │  IP-Based Login    │          │  MAC-Based Login   │
         │                    │          │                    │
         │ • allowed_ip4      │          │ • allowed_macs     │
         │ • allowed_ip6      │          │ • user_mac_marks   │
         │ • user4_marks      │          │                    │
         │ • ALLOW_ACCESS     │          │ • ALLOW_ACCESS     │
         └──────────┬─────────┘          └──────────┬─────────┘
                    │                               │
                    └───────────────┬───────────────┘
                                    │
                                    ▼
                        ┌─────────────────────────┐
                        │  IP+MAC Binding         │
                        │  (Highest Security)     │
                        │                         │
                        │ • allowed_ip4_mac map   │
                        │ • Prevents IP spoofing  │
                        │ • Strict identity       │
                        └───────────┬─────────────┘
                                    │
                                    ▼
                        ┌─────────────────────────┐
                        │  User Online & Active   │
                        │  - Internet access      │
                        │  - QoS enforced         │
                        │  - ISP routing applied  │
                        │  - Web filter active    │
                        └─────────────────────────┘
```

---

### 3. Policy-Based Routing (ISP Selection)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                    PACKET MARK STRUCTURE                                 │
│                                                                          │
│         0x00  [ISP_MARK]  [TC_CLASS_MARK]                                │
│           │       │              │                                       │
│           │       │              └─► Traffic Control Class ID            │
│           │       │                  (Bandwidth limit)                   │
│           │       │                                                      │
│           │       └─────────────────► ISP Identifier                     │
│           │                           (Which routing table)              │
│           │                                                              │
│           └─────────────────────────► Prefix (always 0x00)               │
│                                                                          │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  MANGLE TABLE (prerouting)  ──► Sets mark based on:                      │
│                                  • user4_marks map (IP → mark)           │
│                                  • user6_marks map                       │
│                                  • user_mac_marks map (MAC → mark)       │
│                                                                          │
│  IP RULE (kernel)           ──► Matches mark:                            │
│                                  fwmark 0x00[ISP]0000/0x00ff0000         │
│                                  table [ISP_TABLE_NUMBER]                │
│                                                                          │
│  IP ROUTE (per-ISP table)   ──► Routes via specific gateway:             │
│                                  default via [ISP_GATEWAY] dev [IFACE]   │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

Example:
  User mark: 0x00010002
            ╰──┬──╯╰─┬─╯
               │     └─► TC Class 2 (e.g., 50Mbps plan)
               └───────► ISP 1 routing table
```

---

### 4. Traffic Control (QoS) Integration

```
            WAN Interface (eth0) - Controls UPLOAD
            ═════════════════════════════════════
                              │
                    ┌─────────▼─────────┐
                    │  HTB Root Qdisc   │
                    │  handle 1:        │
                    └─────────┬─────────┘
                              │
                    ┌─────────▼─────────┐
                    │  Parent Class 1:1 │
                    │  (Total Capacity) │
                    └─────────┬─────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
    ┌─────────▼─────┐  ┌──────▼──────┐   ┌────▼────────┐
    │ Class 1:10    │  │ Class 1:20  │   │ Class 1:30  │
    │ Default/Guest │  │ User A      │   │ User B      │
    │ 10 Mbps       │  │ 100 Mbps    │   │ 50 Mbps     │
    └───────────────┘  └─────────────┘   └─────────────┘
            │                  │               │
    ┌───────▼───────┐  ┌───────▼──────┐ ┌──────▼──────┐
    │  SFQ (fair)   │  │  SFQ (fair)  │ │  SFQ (fair) │
    │  perturb 10   │  │  perturb 10  │ │  perturb 10 │
    └───────────────┘  └──────────────┘ └─────────────┘

    TC Filter matches fwmark:
    • 0x00010020 → flowid 1:20 (User A, ISP 1, 100M plan)
    • 0x00020030 → flowid 1:30 (User B, ISP 2, 50M plan)


                    LAN Interface (eth1) - Controls DOWNLOAD
                    ══════════════════════════════════════
                    (Same structure, mirrored for incoming traffic)
```

---

### 5. Special Features

#### DMZ / Port Forwarding
```
Internet → WAN IP:80 ──┬─► [DNAT Rule] ──► LAN Server 192.168.1.10:80
                       │
                       └─► [Filter Rule] ──► ACCEPT (security permit)
```

#### VPN Server Integration
```
Internet → WAN:51820/udp ──► [Input Chain] ──► VPN Server (WireGuard)
                                                      │
                    ┌─────────────────────────────────┘
                    │
VPN Client ←────────┼──────► [Forward Chain] ──► Internal Network
         (tun0)     │
                    └──────► [Filter: iifname tun0] ──► ACCEPT
```

#### GeoIP Enforcement
```
Packet arrives → [GeoIP Check @ PREROUTING]
                 │
                 ├─► Source IP in geo_v4/geo_v6? ──► DROP (log)
                 │
                 └─► Not blocked ──► Continue to NAT/Filter
```

---

### 6. Data Structures (Sets & Maps)

```
FILTER TABLE
├── allowed_ip4            (ipv4_addr, interval) ──► Whitelisted IPv4
├── allowed_ip6            (ipv6_addr, interval) ──► Whitelisted IPv6
├── allowed_macs           (ether_addr)          ──► Whitelisted MACs
├── allowed_ip4_mac        (ip4 . mac → verdict) ──► IP+MAC binding (v4)
├── allowed_ip6_mac        (ip6 . mac → verdict) ──► IP+MAC binding (v6)
├── log_users_v4           (ipv4_addr, interval) ──► IPv4 watchlist
├── log_users_v6           (ipv6_addr, interval) ──► IPv6 watchlist
├── log_users_mac          (ether_addr)          ──► MAC watchlist
├── wan_ifaces             (ifname)              ──► Internet-facing
└── lan_ifaces             (ifname)              ──► Client-facing

NAT TABLE
├── allowed_ip4            (ipv4_addr, interval) ──► Bypass captive portal
├── allowed_ip6            (ipv6_addr, interval)
├── allowed_macs           (ether_addr)
├── allowed_ip4_mac        (ip4 . mac → verdict)
├── allowed_ip6_mac        (ip6 . mac → verdict)
├── wan_ifaces             (ifname)              ──► For masquerade
└── lan_ifaces             (ifname)              ──► For portal redirect

MANGLE TABLE
├── user4_marks            (ip4 → mark)          ──► IPv4 → QoS+ISP mark
├── user6_marks            (ip6 → mark)          ──► IPv6 → QoS+ISP mark
└── user_mac_marks         (mac → mark)          ──► MAC → QoS+ISP mark

WEBFILTER TABLE
├── ALLOW_ACCESS           (ipv4_addr, interval) ──► Authorized for inspection
└── lan_ifaces             (ifname)              ──► Only inspect LAN traffic

GEO TABLE
├── geo_v4                 (ipv4_addr, interval) ──► Blocked country subnets
├── geo_v6                 (ipv6_addr, interval) ──► Blocked country prefixes
└── wan_ifaces             (ifname)              ──► Only check WAN traffic
```

---

## Operational Workflows

### Adding a New User

```bash
# 1. Grant internet access
nft add element inet filter allowed_ip4 { 192.168.1.100 }
nft add element inet nat allowed_ip4 { 192.168.1.100 }

# 2. Assign QoS + ISP routing (ISP 1, 100Mbps = class 0x0020)
nft add element inet mangle user4_marks { 192.168.1.100 : 0x00010020 }

# 3. Enable web filtering
nft add element inet webfilter ALLOW_ACCESS { 192.168.1.100 }

# 4. Create TC classes on WAN (upload) and LAN (download)
tc class add dev eth0 parent 1:1 classid 1:20 htb rate 100mbit ceil 100mbit
tc qdisc add dev eth0 parent 1:20 handle 20: sfq perturb 10
tc filter add dev eth0 protocol ip parent 1:0 prio 1 handle 0x00010020/0x0000FFFF fw flowid 1:20

tc class add dev eth1 parent 1:1 classid 1:20 htb rate 100mbit ceil 100mbit
tc qdisc add dev eth1 parent 1:20 handle 20: sfq perturb 10
tc filter add dev eth1 protocol ip parent 1:0 prio 1 handle 0x00010020/0x0000FFFF fw flowid 1:20
```

### Port Forwarding (DMZ)

```bash
# Forward public IP port 80 → internal server
nft insert rule inet nat prerouting \
    ip daddr <public_ip> tcp dport 80 \
    dnat to 192.168.1.10:80

# Allow forwarded traffic through filter
nft insert rule inet filter forward ip daddr 192.168.1.10 accept
```

### Blocking a Country

```bash
# Add subnets to GeoIP block list
nft add element inet geo geo_v4 { 203.0.113.0/24, 198.51.100.0/24 }
```

---

## Security Layers (Defense in Depth)

```
Layer 1: GeoIP Border Control      ──► Drop blocked countries at PREROUTING
Layer 2: Captive Portal            ──► Unauthenticated users redirected (NAT)
Layer 3: IP/MAC Binding            ──► Prevent IP spoofing (filter + map)
Layer 4: Forward Chain Policy      ──► Default DROP, explicit ACCEPT only
Layer 5: Anti-DDoS                 ──► Connection/packet rate limits (filter)
Layer 6: Web Content Filtering     ──► NFQUEUE inspection (webfilter)
Layer 7: QoS Enforcement           ──► Bandwidth limits via TC (kernel)
Layer 8: Logging & Monitoring      ──► Opt-in watchlists per table
```

---

**This diagram represents the complete packet flow and architectural structure of the NGFW system.**
