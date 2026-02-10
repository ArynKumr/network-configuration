# Route rules

## Adding a Default Gateway to Multiple Tables

A default gateway can be added to a non-main routing table while still using DHCP.
In this example, the interface `enp8s0` receives its address via DHCP, but a default route is also installed into routing table `100`.

```
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

We must set the metric and priority manually (both can be same, not an issue). It must be unique for each interface's gateway.

This results in:

- Main table: default route from DHCP
- Table 100: a duplicate default route pointing to the same DHCP gateway
- In fwmark, 0x00<2_BYTES_ISP_MARK>0000. Here the 2 bytes define the ISP mark.

> Note: in our case, we are defining that different interface gets different ISP. <br>
> Therefore, each ISP's interface here must have its own fwmark and `[Route]` Section as explained above. <br>

It is also to be noted that we must add all the other routes manually if required (see next section) Since they are not added automatically.
Example:
```bash
root@localhost:/etc/systemd/network# ip r
default via 10.9.0.1 dev enp8s0 proto dhcp src 10.9.0.4 metric 200 
8.8.8.8 via 10.9.0.1 dev enp8s0 proto dhcp src 10.9.0.4 metric 200 
10.9.0.1 dev enp8s0 proto dhcp scope link src 10.9.0.4 metric 200 
10.10.0.0/24 via 10.9.0.1 dev enp8s0 proto static metric 200 onlink 

root@localhost:/etc/systemd/network# ip r show table 69
default via 10.9.0.1 dev enp8s0 proto dhcp metric 300 
10.10.0.0/24 via 10.9.0.1 dev enp8s0 proto static metric 200 onlink 
root@localhost:/etc/systemd/network# 


```

---

## Adding Specific Routes to Multiple Tables

Specific network routes can be installed into multiple routing tables by defining multiple `[Route]` blocks.

Example: adding the network `10.10.0.0/24` to both table `100`, table `200` and the main table.

```
[Route]
Destination=10.10.0.0/24
Gateway=10.9.0.1
Table=100
Metric=200

[Route]
Destination=10.10.0.0/24
Gateway=10.9.0.2
Table=200
Metric=200

[Route]
Destination=10.10.0.0/24
Gateway=10.9.0.2
Table=main
Metric=200
```

This creates identical routes in multiple tables, allowing:

* Normal traffic to use the main table
* Policy-routed traffic to use table 100

> Note: Here, we must define `[Route]` section for each table which requires it.<br>
> For example, here we want it so 10.10.10.0/24 must be accessible via the tables 100 and 200.