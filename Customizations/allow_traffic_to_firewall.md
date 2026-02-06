Allow Traffic to firewall from WAN
======

Case 1 — Fully Locked (IP + Port + Protocol)
--------------------------------------------

**Most secure**

```bash
nft add rule inet filter input \
    ip saddr <source_remote_ip> \
    <protocol> sport <source_remote_port> \
    ip daddr <firewall_public_isp_ip> \
    <protocol> dport <firewall_public_isp_port> \
    accept
```

### Use when:

*   static remote peer
*   known client port
*   strict compliance

* * *

Case 2 — Public Service (Port Only)
-----------------------------------

```bash
nft add rule inet filter input \
    ip daddr <firewall_public_isp_ip> \
    <protocol> dport <firewall_public_isp_port> \
    accept
```

### Use when:

*   public-facing service
*   client IPs unknown
*   still protocol + port scoped

* * *

Case 3 — Port-Restricted Clients (Any IP)
-----------------------------------------

```bash
nft add rule inet filter input \
    <protocol> sport <source_remote_port> \
    ip daddr <firewall_public_isp_ip> \
    <protocol> dport <firewall_public_isp_port> \
    accept
```

### Use when:

*   client software uses fixed source port
*   IPs change (NAT, CGNAT)

⚠️ Less secure than Case 1.

* * *

Case 4 — IP-Restricted Clients (Any Source Port)
------------------------------------------------

```bash
nft add rule inet filter input \
    ip saddr <source_remote_ip> \
    ip daddr <firewall_public_isp_ip> \
    <protocol> dport <firewall_public_isp_port> \
    accept
```

### Use when:

*   trusted IP
*   dynamic client ports

* * *

Security Model Summary
----------------------

| Case | IP Scoped | Port Scoped | Security |
| --- | --- | --- | --- |
| 1 | ✅ | ✅ | Highest |
| 2 | ❌ | ✅ | Medium |
| 3 | ❌ | ⚠️ partial | Medium-Low |
| 4 | ✅ | ❌ | Medium |

* * *