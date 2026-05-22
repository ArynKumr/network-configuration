# Configuring Interfaces in radvd

## Example Configuration

```conf
interface <iface_name> {
    AdvSendAdvert on;

    prefix <prefix_to_be_distributed> {
    };

    RDNSS <ip_of_advertised_dns> {
    };
};
```

# OR

```conf
interface <iface1_name> {
    AdvSendAdvert on;

    prefix <prefix_to_be_distributed> {
    };

    RDNSS <ip_of_advertised_dns> {
    };
};

interface <iface2_name> {
    AdvSendAdvert on;

    prefix <prefix_to_be_distributed> {
    };

    RDNSS <ip_of_advertised_dns> {
    };
};

interface <iface3_name> {
    AdvSendAdvert on;

    prefix <prefix_to_be_distributed> {
    };

    RDNSS <ip_of_advertised_dns> {
    };
};
```

---

# How It Works

Each `interface` block:

* Sends IPv6 Router Advertisements (RA)
* Advertises a unique IPv6 prefix
* Optionally advertises DNS servers using `RDNSS`
* Operates independently from the others

You can define as many interfaces as needed.

---

# Important Rule

Do NOT advertise the same `/64` prefix on multiple routed interfaces.

Correct:

| Interface | Prefix          |
| --------- | --------------- |
| enp1s0    | 2001:db8:1::/64 |
| enp2s0    | 2001:db8:2::/64 |
| br0       | 2001:db8:3::/64 |

Wrong:

| Interface | Prefix          |
| --------- | --------------- |
| enp1s0    | 2001:db8:1::/64 |
| enp2s0    | 2001:db8:1::/64 |

Using the same prefix on multiple L3 interfaces breaks routing unless the interfaces are bridged into the same Layer-2 domain.

---

# Assign IPv6 Addresses to Interfaces

The router itself must own an address inside each advertised subnet.

Example:

```bash
ip -6 addr add 2001:db8:1::1/64 dev enp1s0
ip -6 addr add 2001:db8:2::1/64 dev enp2s0
ip -6 addr add 2001:db8:3::1/64 dev br0
```

---

# Restart radvd

```bash
systemctl restart radvd
```

Check status:

```bash
systemctl status radvd
```

---

# Example Real-World Topology

```text
                Router
        +-------------------+
        |                   |
        | enp1s0 -> LAN A   | 2001:db8:1::/64
        | enp2s0 -> LAN B   | 2001:db8:2::/64
        | br0     -> WiFi   | 2001:db8:3::/64
        +-------------------+
```

Each network gets:

* Its own `/64`
* Its own SLAAC advertisements
* Independent IPv6 routing

---
