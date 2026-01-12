* * *

Policy Routing & ISP Steering (Linux `iproute2`)
================================================

**Purpose:**  
Implement **mark-based policy routing** so traffic tagged by `nftables (mangle)` is:

*   steered to a specific ISP,
*   routed through a dedicated routing table, and
*   kept consistent for both local and forwarded traffic.

This is **routing logic**, not firewalling.

* * *

Main Routing Table Reset (`table main`)
---------------------------------------

**Purpose:**  
Clear and rebuild the **default routing table** so the Firewall only retains  
explicitly defined local connectivity.

> ⚠️ **Danger:**  
> Flushing `table main` will temporarily disconnect the Firewall  
> until local routes are re-added.

* * *

### 1\. Flush the Main Routing Table

```
ip route flush table main
```

* * *

### 2\. Restore Local Connectivity (Per Interface)

**Purpose:**  
Tell the kernel how to reach directly connected networks and  
which source IP to use when sending packets.

```
ip route add <ip_subnet_of_iface> dev <iface_name> src <ip_on_iface>
```

> **Why this matters:**  
> Without these routes, replies to LAN/WAN traffic may fail  
> even though interfaces are up.

* * *

Policy Rules (`ip rule`)
------------------------

**Purpose:**  
Bind **packet marks** (set in `inet mangle`) to **routing tables**.

Only the **ISP portion** of the mark is evaluated.

* * *

### 1\. Cleanup Old Rules (Idempotency)

**Purpose:**  
Prevent duplicate or conflicting rules when reapplying configuration.

```
ip rule del fwmark 0x00<isp_mark>0000/0x00ff0000 table <table_number>
```

* * *

### 2\. Add the Steering Rule

**Purpose:**  
Force packets with a matching ISP mark to use a specific routing table.

```
ip rule add fwmark 0x00<isp_mark>0000/0x00ff0000 table <table_number>
```

**Logic:**

*   `fwmark` → value set by `nftables`
*   `/0x00ff0000` → mask isolates the **ISP ID**
*   `table <table_number>` → selected ISP routing table

* * *

ISP-Specific Routing Table Setup
--------------------------------

**Purpose:**  
Define how traffic exits the Firewall **when steered to this ISP**.

Each ISP gets its **own routing table**.

* * *

### 1\. Flush the ISP Table

**Purpose:**  
Remove stale or incorrect routes before rebuilding.

```
ip route flush table <table_number>
```

* * *

### 2\. Define the Default Gateway (ISP Exit)

**Purpose:**  
Send all internet-bound traffic in this table to the ISP gateway.

```
ip route add default via <gateway_ip> dev <iface_name> table <table_number>
```

* * *

### 3\. Add Directly Connected Networks

**Purpose:**  
Ensure the ISP’s local network is reachable without looping through the gateway.

```
ip route add <ip_subnet_of_iface> dev <iface_name> src <ip_on_iface> table <table_number>
```

* * *