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
nft add element inet filter allowed_ip4 { <local_ip> }
```

* * *

#### 2\. Captive Portal & NAT Bypass

Prevent any NAT-based redirection (portal, DNS hijack, etc.).

```
nft add element inet nat allowed_ip4 { <local_ip> }
```

* * *

#### 3\. QoS & ISP Routing Mark

Attach the user to a specific ISP and bandwidth class.

```
nft add element inet mangle user4_marks { <local_ip> : 0x00<isp_mark><tc_class_marks> }
```

* * *

#### 4\. High-Priority NAT Override

Force an immediate NAT decision for this user.

```
nft insert rule inet nat prerouting ip saddr <local_ip> <action>
```

**Typical `<action>`:**

*   `accept`
*   `return`
*   `dnat to …`

* * *

#### 5\. Forward Chain Override (Outbound)

Allow traffic **from the user** regardless of global policy.

```
nft insert rule inet filter forward ip saddr <local_ip> <action>
```

* * *

#### 6\. Forward Chain Override (Inbound / Replies)

Allow return traffic **to the user**.

```
nft insert rule inet filter forward ip daddr <local_ip> <action>
```

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

```
nft add element inet filter allowed_ip4 { <local_ip> }
nft add element inet nat allowed_ip4 { <local_ip> }
```

* * *

#### 2\. QoS & Routing Mark

```
nft add element inet mangle user4_marks { <local_ip> : 0x00<isp_mark><tc_class_marks> }
```

* * *

#### 3\. Destination-Specific NAT Handling

```
nft insert rule inet nat prerouting \
    ip saddr <local_ip> ip daddr <destination_ip> <action>
```

* * *

#### 4\. Forwarding Rule (Outbound Direction)

Allow traffic **from user → destination** only on specified ports.

```
nft insert rule inet filter forward \
    ip saddr <local_ip> ip daddr <destination_ip> \
    <protocol> sport <source_port> \
    <protocol> dport <destination_port> \
    <action>
```

* * *

#### 5\. Forwarding Rule (Inbound / Replies)

Allow return traffic **from destination → user**.

```
nft insert rule inet filter forward \
    ip daddr <local_ip> ip saddr <destination_ip> \
    <protocol> sport <source_port> \
    <protocol> dport <destination_port> \
    <action>
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
nft add element inet filter allowed_ip4 { <local_ip> }
nft add element inet nat allowed_ip4 { <local_ip> }
```

* * *

#### 2\. QoS & Routing Mark

```
nft add element inet mangle user4_marks { <local_ip> : 0x00<isp_mark><tc_class_marks> }
```

* * *

#### 3\. Destination-Specific NAT Exemption

```
nft insert rule inet nat prerouting \
    ip saddr <local_ip> ip daddr <destination_ip> <action>
```

* * *

#### 4\. Forwarding Rule (Outbound)

```
nft insert rule inet filter forward \
    ip saddr <local_ip> ip daddr <destination_ip> <action>
```

* * *

#### 5\. Forwarding Rule (Inbound / Replies)

```
nft insert rule inet filter forward \
    ip daddr <local_ip> <action>
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