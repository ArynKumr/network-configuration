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

VPN Client Traffic (Inbound → Forward)
--------------------------------------

**Purpose:**  
Allow traffic **originating from VPN clients** to pass through the Firewall.

```
nft add rule inet filter forward ip saddr <vpn_subnet>  <action>
```

**Logic:**

*   `iifname <vpn_iface>` → traffic came **from the VPN tunnel**
*   This rule must exist or VPN clients will connect but have 
**no access**
*   **Typical <vpn_iface>:** tun0,wg0,etc.
>Note: check the exact name of the vpn interface with the command `ip -a` on the firewall.

> **Note:**  
> This rule should appear **before restrictive forward-chain rules**,  
> especially if your default policy is `drop`.

* * *

VPN Client Replies (Outbound → Forward)
---------------------------------------

**Purpose:**  
Allow responses and return traffic **back into the VPN tunnel**.

```
nft add rule inet filter forward ip daddr <vpn_subnet>  <action>
```

**Logic:**

*   `oifname <vpn_iface>` → traffic is being sent **to VPN clients**
*   Without this, VPN users can send traffic but never receive replies

* * *