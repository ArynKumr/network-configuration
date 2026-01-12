* * *

NGFW Policy Chains (User-Scoped Firewall Policies)
==================================================

**Purpose:**  
Apply **policy-based firewall behavior** to a predefined group of users **after user creation**, without modifying global rules.

These policies:

*   operate via **dedicated sub-chains**,
*   are activated only when explicitly **jumped to**, and
*   cleanly return control to the main chains when done.

* * *

Policy Chain & User Set Creation
--------------------------------

### 1\. Create Dedicated Policy Chains

**Purpose:**  
Create isolated chains for NAT and Filter logic.  
They do nothing until traffic is explicitly jumped into them.

```
nft add chain inet nat <policy_name>
nft add chain inet filter <policy_name>
```

* * *

### 2\. Create User Membership Sets

**Purpose:**  
Define which users belong to this policy.

```
nft add set inet nat <user_set_name> '{ type ipv4_addr; flags interval; }'
nft add set inet filter <user_set_name> '{ type ipv4_addr; flags interval; }'
```

> **Important:**  
> Sets must exist in **both tables** — nftables tables are isolated.

* * *

NAT-Side Policy Logic (Captive Portal / Redirection Control)
------------------------------------------------------------

### 3\. Global NAT Action (Policy-Level)

**Purpose:**  
Apply a general NAT decision for all users in this policy  
(e.g. bypass captive portal).

```
nft add rule inet nat <policy_name> ip saddr @<user_set_name> <action>
```

* * *

### 4\. Destination-Specific NAT Exception

**Purpose:**  
Apply a NAT action **only** when traffic is headed to a specific destination  
(e.g. allow company website access without authentication).

```
nft add rule inet nat <policy_name> \
    ip saddr @<user_set_name> ip daddr <destination_ip> <action>
```

* * *

### 5\. NAT Exit Ramp

**Purpose:**  
Stop evaluating this policy and return to the main `prerouting` chain.

```
nft add rule inet nat <policy_name> return
```

* * *

FILTER INPUT Policy Logic
-------------------------------------------------------

### 6\. Filter Input: Firewall Access Control (Policy-Level)

**Purpose:**  
Define what users in this policy may do **to the Firewall itself**  
(SSH, Web UI, APIs, etc.).

```
nft add rule inet filter <policy_name> \
    ip saddr @<user_set_name> <action>
```

> Examples:
> 
> *   `accept` → allow Firewall access
> *   `drop` → isolate users from Firewall services
>     

* * *

### 7\. Filter Input: Destination-Specific Firewall Access

**Purpose:**  
Allow or deny access to a **specific Firewall service**.

```
nft add rule inet filter <policy_name> \
    ip saddr @<user_set_name> ip daddr <Firewall_ip> \
    <protocol> dport <service_port> <action>
```

* * *

### 8\. Filter Input Exit Ramp

**Purpose:**  
Return control to the main `input` chain once policy evaluation is complete.

```
nft add rule inet filter <policy_name> return
```

* * *

Policy Activation (Jump Triggers)
---------------------------------

### 9\. NAT Trigger (Prerouting)

**Purpose:**  
As soon as traffic arrives from a policy user,  
evaluate the policy **before global NAT rules**.

```
nft insert rule inet nat prerouting \
    ip saddr @<user_set_name> jump <policy_name>
```

* * *

### 10\. FILTER INPUT Trigger (Firewall-Bound Traffic)

**Purpose:**  
Ensure traffic **to the Firewall itself** is evaluated by the policy.

```
nft insert rule inet filter input \
    ip saddr @<user_set_name> jump <policy_name>
```

* * *