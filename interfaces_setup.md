# Interface Setup Guide

## Prerequisites

- Debian 13 (Trixie) — ships systemd 257
- `systemd-networkd` ≥ 257 — verify with `networkctl --version`
- A public IPv4/IPv6 address or ISP assignment
- A valid default route via your WAN interface
- For IPv6 routing: a delegated prefix (PD) or static block from your ISP


> **Older Debian notice:** If running Debian 11 (Bullseye, systemd 247) or Debian 12 (Bookworm, systemd 252), the directives `IPv4ReversePathFilter=` (added v255) and `IPv6Forwarding=` (added v256) are unavailable. See [Older Debian Fallback](#older-debian-fallback) at the end of this guide.

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

**Duplicate Address Detection (DAD)** runs automatically when an IPv6 address is assigned. The interface sends an NS for its own tentative address and listens for a conflicting NA before marking it valid. The number of DAD probes is configurable:

```ini
[Network]
IPv6DuplicateAddressDetection=1   # default — 1 probe; set to 0 to disable on isolated static segments
```

**Neighbor Unreachability Detection (NUD)** probes active neighbours periodically using NS/NA to detect and remove stale entries. The NS retransmission interval is configurable (RFC 4861 default is 1s):

```ini
[Network]
IPv6RetransmissionTimeSec=1s      # interval between retransmitted NS messages for DAD and NUD
```

**Hop Limit** is advertised to clients in RAs (RFC 4861 §6.2.1) and sets the default TTL for outgoing IPv6 packets on that segment:

```ini
[Network]
IPv6HopLimit=64                   # standard default; advertised to LAN clients via RA
```

**Proxy NDP** (RFC 4861 §7.2) allows the NGFW to answer NA messages on behalf of downstream addresses, making them appear reachable on an upstream link without a routing entry:

```ini
[Network]
IPv6ProxyNDP=yes
IPv6ProxyNDPAddress=2001:db8:1::100   # proxy NA for this address upstream
IPv6ProxyNDPAddress=2001:db8:1::101   # stack as many entries as needed
```

> **RA-Guard:** NDP is the primary attack surface for rogue router injection. The nftables baseline blocks unsolicited RAs from LAN ports at the host level. For switched environments, enable RA-Guard at the switch level (RFC 6105) in addition to the host firewall.

---

## Kernel Forwarding

The `sysctl.d` file handles global and hardening parameters only. Per-interface behaviour (`rp_filter`, `forwarding`, MTU, RA acceptance) is set directly in each `.network` file using native networkd directives — keeping interface config self-contained. Note that `accept_ra` sysctls are not needed for networkd-managed interfaces; see the comment in the file below.

Replace `<WAN>` and `<LAN>` with your actual interface names (e.g. `eth0`, `br0`).

```bash
cat <<EOF > /etc/sysctl.d/99-ngfw.conf
# --- IPv4 ---
net.ipv4.ip_forward = 1

# Global rp_filter baseline — disabled here, enforced per-interface
# via IPv4ReversePathFilter= in .network files
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0

# --- IPv6 ---
# all.forwarding=1 is sufficient; default ensures new interfaces inherit it
# Per-interface forwarding is controlled by IPv6Forwarding= in .network files
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1

# Note: accept_ra is NOT set here for networkd-managed interfaces.
# systemd-networkd runs a userspace RA implementation; the kernel's own
# RA stack is always disabled on managed interfaces regardless of the
# accept_ra sysctl. IPv6AcceptRA= in .network files controls RA acceptance
# entirely within networkd — IPv6AcceptRA=yes maps to kernel accept_ra=2
# internally. The sysctl only affects unmanaged interfaces.

# --- Hardening (no native networkd directive — must remain here) ---
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
EOF

sysctl --system
```

---

## WAN Interface

Choose the scenario that matches your ISP's delivery method.

---

### Scenario A — Dynamic (DHCPv4 + DHCPv6 Prefix Delegation)

Use when your ISP supports DHCPv6-PD and assigns addresses dynamically. Covered by RFC 8415 (extended, outside P11 scope).

**`/etc/systemd/network/10-wan.network`**
```ini
[Match]
Name=eth0

[Network]
DHCP=yes
IPv6AcceptRA=yes             # networkd userspace RA stack; maps to kernel accept_ra=2 internally
IPv6SendRA=no
IPv6PrivacyExtensions=no
IPv6Forwarding=yes           # per-interface IPv6 forwarding
IPv4ReversePathFilter=loose  # loose: ISP uplinks may route asymmetrically
IPv6MTUBytes=1280            # RFC 8200 §5 minimum; ensures PMTUD operates correctly (RFC 1981/8201)
IPv6HopLimit=64              # advertised to clients in RAs (RFC 4861 §6.2.1)
IPv6RetransmissionTimeSec=1s # NS retransmission interval for DAD and NUD (RFC 4861 default)

[DHCPv6]
PrefixDelegationHint=::/56   # request a /56; server may honour or ignore
UseDelegatedPrefix=yes        # automatically apply delegated prefix to downstream interfaces
WithoutRA=solicit             # do not wait for an RA before sending Solicit — required on many ISPs
```

> `IPv6AcceptRA=yes` is correct here even though forwarding is active. systemd-networkd runs its own userspace RA implementation — the kernel's RA stack is always disabled on networkd-managed interfaces regardless of the `accept_ra` sysctl. Internally, networkd maps `IPv6AcceptRA=yes` to kernel `accept_ra=2`. No manual sysctl override is needed.

> `IPv6SendRA=yes` implicitly enables `IPv6Forwarding=` on an interface unless explicitly set. It is set explicitly throughout this guide for clarity and auditability.

---

### Scenario B — Static Assignment

Use when your ISP provides a fixed IP, gateway, and prefix.

**`/etc/systemd/network/10-wan.network`**
```ini
[Match]
Name=eth0

[Network]
Address=1.2.3.4/24
Gateway=1.2.3.1
Address=2001:db8:100::2/64
Gateway=2001:db8:100::1
IPv6AcceptRA=no
IPv6SendRA=no
IPv6Forwarding=yes
IPv4ReversePathFilter=loose
IPv6MTUBytes=1280
IPv6HopLimit=64
IPv6RetransmissionTimeSec=1s
```

---

### Scenario C — SLAAC Only

Use when your ISP does not offer DHCPv6-PD and assigns a /64 via RA only.

**`/etc/systemd/network/10-wan.network`**
```ini
[Match]
Name=eth0

[Network]
DHCP=ipv4
IPv6AcceptRA=yes
IPv6SendRA=no
IPv6Forwarding=yes
IPv4ReversePathFilter=loose
IPv6MTUBytes=1280
IPv6HopLimit=64
IPv6RetransmissionTimeSec=1s
```

> With SLAAC-only you will not receive a delegated prefix. LAN clients will need ULA or NPTv6 for IPv6 connectivity. See **ULA Fallback** below.


---

## LAN Interface

The LAN interface distributes addresses and RAs to downstream clients. Choose one addressing mode based on your security requirements.

**`/etc/systemd/network/10-lan.network`** (common base — append chosen mode block below)
```ini
[Match]
Name=eth1

[Network]
Address=192.168.1.1/24
IPv6AcceptRA=no
IPv6SendRA=yes               # implicitly enables IPv6Forwarding= on this interface
IPv4ReversePathFilter=strict # known topology; enforce strictly
IPv6MTUBytes=1280
IPv6HopLimit=64
IPv6DuplicateAddressDetection=1
IPv6RetransmissionTimeSec=1s
```

Append **one** of the following mode blocks to the same file:

---

### Mode A — Stateful (DHCPv6 Managed)

Clients receive addresses only from a DHCPv6 server. SLAAC is disabled. Provides a full address audit trail.

> **Requirement:** You must run a DHCPv6 server (e.g. `isc-kea-dhcp6-server` or `dnsmasq`) on this interface. The M-flag in RAs instructs clients to use DHCPv6, but networkd does not include a server — without one, clients will solicit and receive no response.

```ini
[IPv6SendRA]
Managed=yes
OtherInformation=yes
RouterLifetimeSec=1800
DNS=2001:db8:1::53

[IPv6Prefix]
Prefix=2001:db8:1::/64
OnLink=yes
AddressAutoconfiguration=no  # M-flag set; SLAAC disabled on this prefix
ValidLifetimeSec=3600
PreferredLifetimeSec=1800
```

---

### Mode B — Stateless (SLAAC)

Clients self-assign addresses via SLAAC (RFC 4862). No DHCPv6 server required.

```ini
[IPv6SendRA]
Managed=no
OtherInformation=yes
RouterLifetimeSec=1800

[IPv6Prefix]
Prefix=2001:db8:1::/64
OnLink=yes
AddressAutoconfiguration=yes
ValidLifetimeSec=3600
PreferredLifetimeSec=1800
```

---

### Mode C — Hybrid (SLAAC + DHCPv6)

Advertises both SLAAC and DHCPv6. Maximises client compatibility. Requires a DHCPv6 server for the managed portion.

```ini
[IPv6SendRA]
Managed=yes
OtherInformation=yes
RouterLifetimeSec=1800

[IPv6Prefix]
Prefix=2001:db8:1::/64
OnLink=yes
AddressAutoconfiguration=yes
ValidLifetimeSec=3600
PreferredLifetimeSec=1800
```

---

## ULA Fallback (Recommended)

If prefix delegation fails or your ISP provides SLAAC-only with no PD, LAN clients will have no global IPv6 addresses. A ULA prefix provides stable internal IPv6 connectivity regardless of WAN state.

Add to the `[Network]` block in `/etc/systemd/network/10-lan.network`:
```ini
Address=fd00:1:1::1/48        # ULA — RFC 4193 range
```

Add a second `[IPv6Prefix]` block alongside your chosen mode's prefix:
```ini
[IPv6Prefix]
Prefix=fd00:1:1::/64
OnLink=yes
AddressAutoconfiguration=yes
ValidLifetimeSec=7200
PreferredLifetimeSec=3600
```

> Generate a unique ULA prefix with:
> `python3 -c "import os; r=os.urandom(5); print('fd{:02x}{:02x}:{:02x}{:02x}:{:02x}00::/48'.format(*r))"`

---

## Virtual Devices
>Note: For specific mode setup refer previous sections
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
IPv6AcceptRA=no
IPv6SendRA=yes
IPv4ReversePathFilter=strict
IPv6MTUBytes=1280
IPv6HopLimit=64
IPv6DuplicateAddressDetection=1
IPv6RetransmissionTimeSec=1s

[IPv6SendRA]
Managed=no
OtherInformation=yes
RouterLifetimeSec=1800

[IPv6Prefix]
Prefix=2001:db8:30::/64
OnLink=yes
AddressAutoconfiguration=yes
ValidLifetimeSec=3600
PreferredLifetimeSec=1800
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
IPv6AcceptRA=no
IPv6SendRA=yes
IPv4ReversePathFilter=strict
IPv6MTUBytes=1280
IPv6HopLimit=64
IPv6DuplicateAddressDetection=1
IPv6RetransmissionTimeSec=1s

[IPv6SendRA]
Managed=no
OtherInformation=yes
RouterLifetimeSec=1800

[IPv6Prefix]
Prefix=2001:db8:20::/64
OnLink=yes
AddressAutoconfiguration=yes
ValidLifetimeSec=3600
PreferredLifetimeSec=1800
```

**`/etc/systemd/network/10-enp2s0.network`** (bridge port — distinct filename from bond member)
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
IPv6AcceptRA=no
IPv6SendRA=yes
IPv4ReversePathFilter=strict
IPv6MTUBytes=1280
IPv6HopLimit=64
IPv6DuplicateAddressDetection=1
IPv6RetransmissionTimeSec=1s

[IPv6SendRA]
Managed=no
OtherInformation=yes
RouterLifetimeSec=1800

[IPv6Prefix]
Prefix=2001:db8:10::/64
OnLink=yes
AddressAutoconfiguration=yes
ValidLifetimeSec=3600
PreferredLifetimeSec=1800
```

**`/etc/systemd/network/10-eth1.network`** (parent — declares VLAN membership)
```ini
[Match]
Name=eth1

[Network]
VLAN=vlan10
```


---

## Apply and Verify

```bash
# Apply kernel parameters
sysctl --system

# Restart networkd to apply all .network changes
systemctl restart systemd-networkd

# Check interface and networkd status
networkctl list
networkctl status eth0
networkctl status eth1

# Check for unrecognised directives — warnings mean config is silently ignored
journalctl -u systemd-networkd --since "5 minutes ago" | grep -i warn

# Verify IP assignments
ip addr show
ip -6 addr show

# Verify routing table
ip route show
ip -6 route show

# Confirm RAs on LAN — look for ICMPv6 type 134 (Router Advertisement) to ff02::1
tcpdump -i eth1 icmp6 -v

# Verify NDP neighbour table
ip -6 neighbour show
ip -6 neighbour show proxy    # if IPv6ProxyNDP= is in use
```

---

## Common Issues

| Symptom | Likely Cause | Fix |
|---|---|---|
| No RAs on LAN | Wrong directives in `[IPv6SendRA]` or missing `[IPv6Prefix]` | Check `journalctl -u systemd-networkd` for warnings |
| IPv6 WAN address not assigned | `IPv6AcceptRA=` auto-disabled when `IPv6Forwarding=` or `IPv6SendRA=` is active | Explicitly set `IPv6AcceptRA=yes` on WAN — networkd maps this to `accept_ra=2` internally |
| DHCPv6-PD never solicits | Missing `WithoutRA=solicit` | Add to `[DHCPv6]` section |
| LAN clients get no address (Mode A) | No DHCPv6 server running | Install `isc-kea-dhcp6-server` or switch to Mode B |
| IPv6 config silently ignored | Multiple `.network` files matching same interface | Merge into single file per interface |
| PMTUD failures / large packets dropped | `packet-too-big` ICMPv6 blocked | Ensure nftables allows ICMPv6 type `packet-too-big` |

---

## Older Debian Fallback

> **This section applies only to Debian 11 (Bullseye / systemd 247) or Debian 12 (Bookworm / systemd 252).** Debian 13 (Trixie / systemd 257) users do not need this — all directives used in this guide are natively supported.

Two directives used throughout this guide are unavailable on older systemd versions:

| Directive | Added in | Available from |
|---|---|---|
| `IPv4ReversePathFilter=` | v255 | Debian 13+ |
| `IPv6Forwarding=` | v256 | Debian 13+ |
| `IPv6RetransmissionTimeSec=` | v256 | Debian 13+ |

Remove these directives from all `.network` files and add the following per-interface entries to `/etc/sysctl.d/99-ngfw.conf` instead:

```bash
# Per-interface rp_filter (replaces IPv4ReversePathFilter= in .network files)
net.ipv4.conf.<WAN>.rp_filter = 0   # equivalent to loose on WAN
net.ipv4.conf.<LAN>.rp_filter = 1   # equivalent to strict on LAN

# Per-interface IPv6 forwarding (replaces IPv6Forwarding= in .network files)
net.ipv6.conf.<WAN>.forwarding = 1
net.ipv6.conf.<LAN>.forwarding = 1

# NS retransmission interval (replaces IPv6RetransmissionTimeSec= in .network files)
net.ipv6.conf.<WAN>.retrans_time_ms = 1000
net.ipv6.conf.<LAN>.retrans_time_ms = 1000
```

All other directives in this guide are supported from systemd 257 onwards.

---

For further reference: [systemd.network documentation](https://www.freedesktop.org/software/systemd/man/latest/systemd.network.html)
