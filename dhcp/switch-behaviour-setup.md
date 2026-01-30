**Purpose:** Configuring the Firewall to act as a switch (For the case of Uplink DHCP) for L2/L3 connectivity including VLANs and Bridges.

#### Case 1: Flat/Direct DHCP
Direct connection between Server and Client (No relay).
```ini
# /etc/systemd/network/10-flat.network
[Match]
Name=eth0
[Network]
Address=10.9.0.1/24
```

#### Case 2: VLAN-based Topology
Creating tagged interfaces for segmented traffic.
```ini
# /etc/systemd/network/vlan10.netdev
[NetDev]
Name=vlan10
Kind=vlan
[VLAN]
Id=10

# /etc/systemd/network/vlan10.network
[Match]
Name=vlan10
[Network]
Address=10.168.1.1/24
IPForward=yes
```

#### Case 3: Bridge-based Topology
Grouping multiple ports into a single logical broadcast domain.
```ini
# /etc/systemd/network/br0.netdev
[NetDev]
Name=br0
Kind=bridge

# /etc/systemd/network/br0.network
[Match]
Name=br0
[Network]
Address=10.1.1.1/24
IPForward=yes
```