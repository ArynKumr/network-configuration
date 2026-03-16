# Interfaces Setup
Before we begin, you must have:
- a public IP or upstream IP ,as that implies it connects your server to the external network a.k.a the internet.
- a default route via eth0

---
# WAN interface

```bash
# /etc/systemd/network/wan.network
[Match]
Name=eth0

[Network]
DHCP=yes
```

`systemctl restart systemd-networkd`

For configuring an interface using DHCP, place the wan-dhcp-monitor file at /etc/networkd-dispatcher/routable.d/50-wan-dhcp-monitor

---
# LAN interface

Example LAN: `192.168.1.0/24`

```bash
# /etc/systemd/network/lan.network
[Match]
Name=eth1

[Network]
Address=192.168.1.0/24
```

`systemctl restart systemd-networkd`

---
# Bond Device

1. Create the Bond Interface
    File: `/etc/systemd/network/bond0.netdev`

    ```bash
    [NetDev]
    Name=bond0 # Name of bond device
    Kind=bond # Device type = bond

    [Bond]
    Mode=802.3ad # LACP (Link Aggregation Control Protocol)

    # Other modes: active-backup, balance-rr, balance-xor, broadcast, balance-tlb, balance-alb

    MIIMonitorSec=1s # How often to check link state
    TransmitHashPolicy=layer3+4 # Hashing algorithm (used in balance-xor / 802.3ad modes)
    ```

1. Configure the Bond Interface

    File: `/etc/systemd/network/bond0.network`

    ```bash
    [Match]
    Name=bond0 # Match bond master

    [Network]
    Address=192.168.30.10/24 # Static IP assigned to bond
    Gateway=192.168.30.1 # Default gateway
    DNS=8.8.8.8 # Upstream DNS
    ```

1. Attach Physical NICs to Bond

    NIC1 → `/etc/systemd/network/enp1s0.network`

    ```bash
    [Match]
    Name=enp1s0 # Match physical interface
    [Network]
    Bond=bond0 # Attach NIC into bond
    ```

    NIC2 → `/etc/systemd/network/enp2s0.network`

    ```bash
    [Match]
    Name=enp2s0
    [Network]
    Bond=bond0
    ```

    >Alternative Bonding Modes
    > In `bond0.netdev`, replace `Mode=` with:
    > - `active-backup` → One NIC active, others on standby (no switch support needed).
    > - `balance-rr` → Round-robin across NICs (can cause reordering).
    > - `balance-xor` → Hash-based load balancing.
    > - `broadcast` → Send on all NICs (rarely used).
    > - `balance-tlb` / `balance-alb` → Adaptive transmit/receive load balancing.

    ### Verify

    ```bash
    sudo systemctl restart systemd-networkd
    networkctl status bond0
    cat /proc/net/bonding/bond0
    ```

1. Minimal Demo Config (DHCP on bond)

    If you just want DHCP on the bond:

    **bond0.netdev**
    ```bash
    [NetDev]
    Name=bond0
    Kind=bond
    [Bond]
    Mode=active-backup
    ```

    **bond0.network**
    ```bash
    [Match]
    Name=bond0
    [Network]
    DHCP=yes
    ```

    **enp1s0.network**
    ```bash
    [Match]
    Name=enp1s0
    [Network]
    Bond=bond0
    ```

    **enp2s0.network**
    ```bash
    [Match]
    Name=enp2s0
    [Network]
    Bond=bond0
    ```
---
# Bridge Device

1. Create the Bridge Interface

    File: `/etc/systemd/network/br0.netdev`

    ```bash
    [NetDev]
    Name=br0 # The bridge interface name
    Kind=bridge # Device type = bridge
    MACAddress=12:34:56:78:9a:bc # Optional: set fixed MAC (stable identity)
    ```

1. Configure the Bridge Device

    File: `/etc/systemd/network/br0.network`

    ```bash
    [Match]
    Name=br0 # Apply settings to the bridge device

    [Network]
    Address=192.168.20.1/24 # Assign IP to the bridge (gateway for LAN)
    Gateway=192.168.20.254 # Optional: upstream gateway
    DNS=192.168.20.254 # Optional: upstream DNS
    ```

1. Attach Physical NICs to Bridge

    NIC 1 → `/etc/systemd/network/enp1s0.network`

    ```bash
    [Match]
    Name=enp1s0 # Match first NIC

    [Network]
    Bridge=br0 # Attach NIC to bridge
    ```

    NIC 2 → `/etc/systemd/network/enp2s0.network`

    ```bash
    [Match]
    Name=enp2s0 # Match second NIC

    [Network]
    Bridge=br0 # Attach NIC to bridge
    ```

    Verify

    ```bash
    sudo systemctl restart systemd-networkd
    networkctl list
    networkctl status br0
    ```

    You should see `br0` with the configured IP, and `enp1s0`/`enp2s0` enslaved.

1. Minimal Demo Config (Transparent Bridge)

    If you want just a transparent bridge (Linux as a dumb switch):

    **br0.netdev**
    ```bash
    [NetDev]
    Name=br0
    Kind=bridge
    ```

    **br0.network**
    ```bash
    [Match]
    Name=br0

    [Network]
    DHCP=no # Bridge has no IP (transparent)
    ```

    **enp1s0.network**
    ```bash
    [Match]
    Name=enp1s0

    [Network]
    Bridge=br0
    ```

    **enp2s0.network**
    ```bash
    [Match]
    Name=enp2s0

    [Network]
    Bridge=br0
    ```

    Now `enp1s0` and `enp2s0` act like switch ports with no IP on host.

After we are finished setting up the interfaces, we must set the sysctl parameters. this is how we set them up:

```bash
cat <<EOF >/etc/sysctl.d/99-forwarding.conf
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 0
net.ipv4.conf.default.rp_filter = 0
net.ipv4.conf.<WAN_INTERFACE>.rp_filter = 0
net.ipv4.conf.<LAN_INTERFACE>.rp_filter = 1
EOF
sysctl --system
```
Ensure all the WAN_INTERFACEs and LAN_INTERFACEs are set.