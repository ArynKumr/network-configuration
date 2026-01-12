* * *

NGFW User Policy Overrides (nftables)
=====================================

**Purpose:**  
Apply **explicit user-level exceptions** to the firewall.  
These rules are used when a device must:

*   bypass global firewall enforcement,
*   bypass captive portal redirection,
*   retain QoS / ISP routing marks, and
*   optionally receive granular access to Firewall services.

This is **override logic** — it intentionally weakens default protections.

* * *

Case 1: Full Firewall Bypass (Trusted User)
-------------------------------------------

**Use when:**  
A user/device must bypass **all firewall restrictions**, while still:

*   being routable,
*   bypassing the captive portal, and
*   retaining QoS / ISP routing marks.

* * *

### 1\. Global Permission (Forward Chain)

**Purpose:**  
Allow the device to forward traffic through the Firewall to the internet.

```
nft add element inet filter allowed_ip4 { <local_ip> }
```

* * *

### 2\. Captive Portal Bypass (NAT)

**Purpose:**  
Stop HTTP/HTTPS/DNS hijacking for this user.

```
nft add element inet nat allowed_ip4 { <local_ip> }
```

* * *

### 3\. Bandwidth & Routing Mark (Mangle)

**Purpose:**  
Attach ISP ID and TC class to all traffic from this user.

```
nft add element inet mangle user4_marks { <local_ip> : 0x00<isp_mark><tc_class_marks> }
```

* * *

### 4\. Immediate NAT Override (High Priority)

**Purpose:**  
Force an early NAT decision before any other redirection logic.

```
nft insert rule inet nat prerouting ip saddr <local_ip> <action>
```

* * *

### 5\. Firewall Access Control (Inbound → Firewall)

**Purpose:**  
Control whether this user may access Firewall-local services  
(e.g. SSH, Web UI, APIs).

```
nft add rule inet filter input ip saddr <local_ip> <action>
```

* * *

### 6\. Firewall → Client Communication

**Purpose:**  
Allow or deny traffic originating from the Firewall back to the client.

```
nft add rule inet filter input ip daddr <local_ip> <action>
```

* * *

Case 2: Port / Protocol / Destination-Controlled Access
-------------------------------------------------------

_(User is otherwise exempt from global firewall rules)_

**Use when:**  
A user should bypass most enforcement but still be constrained  
to specific ports, protocols, or destinations.

* * *

### Section 1: Global Access Enablement

```
nft add element inet filter allowed_ip4 { <local_ip> }
nft add element inet nat allowed_ip4 { <local_ip> }
```

* * *

### Section 2: Traffic Labeling (QoS & ISP Routing)

```
nft add element inet mangle user4_marks { <local_ip> : 0x00<isp_mark><tc_class_marks> }
```

* * *

### Section 3: Destination-Specific NAT Rule

**Purpose:**  
Apply a NAT decision only when traffic is headed to a specific destination  
(e.g. split tunneling, forced proxy, VPN bypass).

```
nft insert rule inet nat prerouting \
    ip saddr <local_ip> ip daddr <destination_ip> <action>
```

* * *

### Section 4: Firewall Interaction (Granular)

**Purpose:**  
Allow precise access from this user to a Firewall-local service.

```
nft add rule inet filter input \
    ip saddr <local_ip> ip daddr <destination_ip> \
    <protocol> sport <source_port> \
    <protocol> dport <destination_port> \
    <action>
```

* * *

### Emergency Firewall Access Rule

**Purpose:**  
Decide whether the Firewall should accept _any_ direct traffic from this user.

```
nft add rule inet filter input ip daddr <local_ip> <action>
```

* * *

Case 3: Destination-Only Managed Access
---------------------------------------

_(IP-based, otherwise fully exempt)_

**Use when:**  
A device should be:

*   globally trusted,
*   portal-exempt,
*   QoS-managed,
*   but **restricted only when talking to specific destinations**.

* * *

### 1\. Permanent Forward Whitelist

```
nft add element inet filter allowed_ip4 { <local_ip> }
```

* * *

### 2\. Portal Bypass

```
nft add element inet nat allowed_ip4 { <local_ip> }
```

* * *

### 3\. QoS / ISP Marking

```
nft add element inet mangle user4_marks { <local_ip> : 0x00<isp_mark><tc_class_marks> }
```

* * *

### 4\. Destination-Specific NAT Exemption

**Purpose:**  
Ensure this destination is handled **before** any global redirection.

```
nft insert rule inet nat prerouting \
    ip saddr <local_ip> ip daddr <destination_ip> <action>
```

* * *

### 5\. Administrative Access (Client → Firewall)

```
nft add rule inet filter input \
    ip saddr <local_ip> ip daddr <destination_ip> <action>
```

* * *

### 6\. Firewall → Client Replies

```
nft add rule inet filter input ip daddr <local_ip> <action>
```

