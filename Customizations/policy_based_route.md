Policy-Based Relay Routing Module (Linux `ip route`)
====================================================

Purpose
-------

This module implements **forced next-hop routing** for:

*   relayed subnets,
*   downstream switches,
*   L3 hops behind intermediate gateways,

It is used when traffic **must pass through a specific L3 device** before reaching its final destination.

* * *

Core Command
------------

```bash
ip route add <relayed_subnet_or_ip> \
    via <switch_ip_or_gateway_ip> \
    dev <egress_iface>
```
> NOTE : This commands shall be ran for all the routing tables like this

```
ip route add <relayed_subnet_or_ip> \
    via <switch_ip_or_gateway_ip> \
    dev <egress_iface> table <isp_table_id>
```
* * *

What This Rule Actually Does
----------------------------

This creates a **destination-specific route** that:

*   Matches packets whose **destination** is `<relayed_subnet_or_ip>`
*   Forces them to be sent to a **specific next hop**
*   Bypasses default routing decisions


Parameter Breakdown
-------------------

| Field | Meaning |
| --- | --- |
| `<relayed_subnet_or_ip>` | Target network or host |
| `via <gateway_ip>` | Mandatory next-hop router |
| `dev <egress_iface>` | Interface used to reach gateway |

### Example

```bash
ip route add 10.50.0.0/16 via 192.168.1.2 dev lan0
```

**Meaning:**

> Any traffic going to `10.50.0.0/16` must be forwarded through `192.168.1.2`.

Design Rules (Non-Negotiable)
-----------------------------

1.  Gateway (via keyword in commands) must be **directly reachable**
2.  Interface must be **UP**
3.  Return path must exist