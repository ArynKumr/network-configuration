**Purpose:** Configuring the Firewall to act as a switch (For the case of Uplink DHCP) for L2/L3 connectivity including VLANs and Bridges.

#### 1. Flat/Direct DHCP
Direct connection between Server and Client (No relay).
```ini
# /etc/systemd/network/10-flat.network
[Match]
Name=eth0
[Network]
Address=10.9.0.1/24
```

#### 2. VLAN-based Topology
Creating tagged interfaces for segmented traffic.
`10-vlan10.netdev`
```ini
# Creates the vlan itself, similarly we make vlan20---vlan_n
[NetDev]
Name=vlan10
Kind=vlan

[VLAN]
Id=10 #Each Vlan gets a specific id
```
`vlan10-trunk.network`
```ini
#Adds the vlans to the physical interface. 
#Also this interface does not get an IP address. 
#It must remain un-addressed(In the case of tagged vlans).
[Match]
Name=enp11s0 #Physical Interface from which the Vlans are related to.
[Network]
VLAN=vlan10
VLAN=vlan20
```
`10-vlan10.network`
```ini
#assigns the ip address to the vlan. similar with vlan20
[Match]
Name=vlan10
[Network]
Address=10.10.100.1/24
```

#### 3. Bridge-based Topology
Grouping multiple ports into a single logical broadcast domain.
`br0.netdev`
```ini
# /etc/systemd/network/br0.netdev
[NetDev]     
Name=br0     
Kind=bridge  
```
`br0.network`
```ini
# /etc/systemd/network/br0.network
[Match]                      
Name = br0                               
[Network]                    
Address = 10.10.10.1/24 
```

`bind.network`
```ini
# /etc/systemd/network/bind.network
[Match]
Name=enp11s0

[Network]
Bridge=br0
```