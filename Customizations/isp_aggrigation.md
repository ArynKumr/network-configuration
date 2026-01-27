ip route add default table <aggregated_table_id> \
    nexthop via <isp1_gateway_ip> dev <isp1_iface> weight <w1> \
    nexthop via <isp2_gateway_ip> dev <isp2_iface> weight <w2> \
    .......... nexthop via <isp(n)_gateway_ip> dev <isp(n)_iface> weight <w(n)>

* * *

Linux Multipath Default Route (ECMP / Weighted Load Sharing)
============================================================

Command
-------

```bash
ip route add default table <aggregated_table_id> \
    nexthop via <isp1_gateway_ip> dev <isp1_iface> weight <w1> \
    nexthop via <isp2_gateway_ip> dev <isp2_iface> weight <w2> \
    ...
    nexthop via <ispN_gateway_ip> dev <ispN_iface> weight <wN>
```

* * *

1\. What This Actually Does
--------------------------------------

This command creates **a single default route** in a **non-main routing table** that contains **multiple next hops**.

Linux treats this as:

*   **ECMP (Equal/Weighted Cost Multi-Path) routing**
*   **Per-flow load balancing**, _not_ per-packet
*   **Stateless distribution**, decided at connection start


* * *

2\. Why This Is in a Custom Table
---------------------------------

`table <aggregated_table_id>` means:

*   This route is **not active by default**
*   It is only used when matched by an `ip rule`
*   Selected via:
    *   `fwmark` (from nftables mangle)

### Typical selector

```bash
ip rule add fwmark 0x00XX0000/0x00FF0000 table <aggregated_table_id>
```

This makes the multipath route **policy-controlled**, not global.

* * *

3\. Nexthop Semantics (Critical)
--------------------------------

Each `nexthop` defines **one ISP path**:

| Field | Meaning |
| --- | --- |
| `via <gateway>` | Layer-3 next router |
| `dev <iface>` | Physical/logical interface |
| `weight <w>` | Relative traffic share |

Example:

```bash
nexthop via 1.1.1.1 dev wan1 weight 3
nexthop via 2.2.2.2 dev wan2 weight 1
```

**Result:**  
≈ 75% of _new flows_ go to `wan1`, ≈ 25% to `wan2`.

* * *

4\. How Load Balancing Really Works (Important)
-----------------------------------------------

Linux uses a **hash of the flow tuple**, typically:

```
src IP
dst IP
src port
dst port
protocol
```

This means:

*   One TCP/UDP flow → **one ISP only**
*   No packet reordering
*   No mid-connection switching

### Consequences

✅ Safe for TCP  
❌ Not true bandwidth aggregation for a single download  
✅ Excellent for many parallel users / sessions

* * *

5\. Weight Is Not Bandwidth
---------------------------

Weight only controls **probability of path selection**.

If your ISPs are:

| ISP | Speed |
| --- | --- |
| ISP1 | 1 Gbps |
| ISP2 | 100 Mbps |

Correct weights would be **~10:1**, _not_ equal.

Bad weighting causes:

*   bufferbloat
*   asymmetric congestion

* * *

6\. Failure Behavior (Read Carefully)
-------------------------------------

### What happens if an ISP dies?

*   The kernel **does not remove** the nexthop automatically
*   Traffic continues to be hashed to the dead path
*   Connections fail silently

### You MUST add one of:

*   `nexthop ... dead` handling via:
    *   `ip monitor`
    *   `keepalived`
    *   `ifup/down`
    *   BFD / userspace watchdog

**This route alone is NOT failover-safe.**

* * *

7\. Interaction with nftables / QoS
-----------------------------------

This setup is paired with:

### nftables (mangle)

```bash
meta mark set 0x00<isp_id><tc_class>
```

### ip rule

```bash
ip rule add fwmark 0x00<isp_id>0000/0x00FF0000 table <aggregated_table_id>
```

Without **mangle + ip rule**, this route does nothing.

* * *

8\. Common Use Cases
--------------------

This design is **wrong** for:

*   single large downloads
*   VPN tunnel aggregation
*   TCP stream bonding

* * *

9\. Minimal Validation Checklist
--------------------------------

After configuring:

```bash
ip route show table <aggregated_table_id>
ip rule show
```

Then test:

```bash
ip route get 8.8.8.8 mark 0x00XX0000
```

You should see **one of the nexthops selected**, not all.

* * *