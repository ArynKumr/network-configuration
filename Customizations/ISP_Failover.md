* * *

ISP Failover Using fwmark-Based Policy Routing
==============================================

Goal
----

Ensure that traffic **marked for ISP-1** (`fwmark 0x00<isp1_mark>0000/0x00ff0000`) is **automatically rerouted via ISP-2** when ISP-1 becomes unavailable — **without changing nftables rules or user marks**.

* * *

Normal (Healthy) State
----------------------

Each ISP has its own routing table.

### Policy Rules

```
ip rule add fwmark 0x00<isp1_mark>0000 lookup <isp1_table_id>
ip rule add fwmark 0x00<isp2_mark>0000 lookup <isp2_table_id>
```

### Meaning

| Mark | Routing Table | Effect |
| --- | --- | --- |
| `0x00<isp1_mark>0000` | `<isp1_table_id>` | Traffic exits via ISP-1 |
| `0x00<isp2_mark>0000` | `<isp2_table_id>` | Traffic exits via ISP-2 |

*   Marks are usually applied in **nftables (mangle)**
*   Routing decision happens **after marking**
*   Each table has its own default gateway

* * *

Failure Scenario
----------------

**ISP-1 goes down**, but:

*   traffic is still marked `0x00<isp1_mark>0000`
*   routing table `<isp1_table_id>` is now broken

If nothing changes:

*   packets are still sent to ISP-1
*   connections blackhole
*   kernel does NOT auto-failover

Linux **will not save you** here.

* * *

Failover Action (Manual / Scripted)
-----------------------------------

### Step 1: Remove the Broken Rule

```
ip rule del fwmark 0x00<isp1_mark>0000 lookup <isp1_table_id>
```

This immediately prevents traffic marked `0x00<isp1_mark>0000` from being routed via ISP-1.

* * *

### Step 2: Rebind Mark to Backup ISP

```
ip rule add fwmark 0x00<isp1_mark>0000 lookup <isp2_table_id>
```

Now:

| Mark | Routing Table |
| --- | --- |
| `0x00<isp1_mark>0000` | `<isp2_table_id>` |
| `0x00<isp2_mark>0000` | `<isp2_table_id>` |

All traffic — including users originally assigned to ISP-1 — exits via ISP-2.

* * *

Key Design Principle
--------------------

> **Marks do not change.  
> Routing interpretation of marks does.**

* * *

Recovery (Failback)
-------------------

When ISP-1 comes back:

```
ip rule del fwmark 0x00<isp1_mark>0000 lookup <isp2_table_id>
ip rule add fwmark 0x00<isp1_mark>0000 lookup <isp1_table_id>
```

Traffic immediately reverts.

* * *

REQUIRED Supporting Pieces (Non-Optional)
-----------------------------------------

To make this reliable, you must also have:

> [How to configure routing tables](route_rule_setup.md)

### 1\. Per-ISP Routing Tables

```
ip route add default via <isp1_gateway> dev <isp_iface> table <isp1_table_id>
ip route add default via <isp2_gateway> dev <isp_iface> table <isp2_table_id>
```

* * *
### 2\. SNAT Alignment (Critical)

If users marked `0x00<isp1_mark>0000` are SNATed to **ISP-1 public IPs**:

> [How to configure SNAT ](SNAT_setup.md) (although it is expected that if an ISP goes down the SNAT will fail to work) 

*   you MUST also switch SNAT rules
*   or temporarily SNAT them to ISP-2 IPs
*   otherwise traffic will exit ISP-2 with ISP-1 source IP → dropped upstream


* * *

Recommended Production Pattern
------------------------------

| Component | Failover Action |
| --- | --- |
| fwmark → ip rule | remap mark |
| SNAT maps | switch pools |
| QoS | unchanged |
| nftables | unchanged |
| Users | unaware |

* * *

One-Line Summary
----------------

> ISP failover is achieved by **repointing fwmark-based routing rules**, not by changing packet marks — when ISP-1 dies, you simply tell the kernel: “mark `0x00<isp1_mark>0000` now means ISP-2.”