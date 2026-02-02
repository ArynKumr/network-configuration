This guide provides an expanded, production-ready framework for deploying an **ISC DHCP Relay Agent** to work with a **Kea DHCP Server**.

---

# Comprehensive Guide: DHCP Relay for Kea across L3 Boundaries

## 1. Architectural Logic
When a client is not on the same L2 segment as the Kea server, the DHCP broadcast (`DISCOVER`) cannot reach the server. The Relay Agent solves this by:
1.  **Intercepting** the broadcast on the client-facing interface.
2.  **Encapsulating** the request into a Unicast packet.
3.  **Injecting its own IP** into the `giaddr` (Gateway IP Address) field.
4.  **Forwarding** the packet to the Kea Server IP.
5.  **Subnet Selection:** Kea receives the packet, sees the `giaddr`, and looks for a `subnet4` block that matches that IP address.

---

## 2. Installation & Persistent Configuration
Instead of running commands manually, use the OS-native configuration files to ensure the relay starts on boot.

### Installation
```bash
sudo apt update && sudo apt install isc-dhcp-relay -y
```

### Persistent Configuration (`/etc/default/isc-dhcp-relay`)
Edit this file to define your relay behavior permanently.
```bash
# Interfaces the relay should listen on (Client-facing AND Server-facing)
INTERFACES=""

# The IP address of the Kea DHCP Server
SERVERS="10.50.50.1"

# Additional options
# -4: IPv4 only
# -no-pid: Do not write a pid file (useful for some containers)
OPTIONS="-4 -D -a -iu eth0 -id eth1 -id vlan10 -id br0"
```

---

## 3. Deployment Scenarios (Manual Execution)
If you are testing or using a custom script, use these commands. 
**Note:** In `isc-dhcp-relay`, the `-i` flag is used for **all** involved interfaces (both upstream and downstream).

### 3.1. VLAN-Based Relay
Useful when the relay agent sits on a router with tagged traffic.
```bash
# giaddr will be the IP assigned to vlan10
dhcrelay -4 -aD -i vlan10 -i eth0 10.50.50.1
```

### 3.2. Physical Port Relay
Useful for simple L3 separation.
```bash
# giaddr will be the IP assigned to eth1
dhcrelay -4 -aD -i eth1 -i eth0 10.50.50.1
```

### 3.3. Bridge Relay
Used in virtualization (Proxmox/KVM) where clients are on a software bridge.
```bash
# giaddr will be the IP assigned to br0
dhcrelay -4 -aD -i br0 -i eth0 10.50.50.1
```

---

## 4. Kea Server Configuration (Matching the Relay)
For the relay to work, the **Kea Server** must have a subnet matching the `giaddr` of the relay agent.

**Example `kea-dhcp4.conf`:**
```json
{
"Dhcp4": {
    "interfaces-config": {
        "interfaces": [ "eth0" ] // The interface on the SERVER side
    },
    "subnet4": [
        {
            "id": 1,
            "subnet": "192.168.10.0/24",
            "pools": [ { "pool": "192.168.10.50 - 192.168.10.200" } ],
            "relay": {
                "ip-address": "192.168.10.1" // MUST match the Relay Agent's IP on that subnet
            },
            "option-data": [
                { "name": "routers", "data": "192.168.10.1" }
            ]
        }
    ]
}
}
```

---

## 5. Critical OS Tuning
The relay agent acts as a middleman. If the Linux Kernel thinks the incoming DHCP response is "spoofed" or if forwarding is disabled, the packet will be dropped.

### Enable Packet Forwarding
```bash
sysctl -w net.ipv4.ip_forward=1
```

### Relax Reverse Path Filtering (RP_Filter)
By default, Linux might drop packets if the "return path" looks suspicious. DHCP packets often trigger this. Setting it to `2` (loose) allows the relay to function.
```bash
sysctl -w net.ipv4.conf.all.rp_filter=2
sysctl -w net.ipv4.conf.default.rp_filter=2
```

>Note: Firewall need to allow communication of UDP packets over port 67 and 68 as those are the ports for DHCPv4 and ports 546 and 547 for DHCPv6


---

## 6. Summary Comparison Table

| Feature | Flat Network | Relay Agent (VLAN/Port/Bridge) |
| :--- | :--- | :--- |
| **L2 Boundary** | Same Broadcast Domain | Different Broadcast Domains |
| **Kea Logic** | Matches incoming interface subnet | Matches `giaddr` field in packet |
| **Packet Type** | Broadcast (DISCOVER) | Unicast (Forwarded DISCOVER) |
| **Traffic Path** | Client $\to$ Kea | Client $\to$ Relay $\to$ Kea |
| **Complexity** | Low | Medium (Requires L3 Routing) |

---

## 7. Troubleshooting Example
If clients aren't getting IPs, run this on the **Relay Agent** to see where the communication breaks:

```bash
# Watch for DHCP traffic on the client interface and the server uplink
tcpdump -i any port 67 or port 68 -n -vv
```

**What to look for:**
1.  **BOOTREQUEST** from `0.0.0.0` on the client interface.
2.  **BOOTREQUEST** from `Relay_IP` to `Kea_IP` on the uplink interface.
3.  **BOOTREPLY** from `Kea_IP` to `Relay_IP`.
4.  **BOOTREPLY** from `Relay_IP` to `Client_MAC`.


Refer to [man](https://kb.isc.org/docs/isc-dhcp-44-manual-pages-dhcrelay), for more info