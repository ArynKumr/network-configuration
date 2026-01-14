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

Example:
 - We have networks 192.168.1.0/24 (ISP) and 10.9.0.0/24(LAN) which are supposed to be reachable by the firewall.
    ```bash
    root@localhost:~# ip -c -br a
    enp1s0           UP             192.168.1.14/24 metric 100 
    enp8s0           UP             10.9.0.1/24 
    root@localhost:~# 
    ```
    > However we already flushed the main table, so the routes are gone. Therefore we are unable to reach the specified networks anymore.


 - To re add them, we need to add the routes back again, using these commands:
    ```bash
    root@localhost:~# ip route add 192.168.1.0/24 dev enp1s0 src 192.168.1.14
    root@localhost:~# ip route add 10.9.0.0/24 dev enp8s0 src 10.9.0.1
    ```
> **Why this matters:**  
> Without these routes, replies to LAN/WAN traffic may fail  
> even though interfaces are up.

* * *

Policy Rules (`ip rule`)
------------------------

**Purpose:**  
Bind **packet marks** (set in [inet mangle](../nftables.md#L681) ) to **routing tables**.

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
> Note: the <isp_mark> section here is hexadecimal (0-F per bit) <br>For example, the values can be: 00,01,10,F1,AF etc

> Note: Here the table_number can be anything you like, for testing purposes. It creates the table with that number. when we run this command, the table with that number gets created/updated.

**Example:**

```bash
root@localhost:~# ip rule add fwmark 0x00A10000/0xff0000 table 1
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

**Example:**

```bash
root@localhost:~# ip route add default via 192.168.1.1 dev enp1s0 table 1
```

* * *

### 3\. Add Directly Connected Networks

**Purpose:**  
Ensure the ISP’s local network is reachable without looping through the gateway.

```
ip route add <ip_subnet_of_iface> dev <iface_name> src <ip_on_iface> table <table_number>
```

**Example:**

```bash
root@localhost:~# ip route add 192.168.1.0/24 dev enp1s0 src 192.168.1.14 table 1
```

[To test user routes](user_login.md)

* * *