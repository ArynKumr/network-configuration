
# Interface Setup Guide

## Prerequisites

- Debian 13 (Trixie) — ships systemd 257
- `systemd-networkd` ≥ 257 — verify with `networkctl --version`
- `radvd` — handles all IPv6 RA advertisement to downstream clients; see [radvd-setup.md](Customizations/radvd-setup.md)
- `ndppd` — handles NDP proxying for downstream addresses; see [ndppd-setup.md](Customizations/ndppd-setup.md)
- A public IPv4/IPv6 address or ISP assignment
- A valid default route via your WAN interface
- For IPv6 routing: a delegated prefix (PD) or static block from your ISP

---

## Neighbor Discovery Protocol (NDP)

RFC 4861 defines NDP as the foundational control-plane protocol for IPv6. It handles address resolution, router discovery, prefix distribution, and reachability detection — replacing ARP and extending router/host interaction. The following NDP message types are in use throughout this guide:

| Type | ICMPv6 Code | Purpose |
|---|---|---|
| Router Solicitation (RS) | 133 | Client requests RA from router |
| Router Advertisement (RA) | 134 | Router announces prefix, gateway, flags |
| Neighbor Solicitation (NS) | 135 | Address resolution / DAD / NUD |
| Neighbor Advertisement (NA) | 136 | Response to NS |
| Redirect | 137 | Router informs host of better next-hop |

**Duplicate Address Detection (DAD)** runs automatically when an IPv6 address is assigned. The interface sends an NS for its own tentative address and listens for a conflicting NA before marking it valid.

**Neighbor Unreachability Detection (NUD)** probes active neighbours periodically using NS/NA to detect and remove stale entries.

DAD probe count and NS retransmission interval are per-interface kernel tunables managed in `99-ngfw.conf`. See [Kernel Forwarding and Interface Hardening](#kernel-forwarding-and-interface-hardening).

> **Proxy NDP** is handled by **ndppd**. See [ndppd-setup.md](ndppd-setup.md) for configuration of NA proxying on behalf of downstream addresses.

> **RA-Guard:** NDP is the primary attack surface for rogue router injection. The [nftables baseline](../nftables.conf) blocks unsolicited RAs from LAN ports at the host level. For switched environments, enable RA-Guard at the switch level (RFC 6105) in addition to the host firewall.

---

## Kernel Forwarding and Interface Hardening

All forwarding, reverse path filtering, RA acceptance, privacy extensions, DAD, NUD, and hardening parameters are centralised in `/etc/sysctl.d/99-ngfw.conf`. Replace `<WAN>` and `<LAN>` with your actual interface names (e.g. `eth0`, `eth1`). For virtual devices (bond, bridge, VLAN) add matching per-interface entries for each virtual interface name — see [Virtual Devices](#virtual-devices) for the full list of entries required per interface.

Two parameters in this file are scenario-dependent and must be set deliberately:

- `net.ipv6.conf.<WAN>.accept_ra` — set to `2` for Scenario A and C (ISP sends RAs); set to `0` for Scenario B (static assignment, no RAs expected). Only one should be active. The inactive scenario's line must be commented out.
- `net.ipv4.conf.<WAN>.rp_filter` — currently `0` (no source validation). Can be tightened to `2` (loose) once asymmetric routing behaviour from your ISP is confirmed.

On networkd-managed interfaces the kernel RA stack is bypassed entirely — networkd runs its own userspace RA client. `IPv6AcceptRA=` in the `.network` file is the correct knob for those interfaces and maps to `accept_ra=2` internally when set to `yes`. The `accept_ra` sysctl entries below are set explicitly for correctness and to cover any unmanaged interfaces (e.g. raw tap or manually configured interfaces).

#### **`/etc/sysctl.d/99-ngfw.conf`**

```bash
cat <<EOF > /etc/sysctl.d/99-ngfw.conf
# -----------------------------------------------
# IPv4 forwarding
# -----------------------------------------------
net.ipv4.ip_forward = 1

# -----------------------------------------------
# IPv4 reverse path filter
# Global baseline disabled — enforced per interface
# 0 = no source validation (WAN default — change to 2 once ISP routing is confirmed)
# 1 = strict source validation (LAN, known topology)
# 2 = loose source validation (WAN, asymmetric ISP routing)
# -----------------------------------------------
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0

net.ipv4.conf.<WAN>.rp_filter = 0
net.ipv4.conf.<LAN>.rp_filter = 1

# -----------------------------------------------
# IPv6 forwarding
# all.forwarding=1 is sufficient; default ensures
# new interfaces inherit it automatically
# -----------------------------------------------
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1

# -----------------------------------------------
# IPv6 RA acceptance
# With forwarding enabled the kernel defaults
# accept_ra to 0 on all interfaces, suppressing
# RA processing entirely. Two relevant values:
#
#   0 — do not process RAs. Correct for LAN and
#       all internal interfaces. Also correct for
#       Scenario B (static WAN) — no RAs expected
#       from ISP and accepting them would be a
#       security risk.
#
#   2 — process RAs even when forwarding is on.
#       Required on WAN for Scenario A and C where
#       the ISP sends RAs for gateway and prefix
#       discovery.
#
# On networkd-managed interfaces this sysctl has
# no effect — networkd bypasses the kernel RA
# stack entirely. IPv6AcceptRA= in the .network
# file is the correct knob there. These entries
# are set explicitly here for unmanaged interfaces
# and for auditability.
#
# Uncomment exactly one of the two WAN lines
# below depending on your scenario:
# -----------------------------------------------
net.ipv6.conf.<WAN>.accept_ra = 2   # Scenario A and C — ISP sends RAs
# net.ipv6.conf.<WAN>.accept_ra = 0 # Scenario B — static assignment, comment out line above and uncomment this
net.ipv6.conf.<LAN>.accept_ra = 0

# -----------------------------------------------
# IPv6 Privacy Extensions (RFC 3041)
# Controls temporary address generation:
#
#  <= 0 — disabled; interface uses only its stable
#          address (EUI-64 or assigned). Correct for
#          all router interfaces — predictable
#          addressing is required for a gateway.
#
#  == 1 — enabled, but public address preferred
#          over temporary addresses.
#
#   > 1 — enabled, temporary addresses preferred
#          over public addresses. Typical for
#          end-user client devices that benefit
#          from outbound address rotation.
#
# On a router/NGFW all interfaces should be <= 0.
# WAN in particular must be stable — ISP sessions,
# prefix delegation, and firewall state all tie to
# a consistent source address. Temporary addresses
# would cause session churn and unpredictable
# outbound NAT behaviour.
# -----------------------------------------------
net.ipv6.conf.all.use_tempaddr = 0
net.ipv6.conf.<WAN>.use_tempaddr = 0
net.ipv6.conf.<LAN>.use_tempaddr = 0

# -----------------------------------------------
# IPv6 DAD — per interface
# 1 probe (default); set to 0 on isolated static segments
# -----------------------------------------------
net.ipv6.conf.<WAN>.dad_transmits = 1
net.ipv6.conf.<LAN>.dad_transmits = 1

# -----------------------------------------------
# IPv6 NUD — NS retransmission interval per interface
# RFC 4861 default: 1000ms
# -----------------------------------------------
net.ipv6.conf.<WAN>.retrans_time_ms = 1000
net.ipv6.conf.<LAN>.retrans_time_ms = 1000

# -----------------------------------------------
# Hardening (Optional)
# The directives below have not been validated
# against this setup and are noted here for
# reference. Enable only after testing — incorrect
# values can silently break IPv6 connectivity.
# No native networkd directive exists for these.
# -----------------------------------------------
# net.ipv6.conf.all.accept_redirects = 0
# net.ipv6.conf.all.accept_source_route = 0
EOF

sysctl --system
```

---

## WAN Interface

Choose the scenario that matches your ISP's delivery method. Ensure the matching `accept_ra` line is active in `99-ngfw.conf` before or alongside applying the `.network` file.

---

### Scenario A — Dynamic (DHCPv4 + DHCPv6 Prefix Delegation)

Use when your ISP supports DHCPv6-PD and assigns addresses dynamically. The DHCPv6 client (prefix delegation hint, delegation handling, solicit behaviour) is configured separately — see the relevant file under `dhcp/`.

**`/etc/systemd/network/10-wan.network`**
```ini
[Match]
Name=<interface_name>

[Network]
DHCP=yes
IPv6AcceptRA=yes   # networkd userspace RA client; maps to kernel accept_ra=2 internally
```

> `IPv6AcceptRA=yes` is correct here even though forwarding is active. networkd runs its own userspace RA implementation — the kernel RA stack is always disabled on networkd-managed interfaces regardless of the `accept_ra` sysctl. `DHCP=yes` enables both DHCPv4 and the DHCPv6 client; combined with `IPv6AcceptRA=yes`, networkd processes the ISP RA for gateway/prefix discovery and simultaneously solicits DHCPv6 for prefix delegation.

---

### Scenario B — Static Assignment

Use when your ISP provides a fixed IP, gateway, and prefix. No RA processing is needed — ensure `net.ipv6.conf.<WAN>.accept_ra = 0` is active in `99-ngfw.conf` and `IPv6AcceptRA=` is omitted from this file (networkd defaults to no RA acceptance when not specified alongside static addresses).

**`/etc/systemd/network/10-wan.network`**
```ini
[Match]
Name=<interface_name>

[Network]
Address=1.2.3.4/24
Gateway=1.2.3.1
Address=2001:db8:100::2/64
Gateway=2001:db8:100::1
IPv6AcceptRA=no
#IPv6SendRA=yes #If enabling radvd on the interface
```

---

### Scenario C — SLAAC Only

Use when your ISP does not offer DHCPv6-PD and assigns a /64 via RA only. You will not receive a delegated prefix — LAN clients will need ULA or NPTv6 for IPv6 connectivity. See **ULA Fallback** below.

**`/etc/systemd/network/10-wan.network`**
```ini
[Match]
Name=<interface_name>

[Network]
DHCP=ipv4
IPv6AcceptRA=yes   # SLAAC only — no DHCPv6 client, RA provides gateway and /64
```

>> WARNING: if ip is not to be assigned via RA ,please set `IPv6AcceptRA=no`, because if RA is active on the link ,the default behaviour of systemd-networkd is to allow it
---

## LAN Interface

The LAN interface assigns the router's own addresses on the segment. networkd's role here is purely address assignment — equivalent to `ip addr add`. RA advertisement to downstream clients (prefix, M/O flags, DNS, lifetimes) is handled entirely by radvd. Addressing mode (Stateful / SLAAC / Hybrid) and DHCPv6 server interaction are configured in radvd and your DHCPv6 server — see [radvd-setup.md](radvd-setup.md) and the relevant file under `dhcp/`. NDP proxying for downstream addresses is handled by ndppd — see [ndppd-setup.md](ndppd-setup.md).

> The M flag in RAs signals clients to use stateful DHCPv6 (RFC 3315) for address assignment. The O flag signals stateless DHCPv6 (RFC 3736) for other configuration (DNS, NTP). Both are set in radvd, not networkd.

**`/etc/systemd/network/10-lan.network`**
```ini
[Match]
Name=<interface_name>

[Network]
Address=192.168.1.1/24
Address=2001:db1:100::1/64
```

---

## ULA Fallback (Recommended)

If prefix delegation fails or your ISP provides SLAAC-only with no PD, LAN clients will have no global IPv6 addresses. A ULA prefix provides stable internal IPv6 connectivity regardless of WAN state.

Add the router's ULA address to the `[Network]` block of whichever interface serves as your downstream segment — `10-lan.network`, or the relevant bond, bridge, or VLAN `.network` file if a virtual device is your LAN-facing interface:

```ini
Address=fd00:1:1::1/48        # ULA — RFC 4193 range
```

The corresponding ULA prefix advertisement to clients (`fd00:1:1::/64`, lifetimes, SLAAC flag) is configured in radvd alongside your global prefix block. See [radvd-setup.md](radvd-setup.md).

> Generate a unique ULA prefix with:
> `python3 -c "import os; r=os.urandom(5); print('fd{:02x}{:02x}:{:02x}{:02x}:{:02x}00::/48'.format(*r))"`

---

## Virtual Devices

networkd's role for virtual interfaces is the same as for physical ones — address assignment only. RA advertisement and prefix configuration is handled by radvd for all virtual interfaces; see [radvd-setup.md](radvd-setup.md).

When adding any virtual interface, add the following entries for it to `99-ngfw.conf` and run `sysctl --system`:

```bash
net.ipv4.conf.<IF>.rp_filter = 1      # strict for all internal interfaces
net.ipv6.conf.<IF>.accept_ra = 0      # internal interfaces never accept RAs
net.ipv6.conf.<IF>.use_tempaddr = 0
net.ipv6.conf.<IF>.dad_transmits = 1
net.ipv6.conf.<IF>.retrans_time_ms = 1000
```

> `rp_filter` on a bond master or bridge applies to traffic arriving on the virtual interface itself. Member interfaces (bond slaves, bridge ports) carry no IP and need no `rp_filter` entry.

---

### Bond

**`/etc/systemd/network/bond0.netdev`**
```ini
[NetDev]
Name=bond0
Kind=bond

[Bond]
Mode=802.3ad
MIIMonitorSec=1s
TransmitHashPolicy=layer3+4
```

**`/etc/systemd/network/10-bond0.network`**
```ini
[Match]
Name=bond0

[Network]
Address=192.168.30.1/24
Address=2001:db2:100::1/64
```

**`/etc/systemd/network/10-enp1s0.network`** (bond member)
```ini
[Match]
Name=enp1s0

[Network]
Bond=bond0
```

---

### Bridge

**`/etc/systemd/network/br0.netdev`**
```ini
[NetDev]
Name=br0
Kind=bridge
MACAddress=12:34:56:78:9a:bc   # pin MAC for stable link-local address

[Bridge]
STP=yes
```

**`/etc/systemd/network/10-br0.network`**
```ini
[Match]
Name=br0

[Network]
Address=192.168.20.1/24
Address=2001:db3:100::1/64
```

**`/etc/systemd/network/10-enp2s0.network`** (bridge port)
```ini
[Match]
Name=enp2s0

[Network]
Bridge=br0
```

---

### VLAN

**`/etc/systemd/network/vlan10.netdev`**
```ini
[NetDev]
Name=vlan10
Kind=vlan

[VLAN]
Id=10
```

**`/etc/systemd/network/10-vlan10.network`**
```ini
[Match]
Name=vlan10

[Network]
Address=10.10.10.1/24
Address=2001:db4:100::1/64
```

**`/etc/systemd/network/10-eth1.network`** (parent — declares VLAN membership)
```ini
[Match]
Name=<interface_name>

[Network]
VLAN=vlan10
```
>NOTE: You may append `VLAN=` to the `[Network]` section, alongside the current keys to maintain the old config alongside the vlan membership being declared.
---

## Apply and Verify

```bash
# Apply kernel parameters
sysctl --system

# Restart networkd to apply all .network changes
systemctl restart systemd-networkd

# Check interface and networkd status
networkctl list
networkctl status <interface_name>

# Check for unrecognised directives — warnings mean config is silently ignored
journalctl -u systemd-networkd --since "5 minutes ago" | grep -i warn

# Verify IP assignments
ip addr show
ip -6 addr show

# Verify routing table
ip route show
ip -6 route show

# Confirm RAs on LAN — ICMPv6 type 134 (sent by radvd)
tcpdump -i <interface_name> icmp6 -v

# Verify NDP neighbour table
ip -6 neighbour show
ip -6 neighbour show proxy    # if ndppd proxy entries are active

# Verify sysctl values took effect
sysctl net.ipv4.conf.<WAN>.rp_filter
sysctl net.ipv6.conf.<WAN>.forwarding
sysctl net.ipv6.conf.<WAN>.accept_ra
sysctl net.ipv6.conf.<WAN>.use_tempaddr
sysctl net.ipv6.conf.<LAN>.dad_transmits
sysctl net.ipv6.conf.<LAN>.accept_ra
```

---

## Common Issues

| Symptom | Likely Cause | Fix |
|---|---|---|
| No RAs on LAN | radvd not running or misconfigured | Check `systemctl status radvd` and `journalctl -u radvd` |
| IPv6 WAN address not assigned | `IPv6AcceptRA=` not set when forwarding is active | Set `IPv6AcceptRA=yes` on WAN for Scenario A and C |
| WAN processing spurious RAs (Scenario B) | `accept_ra = 2` left active for static WAN | Set `net.ipv6.conf.<WAN>.accept_ra = 0` in `99-ngfw.conf` and run `sysctl --system` |
| LAN clients get no address (stateful mode) | No DHCPv6 server running | Install `isc-kea-dhcp6-server` or switch to SLAAC mode in radvd |
| IPv6 config silently ignored | Multiple `.network` files matching same interface | Merge into single file per interface |
| PMTUD failures / large packets dropped | `packet-too-big` ICMPv6 blocked | Ensure nftables allows ICMPv6 type `packet-too-big` |
| Proxy NDP not working | ndppd not running or missing rule | Check `systemctl status ndppd` and [ndppd-setup.md](ndppd-setup.md) |
| rp_filter or forwarding not taking effect | sysctl not reloaded after edit | Run `sysctl --system`; verify with `sysctl net.ipv4.conf.<IF>.rp_filter` |
| Virtual interface sysctl entries missing | New virtual interface added without updating `99-ngfw.conf` | Add `rp_filter`, `accept_ra`, `use_tempaddr`, `dad_transmits`, `retrans_time_ms` entries for the new interface and run `sysctl --system` |

---

For further reference: [systemd.network documentation](https://www.freedesktop.org/software/systemd/man/latest/systemd.network.html)
