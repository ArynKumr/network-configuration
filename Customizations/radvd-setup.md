# Configuring Interfaces in radvd

> **radvd** (Router Advertisement Daemon) sends IPv6 Router Advertisements (RA) to clients on your network, enabling stateless address autoconfiguration (SLAAC).

---

## Prerequisites

Before you begin, make sure you have:

- [ ] `radvd` installed on your device
- [ ] Unique `/64` IPv6 prefixes allocated per interface

---

## How It Works

Each `interface` block in `radvd.conf` operates independently. For every configured interface, radvd will:

- Send periodic IPv6 Router Advertisements
- Advertise a unique IPv6 prefix (enabling SLAAC for clients)
- Optionally advertise DNS resolvers via `RDNSS`

You can define as many interface blocks as needed — one per routed segment.

---

## Write the Configuration

Edit `/etc/radvd.conf` and add one block per interface. Add or remove blocks to match the number of segments in your network:

```conf
interface <iface1_name> {
    AdvSendAdvert on;
    prefix <prefix_to_be_distributed> {
    };
    RDNSS <ip_of_advertised_dns> {
    };
};

# interface <iface2_name> {
#     AdvSendAdvert on;
#     prefix <prefix_to_be_distributed> {
#     };
#     RDNSS <ip_of_advertised_dns> {
#     };
# };

# interface <iface3_name> {
#     ...
# };
```

> Uncomment and duplicate blocks as needed — one per routed segment.

### radvd example — Stateful (DHCPv6)
### For DHCP Specific instances 

```
interface <iface_name> {
    AdvSendAdvert on;
    AdvManagedFlag on;       # M=1  → use DHCPv6 for addresses
    AdvOtherConfigFlag on;   # O=1  → use DHCPv6 for options
    prefix <prefix_to_be_distributed> {
        AdvAutonomous off;   # disable SLAAC
    };
};
```

### radvd example — Stateless (SLAAC + DHCPv6 options)

```
interface <iface_name> {
    AdvSendAdvert on;
    AdvManagedFlag off;      # M=0  → addresses via SLAAC
    AdvOtherConfigFlag on;   # O=1  → options via DHCPv6
    prefix <prefix_to_be_distributed> {
        AdvAutonomous on;    # enable SLAAC
    };
};
```

### radvd example — Hybrid (SLAAC + IA_NA available)

```
interface <iface_name> {
    AdvSendAdvert on;
    AdvManagedFlag on;       # M=1  → DHCPv6 addresses for clients that request them
    AdvOtherConfigFlag on;   # O=1  → options via DHCPv6
    prefix <prefix_to_be_distributed> {
        AdvAutonomous on;    # SLAAC still available for non-DHCPv6 clients
    };
};

---

## Assign Router Addresses to Each Interface

The router itself must hold an address inside every subnet it advertises. Clients use the router's address as their default gateway.

```bash
sudo ip -6 addr add 2001:db8:1::1/64 dev enp1s0
sudo ip -6 addr add 2001:db8:2::1/64 dev enp2s0
sudo ip -6 addr add 2001:db8:3::1/64 dev br0
```

> These assignments are ephemeral by default. To make them persistent, add them to your network manager config (Netplan, NetworkManager, systemd-networkd, etc.).

---

## Start & Enable radvd

```bash
# Apply the configuration
sudo systemctl restart radvd

# Enable radvd to start on boot
sudo systemctl enable radvd
```

**Verify it's running:**

```bash
systemctl status radvd
```

---

## Real-World Topology Example

```
              Router
      +----------------------+
      |                      |
      |  enp1s0  →  LAN A   |  <prefix_to_be_distributed>
      |  enp2s0  →  LAN B   |  2001:db8:2::/64
      |  wlan0     →  WiFi    |  2001:db8:3::/64
      +----------------------+
```

Each segment gets its own `/64`, its own SLAAC advertisements, and independent IPv6 routing.

---

## ⚠️ Critical: Never Reuse a Prefix Across Routed Interfaces

Advertising the same `/64` on multiple Layer-3 interfaces breaks routing. Each routed interface **must** have a unique prefix.

**✅ Correct:**

| Interface | Prefix |
|---|---|
| `enp1s0` | `<prefix_to_be_distributed>` |
| `enp2s0` | `2001:db8:2::/64` |
| `wlan0` | `2001:db8:3::/64` |

**❌ Wrong:**

| Interface | Prefix |
|---|---|
| `enp1s0` | `<prefix_to_be_distributed>` |
| `enp2s0` | `<prefix_to_be_distributed>` |

> **Exception:** Interfaces that are bridged into the same Layer-2 domain (e.g., two ports on the same bridge) may share a prefix, since they are logically one segment.

---

## Troubleshooting

**radvd fails to start?**
→ Check the config for syntax errors: `radvd -c /etc/radvd.conf`

**Clients not getting addresses?**
→ Confirm the router has an address in the advertised prefix: `ip -6 addr show dev <iface>`
**Routing broken after adding a second interface?**
→ Check for duplicate prefixes across your interface blocks.

---

## Further Reading

- [radvd man page](https://linux.die.net/man/8/radvd)
- [RFC 4861 — Neighbor Discovery for IP version 6](https://www.rfc-editor.org/rfc/rfc4861)
- [RFC 4862 — IPv6 Stateless Address Autoconfiguration](https://www.rfc-editor.org/rfc/rfc4862)
