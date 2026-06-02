
# Linux Multipath Default Route (ECMP / Weighted Load Sharing)

> Warning: The table used in this is not created using systemd-networkd. You must manage all the routes manually in this.

1. Command

    ```bash
    ip route add default table <aggregated_table_id> \
        nexthop via <isp1_gateway_ip> dev <isp1_iface> weight <w1> \
        nexthop via <isp2_gateway_ip> dev <isp2_iface> weight <w2> \
        ...
        nexthop via <ispN_gateway_ip> dev <ispN_iface> weight <wN>
    ```

    ```bash
    ip -6 route add default table <aggregated_table_id> \
        nexthop via <isp1_gateway_ip> dev <isp1_iface> weight <w1> \
        nexthop via <isp2_gateway_ip> dev <isp2_iface> weight <w2> \
        ...
        nexthop via <ispN_gateway_ip> dev <ispN_iface> weight <wN>
    ```
    This command creates **a single default route** in a **non-main routing table** that contains **multiple next hops**.

    > Note: We must have a special table for aggregation. (independant of all the other ISP tables/main table).

    `table <aggregated_table_id>` means:

    *   This route is **not active by default**
    *   It is only used when matched by an `ip rule`
    *   Selected via:
        *   `fwmark` (from nftables mangle) <br><br>

    ```bash
    ip rule add fwmark 0x00XX0000/0x00FF0000 table <aggregated_table_id>
    ```
    ```bash
    ip -6 rule add fwmark 0x00XX0000/0x00FF0000 table <aggregated_table_id>
    ```
    Now this table can be assigned to the users for whom ISP agregation is to be enabled. We set the Fwmark as this table's for those users.


1. Weight Is Not Bandwidth

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


1. Failure Behavior

    1. What happens if an ISP dies?
        - The kernel **does not remove** the nexthop automatically
        - Traffic continues to be hashed to the dead path
        - Connections fail silently

    ### You MUST add one of:

    - `nexthop ... dead` handling via:
        - `ip monitor`
        - `keepalived`
        - `ifup/down`
        - BFD / userspace watchdog

    **This route alone is NOT failover-safe.**


1. Interaction with nftables / QoS

    This setup is paired with:

    ### nftables (mangle)

    ```bash
    meta mark set 0x00<isp_id><tc_class>
    ```

    ### ip rule

    ```bash
    ip rule add fwmark 0x00<isp_id>0000/0x00FF0000 table <aggregated_table_id>
    ```
    ```bash
    ip -6 rule add fwmark 0x00<isp_id>0000/0x00FF0000 table <aggregated_table_id>
    ```

    Without **mangle + ip rule**, this route does nothing.