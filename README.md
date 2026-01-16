* * *

Linux Networking & nftables — From Bare Metal to Working NGFW
=============================================================

**Audience:**  
Someone with a Linux machine and root access who wants to turn it into a **router / firewall / NGFW**.

**Assumptions (non-negotiable):**

*   You understand basic Linux CLI
*   You are root or have `sudo`
*   This is **not** a desktop machine
*   You are okay breaking networking temporarily

* * *

1\. Machine & OS Prerequisites
------------------------------

### Hardware requirements

*   At least **2 network interfaces**
    *   1 × WAN (Internet)
    *   1 × LAN (Internal network)
*   NICs must be **real interfaces**, not just Wi-Fi if you care about stability

Check:

```
ip link
```

You should see something like:

```
eth0   ← WAN
eth1   ← LAN
```

If you only see `lo`, stop. You don’t have networking.

* * *

2\. Kernel Requirements (Critical)
----------------------------------

### Enable IP forwarding (router mode)

Temporary (until reboot):

```
sysctl -w net.ipv4.ip_forward = 1
sysctl -w net.ipv4.conf.all.rp_filter = 0
sysctl -w net.ipv4.conf.default.rp_filter = 0
sysctl -w net.ipv4.conf.<WAN_INTERFACE>.rp_filter = 0
sysctl -w net.ipv4.conf.<LAN_INTERFACE>.rp_filter = 1
```

Persistent:

```
cat <<EOF >/etc/sysctl.d/99-forwarding.conf
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.<WAN_INTERFACE>.rp_filter = 0
net.ipv4.conf.<LAN_INTERFACE>.rp_filter = 1
EOF
sysctl --system
```

If this is **not enabled**, your firewall will pass traffic nowhere.

* * *

3\. Basic Network Interface Setup
---------------------------------

### Bring interfaces up (If they aren't already up)

```
ip link set eth0 up
ip link set eth1 up
```

* * *

### WAN interface (example: DHCP)

```
dhclient eth0
```

Verify:

```
ip addr show eth0
ip route
```

You **must** have:

*   a public IP or upstream IP ,as that implies it connects your server to the external network a.k.a the internet.
*   a default route via eth0

* * *

### LAN interface (static IP)

Example LAN: `192.168.1.0/24`
>Note: Refer [RFC 1918](https://www.rfc-editor.org/rfc/rfc1918) to see what ips are set aside for private networks (LAN)
```
ip addr add 192.168.1.1/24 dev eth1
```

Verify:

```
ip addr show eth1
```

* * *

### Test local connectivity

From a LAN client:

```
ping 192.168.1.1
```

If this fails, stop. Fix basic networking first.

* * *

4\. DNS & DHCP (Minimal but Required)
-------------------------------------

### DHCP server (example: Kea / dnsmasq)

You **must** provide IPs to LAN clients.

* * *

5\. Install nftables
--------------------

### Install

```
apt install nftables
```

Enable at boot:

```
systemctl enable nftables

nft list ruleset
```

* * *

6\. nftables: Absolute Basics
-----------------------------

### Flush everything (safe only on fresh system)

```
nft flush ruleset
```

* * *

### Create a minimal firewall skeleton

```
nft add table inet filter
nft add chain inet filter input  { type filter hook input priority 0 \; policy drop \; }
nft add chain inet filter forward{ type filter hook forward priority 0 \; policy drop \; }
nft add chain inet filter output { type filter hook output priority 0 \; policy accept \; }
```

This **will break connectivity** until you add rules.

* * *

7\. Allow Essential Traffic
---------------------------

### Allow loopback

```
nft add rule inet filter input iif lo accept
```

* * *

### Allow established and related connections

```
nft add rule inet filter input ct state established,related accept
nft add rule inet filter forward ct state established,related accept
```
>Refer man page of [conntrack](https://man.archlinux.org/man/conntrack.8.en) 
* * *

### Allow LAN → Internet

```
nft add rule inet filter forward iif eth1 oif eth0 accept
```

* * *

### Allow LAN → router (DNS, DHCP)

```
nft add rule inet filter input iif eth1 udp dport {67,68,53} accept
nft add rule inet filter input iif eth1 tcp dport 53 accept
```

* * *

8\. NAT (Internet Sharing)
--------------------------

### Create NAT table

```
nft add table inet nat
nft add chain inet nat prerouting  { type nat hook prerouting priority 0 \; }
nft add chain inet nat postrouting { type nat hook postrouting priority 100 \; }
```

* * *

### Masquerade LAN traffic

```
nft add rule inet nat postrouting oif eth0 masquerade
```

* * *

### Test from LAN client

```
ping 8.8.8.8
curl http://example.com
```

If this fails:

*   routing is wrong
*   NAT is missing
*   forwarding is broken

Fix **before continuing**.

* * *

9\. Applying NGFW Rules
-----------------------------

>NOTE: Import the nftables.conf file to you testing machine from the repo.

### Apply rules
Ensure `/etc/nftables.conf` contains everything by running the command below.
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

* * *

10\. From Here → NGFW Stack
---------------------------

At this point you have:

*   working router
*   working NAT
*   working firewall
*   persistent rules

Everything you will build, layers **on top of this**:

| Layer | Depends On |
| --- | --- |
| Geo blocking | prerouting hooks |
| Captive portal | NAT prerouting |
| QoS | mangle + tc |
| Policy routing | fwmark + ip rule |
| NGFW policies | filter input/forward |
| VPN | filter input + forward |

If **this base is wrong**, nothing above it will ever be stable.

* * *



0\. Pre-Flight Sanity Checks (DO NOT SKIP)
------------------------------------------

If these fail, stop immediately.

### nftables state

```
nft list ruleset
```

✔ All tables present: `filter`, `nat`, `mangle`, `webfilter`, `geo`  
✘ Missing table = boot logic failed

* * *

### Routing & policy routing

* [How to configure ip route and ip rules](route_rule_setup.md)

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

* [How to configure interfaces](iface_setup.md)
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
