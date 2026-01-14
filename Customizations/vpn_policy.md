* * *

VPN Policy Integration (NGFW-Aligned)
=====================================

**Purpose:**  
Integrate VPN users into the existing NGFW framework so that:

*   VPN traffic is **not blindly trusted**
*   VPN users can be:
    *   fully trusted,
    *   destination-restricted, or
    *   service-restricted
*   all enforcement is done via **sets + policy chains**
*   VPN access can be **revoked instantly** by removing set membership

This avoids the classic mistake of

> “VPN connected = root access to everything”.

* * *

Core Assumptions
----------------

*   VPN tunnel interface exists (e.g. `wg0`, `tun0`)
*   VPN clients are assigned IPs from a known subnet (e.g. `10.10.10.0/24`)
*   QoS / routing marks still apply (optional but recommended)
*   Global VPN connectivity rules (input + forward) already exist  
    _(as documented above)_

* * *

Step 1: Define VPN User Identity
--------------------------------

You **never** write per-client rules.  
You define **who is a VPN user**.

### VPN User Set (Filter + NAT)

```
nft add set inet filter vpn_users '{ type ipv4_addr; flags interval; }'
nft add set inet nat vpn_users '{ type ipv4_addr; flags interval; }'
```

Example:

```
nft add element inet filter vpn_users { 10.10.10.0/24 }
nft add element inet nat vpn_users { 10.10.10.0/24 }
```

This is now your **VPN identity boundary**.

* * *

Step 2: Choose a VPN Policy Case
--------------------------------

VPN users must fall into **one of the same NGFW policy cases** you already use.

There are **no new concepts**.

* * *

VPN POLICY — CASE 1
===================

### Full VPN Trust (Dangerous, but sometimes required)

**Use when:**  
Admins, site-to-site tunnels, infrastructure nodes.

* * *

### Create Policy Chains

```
nft add chain inet nat VPN_FULL_ACCESS
nft add chain inet filter VPN_FULL_ACCESS
```

* * *

### NAT Policy (No Redirection)

```
nft add rule inet nat VPN_FULL_ACCESS \
    ip saddr @vpn_users accept
nft add rule inet nat VPN_FULL_ACCESS return
```

* * *

### FILTER Policy (Unrestricted Forwarding)

```
nft add rule inet filter VPN_FULL_ACCESS \
    ip saddr @vpn_users accept
nft add rule inet filter VPN_FULL_ACCESS return
```

* * *

### Activate Policy

```
nft insert rule inet nat prerouting \
    ip saddr @vpn_users jump VPN_FULL_ACCESS

nft insert rule inet filter forward \
    ip saddr @vpn_users jump VPN_FULL_ACCESS
```

* * *

### Result

*   VPN users bypass NGFW restrictions
*   QoS / routing still applies
*   **Equivalent to NGFW Case-1 (full bypass)**

⚠️ Use sparingly.

* * *

VPN POLICY — CASE 2
===================

### Destination + Service-Restricted VPN Access (RECOMMENDED)

**Use when:**  
VPN users should access:

*   internal apps,
*   specific servers,
*   limited services only.

* * *

### Create Policy Chains

```
nft add chain inet nat VPN_LIMITED_ACCESS
nft add chain inet filter VPN_LIMITED_ACCESS
```

* * *

### NAT Policy (Allow only specific destination)

```
nft add rule inet nat VPN_LIMITED_ACCESS \
    ip saddr @vpn_users ip daddr <internal_ip> accept

nft add rule inet nat VPN_LIMITED_ACCESS return
```

* * *

### FILTER Policy (Outbound)

```
nft add rule inet filter VPN_LIMITED_ACCESS \
    ip saddr @vpn_users ip daddr <internal_ip> \
    tcp dport <service_port> accept
```

* * *

### FILTER Policy (Replies)

```
nft add rule inet filter VPN_LIMITED_ACCESS \
    ip daddr @vpn_users ip saddr <internal_ip> \
    tcp sport <service_port> accept

nft add rule inet filter VPN_LIMITED_ACCESS return
```

* * *

### Activate Policy

```
nft insert rule inet nat prerouting \
    ip saddr @vpn_users jump VPN_LIMITED_ACCESS

nft insert rule inet filter forward \
    ip saddr @vpn_users jump VPN_LIMITED_ACCESS
```

* * *

### Result

*   VPN users only reach approved services
*   Everything else is dropped
*   **Equivalent to NGFW Case-2**

This is the **correct default** for most VPN deployments.

* * *

VPN POLICY — CASE 3
===================

### Destination-Only VPN Access (Protocol-Agnostic)

**Use when:**  
VPN users may talk to **one backend only**, regardless of protocol.

* * *

### Create Policy Chains

```
nft add chain inet nat VPN_DEST_ONLY
nft add chain inet filter VPN_DEST_ONLY
```

* * *

### NAT Policy

```
nft add rule inet nat VPN_DEST_ONLY \
    ip saddr @vpn_users ip daddr <internal_ip> accept
nft add rule inet nat VPN_DEST_ONLY return
```

* * *

### FILTER Policy

```
nft add rule inet filter VPN_DEST_ONLY \
    ip saddr @vpn_users ip daddr <internal_ip> accept

nft add rule inet filter VPN_DEST_ONLY \
    ip daddr @vpn_users accept

nft add rule inet filter VPN_DEST_ONLY return
```

* * *

### Activate Policy

```
nft insert rule inet nat prerouting \
    ip saddr @vpn_users jump VPN_DEST_ONLY

nft insert rule inet filter forward \
    ip saddr @vpn_users jump VPN_DEST_ONLY
```

* * *

### Result

*   VPN users are tightly scoped
*   No service sprawl
*   **Equivalent to NGFW Case-3**

* * *

Optional: QoS & ISP Routing for VPN Users
-----------------------------------------

If VPN users should also obey bandwidth / ISP steering:

```
nft add element inet mangle user4_marks { 10.10.10.0/24 : 0x00<isp><class> }
```

Works exactly like LAN users.

* * *

Revoking VPN Access (Instant Kill)
----------------------------------

No rule deletion required.

```
nft delete element inet filter vpn_users { <client_ip> }
nft delete element inet nat vpn_users { <client_ip> }
```

Connection dies immediately.

* * *