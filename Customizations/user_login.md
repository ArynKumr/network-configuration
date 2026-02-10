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
***
**REQUIREMENTS:**

* [IP Routes are to configured for nftables](route_rule_setup.md)
* [Interfaces are to configured for nftables](iface_setup.md)
* [TC classes qdiscs and filters are to configured for user setup](tc_setup.md)
* * *
>In the case of bandwidth pool the users under that pool are to to be assigned same class id.
* * *

When creating new users following commands must be ran.
-------

```
nft delete element inet filter blocked_users_v4 { <client_ip> }
nft delete element inet filter blocked_users_macs { <client_mac> }
nft delete element inet filter blocked_users_v4_mac { <client_ip> . <mac_address> }
```

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

### 5\. Deleting Ip-Based User
**Purpose:**  
Deleting the user.
```
nft delete element inet filter allowed_ip4 { <client_ip> }
nft delete element inet nat allowed_ip4 { <client_ip> }
nft delete element inet mangle user4_marks { <client_ip> }
nft delete element inet webfilter ALLOW_ACCESS { <client_ip> }
nft add element inet filter blocked_users_v4 { <client_ip> }
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
### 5\. Deleting MAC-Based User
**Purpose:**  
Deleting the user.
```
nft delete element inet filter allowed_macs { <client_mac> }
nft delete element inet nat allowed_macs { <client_mac> }
nft delete element inet mangle user_mac_marks { <client_mac> : 0x00<isp_mark><tc_class_marks> }
nft delete element inet webfilter ALLOW_ACCESS { <client_ip> }
nft add element inet filter blocked_users_macs { <client_mac> }
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
nft add element inet filter allowed_ip4_mac { <client_ip> . <mac_address> }
```

* * *

### 2\. Captive Portal Bypass (NAT)

**Purpose:**  
Authorize this exact IP–MAC pair to bypass redirection.

```
nft add element inet nat allowed_ip4_mac { <client_ip> . <mac_address> }
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
### 5\. Deleting IP–MAC-Based User
**Purpose:**  
Deleting the user.
```
nft delete element inet filter allowed_ip4_mac { <client_ip> . <mac_address> }
nft delete element inet nat allowed_ip4_mac { <client_ip> . <mac_address> }
nft delete element inet mangle user4_marks { <client_ip> : 0x00<isp_mark><tc_class_marks> }
nft delete element inet webfilter ALLOW_ACCESS { <client_ip> }
nft add element inet filter blocked_users_v4_mac { <client_ip> . <mac_address> }
```
* * *

For a user that has been assigned a ngfw policy, upon the user logout following are the steps to logout that user:
--

USER LOGOUT/Delete
--
For user logout we only need to remove ips of users from policy and mark sets

```
nft delete element inet mangle user4_marks {<policy_vpn_users_ip> : 0x00<isp_id><tc_class_id>}
nft delete element inet filter <policy_vpn_users_set> { <policy_vpn_users_ip> }
nft delete element inet nat <policy_vpn_users_set> { <policy_vpn_users_ip> }
```