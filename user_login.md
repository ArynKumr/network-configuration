* * *

User Authentication Actions (Login-Time nftables Updates)
=========================================================

**Purpose:**  
Apply firewall, NAT, QoS, and web-filtering permissions **at the moment a user successfully logs in**.

These commands are meant to be executed dynamically by:

*   a captive portal,
*   an authentication daemon,
*   or an orchestration backend.

They **modify live sets/maps** — nothing here is persistent unless saved.

* * *

IPv4-Based Users
----------------

**Use when:**  
The user is identified purely by IPv4 address.

* * *

### 1\. Internet Access (Forward Chain)

**Purpose:**  
Allow the user to pass traffic through the Firewall to the internet.

```
nft add element inet filter allowed_ip4 { <client_ip> }
```

* * *

### 2\. Captive Portal Bypass (NAT)

**Purpose:**  
Stop redirecting this user to the login / splash page.

```
nft add element inet nat allowed_ip4 { <client_ip> }
```

* * *

### 3\. QoS & ISP Routing Mark

**Purpose:**  
Tag all traffic from this IP with a composite mark:  
`0x00[ISP][CLASS]`

```
nft add element inet mangle user4_marks { <client_ip> : 0x00<isp_mark><tc_class_marks> }
```

* * *

### 4\. Enable Web Inspection (HTTP / HTTPS)

**Purpose:**  
Send this user’s web traffic to the NFQUEUE inspection engine.

```
nft add element inet webfilter ALLOW_ACCESS { <client_ip> }
```

* * *

MAC-Based Users
---------------

**Use when:**  
The device must remain authorized even if its IP changes.

* * *

### 1\. Hardware Whitelisting (Filter)

**Purpose:**  
Authorize the device itself, independent of IP address.

```
nft add element inet filter allowed_macs { <client_mac> }
```

* * *

### 2\. Captive Portal Bypass (NAT)

**Purpose:**  
Prevent portal redirection based on MAC identity.

```
nft add element inet nat allowed_macs { <client_mac> }
```

> **Note:**  
> MAC-based NAT bypass is powerful and should be tightly controlled.

* * *

### 3\. QoS & Routing Mark (MAC-Based)

**Purpose:**  
Apply bandwidth and ISP selection based on hardware identity.

```
nft add element inet mangle user_mac_marks { <client_mac> : 0x00<isp_mark><tc_class_marks> }
```

* * *

### 4\. Enable Web Inspection (IP-Level)

**Purpose:**  
Web filtering still operates at L3/L4.  
The current IP must be explicitly added.

```
nft add element inet webfilter ALLOW_ACCESS { <client_ip> }
```

* * *

IPv4 + MAC Bound Users (Highest Trust)
--------------------------------------

**Use when:**  
You want **strong identity binding** — traffic is allowed **only if**  
the IP and MAC pair match.

* * *

### 1\. IP–MAC Security Binding (Filter)

**Purpose:**  
Allow traffic only when `<client_ip>` is seen coming from `<client_mac>`.

```
nft add element inet filter allowed_ip4_mac { <client_ip> . <mac_address> : accept }
```

* * *

### 2\. Captive Portal Bypass (NAT)

**Purpose:**  
Authorize this exact IP–MAC pair to bypass redirection.

```
nft add element inet nat allowed_ip4_mac { <client_ip> . <mac_address> : accept }
```

* * *

### 3\. QoS & Routing Mark (IP-Based)

**Purpose:**  
Attach traffic-control marks for bandwidth management.

```
nft add element inet mangle user4_marks { <client_ip> : 0x00<isp_mark><tc_class_marks> }
```

* * *

### 4\. Enable Web Inspection

**Purpose:**  
Activate web filtering for this user’s traffic.

```
nft add element inet webfilter ALLOW_ACCESS { <client_ip> }
```

* * *