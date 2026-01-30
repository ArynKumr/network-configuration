# Firewall Module Setup Guide: Networking & DHCP

This guide covers the deployment of three core firewall modules:
1.  **Network Topology Module**: L2/L3 interface management via `systemd-networkd`.
2.  **DHCP Server Module**: IP address management via `ISC Kea 3.0`.
3.  **Relay Module**: Bridging DHCP requests across subnets.

---

## 🛠 Module 1: Network Topology (systemd-networkd)
This module defines how the firewall "sees" the network. We replace traditional `ifupdown` or `NetworkManager` with `systemd-networkd` for better integration and performance.

### 1.1 Enable systemd-networkd
```bash
systemctl enable --now systemd-networkd systemd-resolved
```

### 1.2 Define Interfaces (`/etc/systemd/network/`)
Create configurations for your specific use cases:

**Case A: Physical Interface (Flat/Direct)**
`10-physical.network`
```ini
[Match]
Name=enp8s0
[Network]
Address=10.9.0.1/24
IPForward=yes
```

**Case B: VLAN Interface (Segmented)**
`20-vlan10.netdev` & `20-vlan10.network`
```ini
# Netdev defines the device
[NetDev]
Name=vlan10
Kind=vlan
[VLAN]
Id=10

# Network defines the L3 config
[Match]
Name=vlan10
[Network]
Address=10.168.1.1/24
IPForward=yes
```

**Case C: Linux Bridge (Aggregated)**
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

---

## 🗄 Module 2: DHCP Server (Kea 3.0)
The central engine for IP allocation. It listens for local broadcast requests and relayed unicast requests.

### 2.1 Installation & Database Init
```bash
# Add Repo & Install
curl -1sLf 'https://dl.cloudsmith.io/public/isc/kea-3-0/setup.deb.sh' | bash
apt update && apt install -y isc-kea isc-kea-mysql mariadb-server

# Initialize Database
mysql -u root -e "CREATE DATABASE kea_dhcp; CREATE USER 'dilraj'@'localhost' IDENTIFIED BY 'dilraj'; GRANT ALL PRIVILEGES ON kea_dhcp.* TO 'dilraj'@'localhost'; FLUSH PRIVILEGES;"
kea-admin db-init mysql -u dilraj -p dilraj -n kea_dhcp
```

### 2.2 Configure Kea (`/etc/kea/kea-dhcp4.conf`)
Ensure you define subnets with the `relay` block when the clients are not on a directly connected broadcast domain.

```json
{
    "Dhcp4": {
        "interfaces-config": { "interfaces": ["enp8s0", "vlan10", "br0"] },
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
`systemctl restart isc-kea-dhcp4-server`

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
```bash
# SERVER_IP is the IP of the Kea Instance
dhcrelay -4 -D -iu vlan10 -id enp8s0 10.9.0.1
```

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