
# ISP Failover Using fwmark-Based Policy Routing

Goal
----

Ensure that traffic **marked for ISP-1** (`fwmark 0x00<isp1_mark>0000/0x00ff0000`) is **automatically rerouted via ISP-2** when ISP-1 becomes unavailable — **without changing nftables rules or user marks**.

* * *

Normal (Healthy) State

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

*   Marks are applied in **nftables (mangle)**
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

* * *

Failover Action (Manual / Scripted)
-----------------------------------

### Step 1: Remove the Rule

```
ip rule del fwmark 0x00<isp1_mark>0000 lookup <isp1_table_id> priority <prio>
```

This immediately prevents traffic marked `0x00<isp1_mark>0000` from being routed via ISP-1.

* * *

### Step 2: Rebind Mark to Backup ISP

```
ip rule add fwmark 0x00<isp1_mark>0000 lookup <isp2_table_id> priority <prio> priority <prio>
```

Now:

| Mark | Routing Table |
| --- | --- |
| `0x00<isp1_mark>0000` | `<isp2_table_id>` |
| `0x00<isp2_mark>0000` | `<isp2_table_id>` |

All traffic — including users originally assigned to ISP-1 — exits via ISP-2.

* * *

Recovery (Failback)
-------------------

When ISP-1 comes back:

```
ip rule del fwmark 0x00<isp1_mark>0000 lookup <isp2_table_id> priority <prio>
ip rule add fwmark 0x00<isp1_mark>0000 lookup <isp1_table_id> priority <prio>
```

Traffic reverts back.

* * *

**REQUIRED** Supporting Pieces


To make this reliable, you must also have:

> [Configured routing tables](route_rule_setup.md)

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
How to test For ISP Failure
--

**Meaning:** Ping a publically accessable server while specifying an interface if the ping works the isp is up if not then the isp is down.

**Example:**
- ping -c 5 -I enp44s0 8.8.8.8 

```bash
ping -c <times_to_ping> -I <wan_iface> <public_server_ip/domain>
```