**Purpose:** To show a quick runthrough of setting up all module ,without going into the depths

This guide plans to give an overview of the deployment of three core firewall modules:
1.  **Network Topology Module**: L2/L3 interface management via `systemd-networkd`.
2.  **DHCP Server Module**: IP address management via `ISC Kea 3.0`.
3.  **Relay Module**: Bridging DHCP requests across subnets.

---

## 🛠 Module 1: Network Topology (systemd-networkd)
This module defines how the firewall "sees" the network. We replace traditional `ifupdown` or `NetworkManager` with `systemd-networkd` for better integration and performance.

### 1.1 Enable systemd-networkd
```bash
systemctl enable --now systemd-networkd
```

### 1.2 Define Interfaces (`/etc/systemd/network/`)
Create configurations for your specific use cases:

**1.2.1: Physical Interface (Flat/Direct)**
`10-physical.network`
```ini
[Match]
Name=enp8s0
[Network]
Address=10.9.0.1/24
IPForward=yes #Just as precaution ,when net.ipv4.ip_forward is persistently set to 1 ,it persists ip-based forwarding ,kernel-wide
```

**1.2.2: VLAN Interface (Segmented)**
`20-vlan.netdev` & `20-vlan.network` & `trunk.link`

`20-vlan.netdev`
```ini
[NetDev]
Name=vlan10
Kind=vlan

[VLAN]
Id=10 
```

`20-vlan.network`
```ini
# 10-vlan10.network, assigns the ip address to the vlan. similar with vlan20
[Match]
Name=vlan10

[Network]
Address=Address=10.2.1.1/24
```
`trunk.link` 
> Ignore If vlan parent isn't supposed to be trunked (Very Rare nowadays)
```ini
[Match]
Name=enp11s0 #NOTE: Incase of trunked vlans ,enp11s0 will not have an ip 

[Network]
VLAN=vlan10
```
**1.2.3: Linux Bridge (Aggregated)**
`30-br0.netdev` & `30-br0.network`
```ini
[NetDev]
Name=br0
Kind=bridge

[Match]
Name=br0
[Network]
Address=10.1.1.1/24
IPForward=yes
```

>Note: To Apply any new interface based config ,run `systemctl restart systemd-networkd`
---

## 🗄 Module 2: DHCP Server (Kea 3.0)
The central engine for IP allocation. It listens for local broadcast requests and relayed unicast requests.

### 2.1 Installation & Database Init
```bash
# Add Repo & Install
curl -1sLf 'https://dl.cloudsmith.io/public/isc/kea-3-0/setup.deb.sh' | bash
apt update && apt install -y isc-kea isc-kea-mysql mariadb-server
```
# Initialize Database
>NOTE: Use strong credentials in production ,below shown example here is for simplicity.
```bash
mysql -u root -e "CREATE DATABASE kea_dhcp; 
CREATE USER 'dilraj'@'localhost' IDENTIFIED BY 'dilraj'; GRANT ALL PRIVILEGES ON kea_dhcp.* TO 'dilraj'@'localhost'; FLUSH PRIVILEGES;"
kea-admin db-init mysql -u dilraj -p dilraj -n kea_dhcp
```
### 2.2 Configure Kea (`/etc/kea/kea-dhcp4.conf`)
Ensure you define subnets with the `relay` block when the clients are not on a directly connected broadcast domain.

```json
{
    "Dhcp4": {
        "interfaces-config": { "interfaces": ["enp8s0", "vlan10", "br0"] },
        "hosts-database": {
            "type": "mysql",
            "name": "kea_dhcp",
            "user": "dilraj",
            "password": "dilraj",
            "host": "127.0.0.1",
            "port": 3306
        },
        "expired-leases-processing": {
            "reclaim-timer-wait-time": 10,
            "flush-reclaimed-timer-wait-time": 25,
            "hold-reclaimed-time": 3600,
            "max-reclaim-leases": 100,
            "max-reclaim-time": 250,
            "unwarned-reclaim-cycles": 5
        },
        "calculate-tee-times": true,
        "valid-lifetime": 86400,
        "lease-database": {
            "type": "mysql",
            "name": "kea_dhcp",
            "user": "dilraj",
            "password": "dilraj",
            "host": "localhost"
        },
        "subnet4": [
            {
                "id": 1,
                "subnet": "10.9.0.0/24",
                "pools": [{ "pool": "10.9.0.10 - 10.9.0.200" }]
            },
            {
                "id": 2,
                "subnet": "10.168.1.0/24",
                "relay": { "ip-addresses": ["10.168.1.1"] },
                "pools": [{ "pool": "10.168.1.100 - 10.168.1.200" }]
            }
        ]
    }
}
```
---
>NOTE: Some variables here are default consts already (e.g; valid-lifetime:86400 is set by default to 86400), they are mentioned for reference ,if in future any of them loose their default status or values for them need to be customised.
---

```bash 
#Performs a dry-run and tells whether there are any syntax errors
kea-dhcp4 -t /etc/kea/kea-dhcp4.conf
# To Apply the config and restart the service
systemctl restart isc-kea-dhcp4-server`
```
---

## 📡 Module 3: DHCP Relay
Used when the firewall acts as a gateway for downstream switches or when clients are separated by a router.

### 3.1 Setup Relay Agent
Install the relay package:
```bash
apt install isc-dhcp-relay
```

### 3.2 Running the Relay
The relay needs two pieces of information:
1.  **Upstream interface (`-iu`)**: Where the clients are.
2.  **Downstream interface (`-id`)**: Where the DHCP server is.

**Example: Relay for VLAN 10**
```ini
# SERVER_IP is the IP of the Kea Instance
dhcrelay -4 -D -iu vlan10 -id enp8s0 10.9.0.1 
#This is only meant for quick debugging 
#Please disable service ,via `systemctl stop isc-dhcp-relay.service`,whilst running this foreground 
```

> NOTE: Ideally run the relay as a persistent service ,by editing the `/etc/default/isc-dhcp-relay`. In case of running multiple relays ,refer [this](multi-dhcp-relay-service.md)
---

## ⚙️ Firewall Kernel Tuning
For these modules to interact correctly (specifically the Relay), the Linux kernel must allow packets to move between interfaces and not drop them due to path filtering.<br>For that refer the [README](../README.md)


---

## ✅ Verification Checklist
- [ ]  **Interfaces**: Run `networkctl status` to ensure all interfaces are `routable` and `configured`.
- [ ]  **Kea**: Run `kea-dhcp4 -t /etc/kea/kea-dhcp4.conf` to check for JSON syntax errors.
- [ ]  **Logs**: Monitor assignments in real-time:
    ```bash
    journalctl -u isc-kea-dhcp4-server -f
    ```
- [ ]  **Database**: Check leases stored in MySQL:
    ```sql
    SELECT IP_ADDRESS, HEX(HWADDR) FROM kea_dhcp.lease4;
    ```

>NOTE: This document provides a deployment overview. Detailed option tuning, relay edge cases, and switch behavior are covered in supporting files under the folder dhcp of this repository.