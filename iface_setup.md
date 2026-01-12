Interface Registration — WAN & LAN (nftables)
=============================================

**Purpose:** Register physical interfaces in the appropriate nftables sets so the rules (masquerade, geofence, captive portal, webfilter, forward logic) know which ports are WAN and which are LAN.

> **Note:** These commands **add elements** to pre-existing sets. Make sure those sets exist in your nftables configuration before running the `add element` commands.

* * *

To be run when a WAN interface is configured
--------------------------------------------

**Purpose:** Add your Internet-facing interfaces (e.g. `eth0`, `ppp0`) to the `filter`, `nat`, and `geo` sets so NAT, forwarding, and geofencing behave correctly.

```
# Add WAN interfaces to the filter table (used by forwarding rules)
nft add element inet filter wan_ifaces { "<wan_iface1>", "<wan_iface2>" }

# Add WAN interfaces to the nat table (used by masquerade / SNAT)
nft add element inet nat wan_ifaces { "<wan_iface1>", "<wan_iface2>" }

# Add WAN interfaces to the geo table (used by geofencing checks)
nft add element inet geo wan_ifaces { "<wan_iface1>", "<wan_iface2>" }
```

* * *

To be run when a LAN interface is configured
--------------------------------------------

**Purpose:** Register local network interfaces so the firewall can treat internal traffic correctly (forwarding, captive portal interception, webfilter NFQUEUE).

```
# Register LAN interfaces in the filter table (forward/whitelists)
nft add element inet filter lan_ifaces { "<lan_iface1>", "<lan_iface2>" }

# Register LAN interfaces in the nat table (captive portal logic)
nft add element inet nat lan_ifaces { "<lan_iface1>", "<lan_iface2>" }

# Register LAN interfaces for webfilter/NFQUEUE inspection (internal-only web traffic)
nft add element inet webfilter lan_ifaces { "<lan_iface1>", "<lan_iface2>" }
```

* * *