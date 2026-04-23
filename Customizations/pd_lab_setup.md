# Lab Documentation: IPv6 Prefix Delegation (PD) Simulation

## 1. Objective
The goal of this lab is to simulate a professional ISP-to-CPE (Customer Premises Equipment) IPv6 architecture. This includes the delegation of a global prefix from an ISP to a router, the carving of that prefix into subnets, and the distribution of those addresses to end hosts using SLAAC.

---

## 2. Lab Topology
**Logical Flow:** 
`[ISP Server] <--- (WAN Link) ---> [CPE Router] <--- (LAN Link) ---> [End Host]`

### Network Assignments
| Device | Interface | Role | IP / Prefix |
| :--- | :--- | :--- | :--- |
| **ISP Server** | `enp1s0` | Gateway / DHCPv6 Server | `2001:db8:1::1/64` |
| **CPE Router** | `enp1s0` | WAN Interface | Dynamic (via SLAAC) |
| **CPE Router** | `enp7s0` | LAN Interface | `2001:db8:1:1::1/64` (from PD) |
| **End Host** | `eth0` | Client | Dynamic (via SLAAC) |

**Delegated Prefix:** `2001:db8:1::/56` (Assigned by ISP $\rightarrow$ CPE)

---

## 3. Step-by-Step Configuration

### Part A: The ISP Server
The ISP server acts as the source of truth, providing both the Router Advertisement (RA) and the DHCPv6 Prefix Delegation pool.

#### 1. Enable IPv6 Forwarding
The kernel must be allowed to act as a router to send RAs.
```bash
sudo nano /etc/sysctl.d/99-forwarding.conf
```
Add the following:
```conf
net.ipv6.conf.all.forwarding = 1
net.ipv6.conf.default.forwarding = 1
```
Apply changes: `sudo sysctl -p /etc/sysctl.d/99-forwarding.conf`

#### 2. Configure RA (`systemd-networkd`)
Create `/etc/systemd/network/enp1s0.network`:
```ini
[Match]
Name=enp1s0

[Network]
Address=2001:db8:1::1/64
IPv6AcceptRA=no
IPv6SendRA=yes

[IPv6SendRA]
Managed=no
OtherInformation=yes
RouterLifetimeSec=1800

[IPv6Prefix]
Prefix=2001:db8:1::/48
```
`sudo systemctl restart systemd-networkd`

#### 3. Configure Kea DHCPv6 Server
Create `/etc/kea/kea-dhcp6.conf`:
```json
{
  "Dhcp6": {
    "interfaces-config": { "interfaces": [ "enp1s0" ] },
    "lease-database": { "type": "memfile" },
    "subnet6": [
      {
        "id": 1,
        "subnet": "2001:db8:1::/48",
        "interface": "enp1s0",
        "pd-pools": [
          {
            "prefix": "2001:db8:1::",
            "prefix-len": 48,
            "delegated-len": 56
          }
        ]
      }
    ]
  }
}
```
Start Kea: `sudo kea-dhcp6 -c /etc/kea/kea-dhcp6.conf`

---

### Part B: The CPE Router
The CPE router requests a prefix from the ISP and redistributes it to the LAN.

#### 1. Enable IPv6 Forwarding
Crucial for allowing packets to move from LAN $\rightarrow$ WAN.
```bash
sudo sysctl -w net.ipv6.conf.all.forwarding=1
```

#### 2. WAN Configuration (`systemd-networkd`)
Create `/etc/systemd/network/20-wan.network`:
```ini
[Match]
Name=enp1s0

[Network]
IPv6AcceptRA=yes
DHCP=no
```
`sudo systemctl restart systemd-networkd`

#### 3. Request the Prefix Delegation
Use `dhclient` to request the `/56` block from Kea.
```bash
sudo dhclient -6 -P enp1s0
```
**Verify Lease:** `grep "iaprefix" /var/lib/dhcp/dhclient6.leases`
*(You should see `iaprefix 2001:db8:1::/56`)*.

#### 4. LAN Configuration (`systemd-networkd`)
Carve a `/64` slice from the delegated `/56` and assign it to the LAN.
Create `/etc/systemd/network/30-lan.network`:
```ini
[Match]
Name=enp7s0

[Network]
Address=2001:db8:1:1::1/64
IPv6SendRA=yes

[IPv6SendRA]
Managed=no
OtherInformation=no

[IPv6Prefix]
Prefix=2001:db8:1:1::/64
```
`sudo systemctl restart systemd-networkd`

---

### Part C: The End Host
The host is a standard Linux machine connected to the CPE router's LAN.

#### 1. Configuration
Set the interface to automatic (DHCP/SLAAC). If using `systemd-networkd`:
```ini
[Match]
Name=eth0

[Network]
DHCP=ipv6
IPv6AcceptRA=yes
```

---

## 4. The Final "Integration" Step (Return Routing)
Because Kea is a standalone server, the ISP's Linux kernel doesn't automatically know that the delegated prefix resides behind the CPE router. You must add a return route on the **ISP Server**.

**On the ISP Server:**
```bash
# Route the delegated /56 block via the CPE Router's Link-Local address
sudo ip -6 route add 2001:db8:1::/56 via fe80::[CPE_ROUTER_LL_ADDRESS] dev enp1s0
```

---

## 5. Verification Matrix

| Test | Command (From Device) | Expected Result | Purpose |
| :--- | :--- | :--- | :--- |
| **CPE $\rightarrow$ ISP** | `ping6 2001:db8:1::1` | Success | Verify WAN connectivity. |
| **Host $\rightarrow$ CPE** | `ping6 2001:db8:1:1::1` | Success | Verify LAN SLAAC and Gateway. |
| **Host $\rightarrow$ ISP** | `ping6 2001:db8:1::1` | Success | Verify Forwarding & Return Route. |
| **Spoofed LAN** | `ping6 -I [LAN_IP] [ISP_IP]` | Success | Verify Routing Table logic. |

## 6. Key Technical Concepts Summary
*   **SLAAC:** Used by the End Host to generate a GUA based on the RA prefix.
*   **IA_PD:** The DHCPv6 process that delegates a block of IPs to a router.
*   **M-Flag / O-Flag:** Router Advertisement flags that tell hosts whether to use DHCPv6 for addresses (M) or other info (O).
*   **IPv6 Forwarding:** Kernel setting that transforms a "Host" into a "Router."
*   **Return Routing:** The necessity for the upstream gateway to have a route back to the delegated prefix.