
* * *

DMZ & Port Forwarding (nftables)
================================

**Purpose:**  
Provide runnable nftables templates for:

*   selective port forwarding (TCP, UDP, or both), and
*   full DMZ (all incoming traffic redirected to a single internal host),  
    with optional QoS marking.

> **Protocol note:**  
> If both TCP and UDP are required, apply the relevant rules **twice** — once per protocol.

* * *

Selective Port Forwarding
-------------------------
>Note: Ensure that you have added the interfaces in nat and filter table.
### 1\. ALLOW INTERNET ACCESS

**Purpose:**  
Adds the client to the global whitelist so the firewall allows general outgoing traffic.

```
nft add element inet filter allowed_ip4 { <client_ip> }
```

* * *

### 2\. UPLOAD TRAFFIC MARKING (Internal → External)

**Purpose:**  
Tags traffic originating from the internal client and source port.  
Used for ISP/QoS classification of **outgoing** traffic.

```
nft add rule inet mangle prerouting \
    ip saddr <client_ip> <protocol> sport <client_port> \
    meta mark set 0x00<isp_mark><tc_class_marks>
```

* * *

### 3\. DOWNLOAD TRAFFIC MARKING (External → Internal)

**Purpose:**  
Tags traffic destined **to** the internal client.  
Allows control of incoming bandwidth so downloads don’t saturate the network.

```
nft add rule inet mangle forward \
    ip daddr <client_ip> <protocol> dport <client_port> \
    meta mark set 0x00<isp_mark><tc_class_marks>
```

* * *

### 4\. PORT FORWARD (DNAT)

**Purpose:**  
Ensures traffic hitting the public WAN IP on a specific port is redirected to the internal host.  
`insert rule` places this at the **top** of the NAT chain.

```
nft insert rule inet nat prerouting \
    ip daddr <public_facing_isp_ip> <protocol> dport <public_facing_isp_port> \
    dnat to <client_ip>:<client_port>
```

* * *

### 5\. SECURITY PERMIT (FORWARD CHAIN)

**Purpose:**  
Since the `forward` chain policy is `drop`, forwarded packets must be explicitly allowed **after DNAT**.

```
nft insert rule inet filter forward ip daddr <client_ip> <action>
```

* * *

Selective Port Pool Forwarding
-------------------------
>Note: Ensure that you have added the interfaces in nat and filter table.
### 1\. ALLOW INTERNET ACCESS

**Purpose:**  
Adds the client to the global whitelist so the firewall allows general outgoing traffic.

```
nft add element inet filter allowed_ip4 { <client_ip> }
```

* * *

### 2\. UPLOAD TRAFFIC MARKING (Internal → External)

**Purpose:**  
Tags traffic originating from the internal client and source ports.  
Used for ISP/QoS classification of **outgoing** traffic.

```
nft add rule inet mangle prerouting \
    ip saddr <client_ip> <protocol> sport <starting_client_port>-<ending_client_port> \
    meta mark set 0x00<isp_mark><tc_class_marks>
```

* * *

### 3\. DOWNLOAD TRAFFIC MARKING (External → Internal)

**Purpose:**  
Tags traffic destined **to** the internal client.  
Allows control of incoming bandwidth so downloads don’t saturate the network.

```
nft add rule inet mangle forward \
    ip daddr <client_ip> <protocol> dport <starting_client_port>-<ending_client_port> \
    meta mark set 0x00<isp_mark><tc_class_marks>
```

* * *

### 4\. PORT FORWARD (DNAT)

**Purpose:**  
Ensures traffic hitting the public WAN IP on a specific pool of port eg: 64000 to 65000 is redirected to the internal hosts 5000 to 6000 and mapped one to one
 also it is required that the range of ports to be the same.  
`insert rule` places this at the **top** of the NAT chain.

```
nft insert rule inet nat prerouting \
    ip daddr <public_facing_isp_ip> <protocol> dport <starting_public_facing_isp_port>-<ending_public_facing_isp_port> \
    dnat to <client_ip>:<starting_client_port>-<ending_client_port>
```

* * *

### 5\. SECURITY PERMIT (FORWARD CHAIN)

**Purpose:**  
Since the `forward` chain policy is `drop`, forwarded packets must be explicitly allowed **after DNAT**.

```
nft insert rule inet filter forward ip daddr <client_ip> <action>
```

* * *

Full DMZ (All Incoming Traffic → Single Host)
---------------------------------------------

### 1\. THE PERMIT

**Purpose:**  
Allows the internal client to send traffic **out** to the internet.  
Without this, the host can receive packets but cannot reply.

```
nft add element inet filter allowed_ip4 { <client_ip> }
```

* * *

### 2\. QOS MARKING

**Purpose:**  
Labels all traffic from the client for bandwidth management.  
Ensures forwarded DMZ traffic still respects TC class limits.

```
nft add element inet mangle user4_marks { <client_ip> : 0x00<isp_mark><tc_class_marks> }
```

* * *

### 3\. TRANSLATOR (DNAT)

**Purpose:**  
All packets hitting the public ISP IP are destination-NATed to the internal client  
before routing decisions occur.

```
nft insert rule inet nat prerouting \
    ip daddr <public_facing_isp_ip> \
    dnat to <client_ip>
```

* * *

### 4\. GATEKEEPER (FORWARD CHAIN)

**Purpose:**  
Explicitly allows traffic through the `forward` chain.  
Required when the default policy is `drop`.

```
nft insert rule inet filter forward ip daddr <client_ip> <action>
```

* * *