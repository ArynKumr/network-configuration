Linux Networking & nftables — From Bare Metal to Working NGFW
=============================================================

## Kernel Requirements


- Enable IP forwarding (router mode)

    Temporary (until reboot):

    ```
    sysctl -w net.ipv4.ip_forward = 1
    sysctl -w net.ipv4.conf.all.rp_filter = 0
    sysctl -w net.ipv4.conf.default.rp_filter = 0
    sysctl -w net.ipv4.conf.<WAN_INTERFACE>.rp_filter = 0
    sysctl -w net.ipv4.conf.<LAN_INTERFACE>.rp_filter = 1
    ```

    Persistent:

    ```
    cat <<EOF >/etc/sysctl.d/99-forwarding.conf
    net.ipv4.ip_forward = 1
    net.ipv4.conf.all.rp_filter = 0
    net.ipv4.conf.default.rp_filter = 0
    net.ipv4.conf.<WAN_INTERFACE>.rp_filter = 0
    net.ipv4.conf.<LAN_INTERFACE>.rp_filter = 1
    EOF
    sysctl --system
    ```

    If this is **not enabled**, your firewall will pass traffic nowhere.


## Basic Network Interface Setup

You must have:
- a public IP or upstream IP ,as that implies it connects your server to the external network a.k.a the internet.
- a default route via eth0

1. WAN interface (example: DHCP)

    ```bash
     # /etc/systemd/network/wan.network
    [Match]
    Name=eth0

    [Network]
    DHCP=yes
    ```

    `systemctl restart systemd-networkd`

    Verify:
    ```
    ip addr show eth0
    ip route
    ```



1. LAN interface (static IP)

Example LAN: `192.168.1.0/24`

```bash
# /etc/systemd/network/lan.network
[Match]
Name=eth1

[Network]
Address=192.168.1.0/24
```

`systemctl restart systemd-networkd`

Verify:

```
ip addr show eth1
```


## DNS & DHCP (Minimal but Required)
-------------------------------------

You must set up DHCP. you can find the information regarding it [here](dhcp/dhcp-server-config.md)

For DHCP, follow these steps:

```bash
sudo apt install dnsdist
```

then make this file:
```lua
-- in /etc/dnsdist/dnsdist.conf
setSecurityPollSuffix("")
setMaxUDPOutstanding(10240)
newServer("8.8.8.8") -- this is the upstream server

addLocal("192.168.1.1") -- this is what we listen to.
```

`systemctl restart dnsdist`



## nftables: Absolute Basics

```
apt install nftables
```

Enable at boot:

```
systemctl enable nftables
nft list ruleset
```

## Applying NGFW Rules

>NOTE: Import the nftables.conf file to you testing machine from the repo.

Apply rules

Ensure `/etc/nftables.conf` contains everything by running the command below. You can find the file nftables.conf [here](./nftables.conf)
```
less /etc/nftables.conf
```
After confirming the rules are stored in the location `/etc/nftables.conf`, run the command below
```
nft -f /etc/nftables.conf
```

To enable loading at boot:
```
systemctl enable nftables
```

* * *

10\. From Here → NGFW Stack
---------------------------

At this point you have:

*   working router
*   working NAT
*   working firewall
*   persistent rules

Everything you will build, layers **on top of this**:

| Layer | Depends On |
| --- | --- |
| Geo blocking | prerouting hooks |
| Captive portal | NAT prerouting |
| QoS | mangle + tc |
| Policy routing | fwmark + ip rule |
| NGFW policies | filter input/forward |
| VPN | filter input + forward |

If **this base is wrong**, nothing above it will ever be stable.

