# IPv6 Prefix Proxying with ndppd and radvd

## Overview

This guide explains how to configure **ndppd** and **radvd** when your ISP provides only a **single IPv6 /64** and does **not** support DHCPv6 Prefix Delegation (DHCPv6-PD).

Instead of routing a separate subnet, the router proxies Neighbor Discovery Protocol (NDP) between the WAN and LAN. This allows LAN devices to receive globally routable IPv6 addresses from the ISP's /64 using SLAAC.

---

# Assign an IPv6 Address to the LAN Interface

The LAN interface must have an address from the ISP-assigned prefix.

This address is used as:

* The default gateway for LAN clients
* The source address for Router Advertisements
* The DNS server (if advertised)

---

# Configure radvd

Configuration file:

```text
/etc/radvd.conf
```

Example:

```conf
interface <iface_name> {
    AdvSendAdvert on;
    prefix <prefix_to_be_distributed> {
    };
    RDNSS <ip_of_advertised_dns> {
    };
};
```

# Configure ndppd

Configuration file:

```text
/etc/ndppd.conf
```

Example:

```conf
route-ttl 30000
address-ttl 30000

proxy <wan_interface> {
    router yes
    timeout 500
    ttl 30000
    promiscuous yes

    rule <prefix>::<length_of_prefix> {
        iface <lan_interface>
    }
}
```

---

# Start the Services

```bash
systemctl enable ndppd
systemctl restart ndppd

systemctl enable radvd
systemctl restart radvd
```

---