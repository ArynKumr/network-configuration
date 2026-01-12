* * *

VPN Server Connectivity Rules (nftables)
========================================

**Purpose:**  
Allow a VPN server hosted behind the firewall to:

*   establish an encrypted tunnel from the internet,
*   forward traffic **from VPN clients into the network**, and
*   return traffic **back to VPN clients** reliably.

These rules are intended to be applied:

*   during **initial server setup**, and
*   again at **boot time** to restore VPN connectivity.

* * *

VPN Tunnel Establishment (Inbound)
----------------------------------

**Purpose:**  
Permit incoming VPN handshake traffic from the internet to the Firewall.

```
nft add rule inet filter input \
    iifname @wan_ifaces \
    udp dport <vpn_server_port> \
    <action>
```

**Logic:**

*   `iifname @wan_ifaces` → packet arrived from the internet
*   `udp dport <vpn_server_port>` → VPN listening port
    *   WireGuard: `51820/udp`
    *   OpenVPN: `1194/udp` (default)
*   `<action>` → typically `accept`

* * *

VPN Client Traffic (Inbound → Forward)
--------------------------------------

**Purpose:**  
Allow traffic **originating from VPN clients** to pass through the Firewall.

```
nft add rule inet filter forward \
    iifname <vpn_iface> \
    <action>
```

**Logic:**

*   `iifname <vpn_iface>` → traffic came **from the VPN tunnel**
*   This rule must exist or VPN clients will connect but have **no access**

> **Note:**  
> This rule should appear **before restrictive forward-chain rules**,  
> especially if your default policy is `drop`.

* * *

VPN Client Replies (Outbound → Forward)
---------------------------------------

**Purpose:**  
Allow responses and return traffic **back into the VPN tunnel**.

```
nft add rule inet filter forward \
    oifname <vpn_iface> \
    <action>
```

**Logic:**

*   `oifname <vpn_iface>` → traffic is being sent **to VPN clients**
*   Without this, VPN users can send traffic but never receive replies

* * *