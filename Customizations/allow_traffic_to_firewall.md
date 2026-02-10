Allow Traffic to firewall from WAN
======

Case 1 — Fully Locked (IP + Port + Protocol)
--------------------------------------------
**What it does:** Adds an input rule that accepts packets only when originating from a specific source IP and port, destined for a specific firewall public IP and port, with a matching protocol.

```bash
nft add rule inet filter input \
    ip saddr <source_remote_ip> \
    <protocol> sport <source_remote_port> \
    ip daddr <firewall_public_isp_ip> \
    <protocol> dport <firewall_public_isp_port> \
    accept
```

* * *

Case 2 — Public Service (Port Only)
-----------------------------------
**What it does:** Adds an input rule that accepts packets destined for a specific firewall public IP and port, regardless of source IP or port.

```bash
nft add rule inet filter input \
    ip daddr <firewall_public_isp_ip> \
    <protocol> dport <firewall_public_isp_port> \
    accept
```

* * *

Case 3 — Port-Restricted Clients (Any IP)
-----------------------------------------

**What it does:** Adds an input rule that accepts packets from any source IP, but only if they originate from a specific source port and are destined for a specific firewall public IP and port.

```bash
nft add rule inet filter input \
    <protocol> sport <source_remote_port> \
    ip daddr <firewall_public_isp_ip> \
    <protocol> dport <firewall_public_isp_port> \
    accept
```

* * *

Case 4 — IP-Restricted Clients (Any Source Port)
------------------------------------------------

**What it does:** Adds an input rule that accepts packets from a specific source IP destined for a specific firewall public IP and port, but allows any source port.

```bash
nft add rule inet filter input \
    ip saddr <source_remote_ip> \
    ip daddr <firewall_public_isp_ip> \
    <protocol> dport <firewall_public_isp_port> \
    accept
```

* * *