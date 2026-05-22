# Route Rules

## Adding a Default Gateway to Multiple Tables (DHCP)

A default gateway can be added to a non-main routing table while still using DHCP.
In this example, the interface `enp8s0` receives its address via DHCP, but a default route is also installed into routing table `100`.

### IPv4

```ini
[Match]
Name=enp8s0

[Network]
DHCP=yes

[DHCP]
UseRoutes=yes
RouteMetric=200

[Route]
Destination=0.0.0.0/0
Gateway=_dhcp4
Table=100
Metric=200

[RoutingPolicyRule]
FirewallMark=0x00a10000/0x00ff0000
Table=100
Priority=1000
```

### IPv6

```ini
[Match]
Name=enp8s0

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCP]
UseRoutes=yes
RouteMetric=200

[IPv6AcceptRA]
UseAutonomousPrefix=yes
UseOnLinkPrefix=yes

[Route]
Destination=::/0
Gateway=_ipv6ra
Table=100
Metric=200

[RoutingPolicyRule]
Family=ipv6
FirewallMark=0x00a10000/0x00ff0000
Table=100
Priority=1000
```

We must set the metric and priority manually (both can be same, not an issue). It must be unique for each interface's gateway.

This results in:

- **Main table:** default route from DHCP (IPv4) / RA (IPv6)
- **Table 100:** a duplicate default route pointing to the same DHCP/RA gateway
- In fwmark, `0x00<1_BYTE_ISP_MARK>0000/0x00ff0000`. The 1 byte (bits 16–23) defines the ISP mark.

> **Note:** In our case, we are defining that different interfaces get different ISPs.
> Therefore, each ISP's interface must have its own fwmark and `[Route]` section as explained above.

> **Note (IPv6):** `Gateway=_ipv6ra` instructs systemd-networkd to use the default gateway learned from Router Advertisements. This requires `IPv6AcceptRA=yes` in the `[Network]` section. The `[RoutingPolicyRule]` block must also include `Family=ipv6` to correctly match IPv6 packets.

> **Note:** All other routes must be added manually if required (see next section), since they are not added automatically.

**Example output:**

```bash
# --- IPv4 ---

[root@localhost]:/etc/systemd/network# ip r
default via 10.9.0.1 dev enp8s0 proto dhcp src 10.9.0.4 metric 200
8.8.8.8 via 10.9.0.1 dev enp8s0 proto dhcp src 10.9.0.4 metric 200
10.9.0.1 dev enp8s0 proto dhcp scope link src 10.9.0.4 metric 200
10.10.0.0/24 via 10.9.0.1 dev enp8s0 proto static metric 200 onlink

[root@localhost]:/etc/systemd/network# ip r show table 100
default via 10.9.0.1 dev enp8s0 proto dhcp metric 200
10.10.0.0/24 via 10.9.0.1 dev enp8s0 proto static metric 200 onlink

# Verify the RPDB (policy rule) is installed:
[root@localhost]:/etc/systemd/network# ip rule show
0:      from all lookup local
1000:   from all fwmark 0xa10000/0xff0000 lookup 100
32766:  from all lookup main
32767:  from all lookup default

# --- IPv6 ---

[root@localhost]:/etc/systemd/network# ip -6 r
default via fe80::1 dev enp8s0 proto ra metric 200 pref medium
fe80::/64 dev enp8s0 proto kernel metric 200 pref medium

[root@localhost]:/etc/systemd/network# ip -6 r show table 100
default via fe80::1 dev enp8s0 proto ra metric 200

# Verify the IPv6 RPDB rule:
[root@localhost]:/etc/systemd/network# ip -6 rule show
0:      from all lookup local
1000:   from all fwmark 0xa10000/0xff0000 lookup 100
32766:  from all lookup main
```

---

## Adding Specific Routes to Multiple Tables

Specific network routes can be installed into multiple routing tables by defining multiple `[Route]` blocks.

### IPv4

Example: adding the network `10.10.0.0/24` to both table `100`, table `200` and the main table.

```ini
# The interface must always match the Gateway.
[Match]
Name=enp8s0

# Equivalent to: ip route add 10.10.0.0/24 via 10.9.0.1 dev enp8s0 table 100 metric 200
[Route]
Destination=10.10.0.0/24
Gateway=10.9.0.1
Table=100
Metric=200

# Equivalent to: ip route add 10.10.0.0/24 via 10.9.0.2 dev enp8s0 table 200 metric 200
[Route]
Destination=10.10.0.0/24
Gateway=10.9.0.2
Table=200
Metric=200

# Equivalent to: ip route add 10.10.0.0/24 via 10.9.0.2 dev enp8s0 metric 200
[Route]
Destination=10.10.0.0/24
Gateway=10.9.0.2
Table=main
Metric=200
```

### IPv6

Example: adding the network `2001:db8:1::/48` to table `100`, table `200`, and the main table.

```ini
# The interface must always match the Gateway.
[Match]
Name=enp8s0

# Equivalent to: ip -6 route add 2001:db8:1::/48 via fe80::1 dev enp8s0 table 100 metric 200
[Route]
Destination=2001:db8:1::/48
Gateway=fe80::1
Table=100
Metric=200

# Equivalent to: ip -6 route add 2001:db8:1::/48 via fe80::2 dev enp8s0 table 200 metric 200
[Route]
Destination=2001:db8:1::/48
Gateway=fe80::2
Table=200
Metric=200

# Equivalent to: ip -6 route add 2001:db8:1::/48 via fe80::2 dev enp8s0 metric 200
[Route]
Destination=2001:db8:1::/48
Gateway=fe80::2
Table=main
Metric=200
```

> **Note (IPv6):** IPv6 link-local addresses (e.g., `fe80::1`) are the typical next-hop for IPv6 routes learned via Router Advertisements. Always verify the correct link-local gateway using `ip -6 neigh` or `rdisc6 enp8s0` before hardcoding a gateway address.

This creates identical routes in multiple tables, allowing:

- Normal traffic to use the main table
- Policy-routed traffic to use table 100

> **Note:** A `[Route]` section must be defined for each table that requires it.
> For example, `10.10.0.0/24` (IPv4) and `2001:db8:1::/48` (IPv6) must be accessible via tables 100 and 200.
> Make sure that the metric is unique in each `.network` file.

> **Note:** All routes reachable via an interface must be added to every routing table. Otherwise, VPN traffic may fail to reach certain destinations. For example, if a VPN user is assigned to ISP 1, they will only be able to access the routes present in ISP 1's routing table. Including the full set of routes in each ISP's table ensures consistent accessibility regardless of which ISP a VPN user is mapped to.

> **⚠️ IPv6 VPN Testing Pending:** Multi-table routing behaviour for IPv6 has not yet been fully validated in a VPN scenario. Testing of IPv6 policy routing with VPN-assigned clients (analogous to the IPv4 ISP-mapping behaviour described above) is still pending. Proceed with caution and verify routing table population with `ip -6 route show table <N>` after configuration.
