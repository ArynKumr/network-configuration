* * *

NGFW Rule Application (User-Level Firewall Overrides)
=====================================================

**Purpose:**  
Apply **explicit firewall overrides** for selected users **after identity is known**.  
These rules intentionally bypass or partially bypass the default NGFW pipeline.

This layer is used for:

*   trusted devices,
*   administrators,
*   exceptions,
*   controlled partner access.

> ⚠️ **Warning:**  
> Misuse of these rules can completely bypass security controls.  
> These are **operator-only actions**.

* * *

Case 1: Full Firewall Bypass (Unrestricted User)
------------------------------------------------

**Use when:**  
A device must bypass **all firewall restrictions**, while still:

*   participating in QoS / ISP routing,
*   traversing NAT correctly.

This user is effectively **trusted root on the network**.

* * *

### Rules Applied

#### 1\. Forwarding Permission (Filter)

Allow the user to forward traffic through the firewall.

```
nft insert rule inet filter forward ip daddr <local_ip> accept
nft insert rule inet filter forward ip saddr <local_ip> accept
```

* * *

#### 2\. Captive Portal & NAT Bypass

Prevent any NAT-based redirection (portal, DNS hijack, etc.).

```
nft insert rule inet nat prerouting ip daddr <local_ip> accept
nft insert rule inet nat prerouting ip saddr <local_ip> accept
```

* * *

#### 3\. QoS & ISP Routing Mark

Attach the user to a specific ISP and bandwidth class.

```
nft add element inet mangle user4_marks { <local_ip> : 0x00<isp_mark><tc_class_marks> }
```

* * *

#### 4\. NAT Masquerading

Force an immediate NAT decision for this user.

```
nft insert rule inet nat postrouting oifname @wan_ifaces ip saddr <local_ip> masquerade
```

**Typical `<action>`:**

*   `accept`
*   `return`
*   `dnat to …`

* * *

### Resulting Behavior

*   No firewall filtering
*   No captive portal
*   No geo restrictions
*   QoS and routing still enforced

This is **maximum privilege**.

* * *

Case 2: Port / Protocol / Destination-Controlled Access
-------------------------------------------------------

_(User is otherwise exempt from global firewall rules)_

**Use when:**  
A user should bypass global enforcement **except** for:

*   specific ports,
*   specific protocols,
*   specific destination IPs.

This is **surgical trust**, not blanket trust.

* * *

### Rules Applied

#### 1\. Global Bypass Enablement
Allow traffic **from user → destination** only on specified ports.
Allow return traffic **from destination → user**.
```
nft insert rule inet filter forward ip daddr <local_ip> ip saddr <destination_ip> tcp dport <destination_port> accept
nft insert rule inet filter forward ip saddr <local_ip> ip daddr <destination_ip> tcp sport <local_port> accept
```

* * *

#### 2\. QoS & Routing Mark

```
nft add element inet mangle user4_marks { <local_ip> : 0x00<isp_mark><tc_class_marks> }
```

* * *

#### 3\. NAT Handling

```
nft insert rule inet nat prerouting ip daddr <local_ip> ip saddr <destination_ip> tcp dport <destination_port> accept
nft insert rule inet nat prerouting ip saddr <local_ip> ip daddr <destination_ip> tcp sport <local_port> accept
```

* * *

#### 4\. NAT Masquerading

```
nft insert rule inet nat postrouting oifname @wan_ifaces ip saddr <local_ip> ip daddr <destination_ip> tcp sport <local_port> masquerade
```

* * *

### Resulting Behavior

*   User bypasses general firewall rules
*   Only specified services are reachable
*   All other traffic still dies at policy drop

* * *

Case 3: Destination-IP–Only Managed Access
------------------------------------------

_(Protocol-agnostic, IP-scoped trust)_

**Use when:**  
A user is trusted **only when communicating with a specific IP**,  
regardless of protocol or port.

* * *

### Rules Applied

#### 1\. Global Bypass Enablement

```
nft insert rule inet filter forward ip daddr <local_ip> ip saddr <destination_ip> accept
nft insert rule inet filter forward ip saddr <local_ip> ip daddr <destination_ip> accept
```

* * *

#### 2\. QoS & Routing Mark

```
nft add element inet mangle user4_marks { <local_ip> : 0x00<isp_mark><tc_class_marks> }
```

* * *

#### 3\. NAT Exemption

```
nft insert rule inet nat prerouting ip saddr <local_ip> ip daddr <destination_ip> accept
nft insert rule inet nat prerouting ip daddr <local_ip> ip saddr <destination_ip> accept
```

* * *

#### 4\. NAT Masquerading

```
nft insert rule inet nat postrouting oifname @wan_ifaces ip saddr <local_ip> ip daddr <destination_ip> masquerade
```

* * *

### Resulting Behavior

*   User is globally trusted
*   Enforcement applies **only** based on destination IP
*   Suitable for:
    *   site-to-site links,
    *   partner systems,
    *   fixed backends

* * *