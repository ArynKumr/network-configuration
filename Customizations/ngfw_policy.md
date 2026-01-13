NGFW Policy Framework (Set-Based, Chain-Driven)
===============================================

**Purpose:**  
Apply **group-based firewall policies** to already-created users using:

*   dedicated policy chains,
*   user membership sets,
*   explicit NAT + FILTER symmetry,
*   predictable control flow (`jump` → policy → `return`).

Policies are **reusable**, **auditable**, and **time-bound**.

* * *

Core Concepts (Do Not Skip)
---------------------------

### 1\. Policies are **chains**, not rules

They do nothing until traffic is explicitly jumped into them.

### 2\. Users are assigned via **sets**

No per-user rules. Membership decides behavior.

### 3\. NAT and FILTER are **both required**

NAT changes traffic direction.  
FILTER decides if traffic is allowed.

Missing either = broken policy.

* * *

Common Setup (Required for ALL Policies)
----------------------------------------

### Create Policy Chains

```
nft add chain inet nat <policy_name>
nft add chain inet filter <policy_name>
```

* * *

### Create Policy Membership Sets

```
nft add set inet nat <policy_user_set> '{ type ipv4_addr; flags interval; }'
nft add set inet filter <policy_user_set> '{ type ipv4_addr; flags interval; }'
```

> `flags interval` allows subnet-level policies.

* * *

### Policy Triggers (Activation)

These rules **activate** the policy.

```
nft insert rule inet nat prerouting \
    ip saddr @<policy_user_set> jump <policy_name>

nft insert rule inet filter forward \
    ip saddr @<policy_user_set> jump <policy_name>
```

Traffic now enters the policy **before global logic**.

* * *

POLICY CASES
============

Each policy must clearly declare **which case it implements**.

* * *

Case 1: Full Policy Bypass (Group Trust)
----------------------------------------

**Use when:**  
A group should bypass **all firewall restrictions**, while still:

*   being NATed correctly,
*   retaining QoS / ISP routing marks.

This is **maximum trust**.

* * *

### NAT Policy (Bypass All Redirection)

```
nft add rule inet nat <policy_name> \
    ip saddr @<policy_user_set> accept
```

```
nft add rule inet nat <policy_name> return
```

* * *

### FILTER Policy (Bypass All Filtering)

```
nft add rule inet filter <policy_name> \
    ip saddr @<policy_user_set> accept
```

```
nft add rule inet filter <policy_name> return
```

* * *

### Result

*   No captive portal
*   No geo blocking
*   No protocol restrictions
*   Global QoS / routing still applies

This is equivalent to **Case 1 in NGFW rules**.

* * *

Case 2: Destination + Port / Protocol Controlled Policy
-------------------------------------------------------

**Use when:**  
Users are mostly trusted, but access must be restricted to:

*   specific destination IPs,
*   specific ports,
*   specific protocols.

This is **controlled trust**.

* * *

### NAT Policy (Destination-Specific Bypass)

```
nft add rule inet nat <policy_name> \
    ip saddr @<policy_user_set> ip daddr <destination_ip> <action>
```

```
nft add rule inet nat <policy_name> return
```

* * *

### FILTER Policy (Outbound Control)

```
nft add rule inet filter <policy_name> \
    ip saddr @<policy_user_set> ip daddr <destination_ip> \
    <protocol> dport <service_port> <action>
```

* * *

### FILTER Policy (Inbound / Replies)

```
nft add rule inet filter <policy_name> \
    ip daddr @<policy_user_set> ip saddr <destination_ip> \
    <protocol> sport <service_port> <action>
```

```
nft add rule inet filter <policy_name> return
```

* * *

### Result

*   Only defined services work
*   Everything else dies at policy boundary
*   Global firewall remains intact

Matches **Case 2 in NGFW rules**.

* * *

Case 3: Destination-Only Policy (Protocol-Agnostic)
---------------------------------------------------

**Use when:**  
A group should communicate **only with a specific IP**, regardless of port or protocol.

Useful for:

*   partner systems,
*   site-to-site backends,
*   fixed SaaS endpoints.

* * *

### NAT Policy

```
nft add rule inet nat <policy_name> \
    ip saddr @<policy_user_set> ip daddr <destination_ip> <action>
```

```
nft add rule inet nat <policy_name> return
```

* * *

### FILTER Policy (Outbound)

```
nft add rule inet filter <policy_name> \
    ip saddr @<policy_user_set> ip daddr <destination_ip> accept
```

* * *

### FILTER Policy (Inbound / Replies)

```
nft add rule inet filter <policy_name> \
    ip daddr @<policy_user_set> accept
```

```
nft add rule inet filter <policy_name> return
```

* * *

### Result

*   User is globally restricted
*   Only traffic to the destination works
*   Clean, predictable behavior

Matches **Case 3 in NGFW rules**.

* * *

Firewall (Router) Access Control — OPTIONAL EXTENSION
-----------------------------------------------------

If the policy also needs to control access **to the firewall itself**:

```
nft add rule inet filter <policy_name> \
    ip saddr @<policy_user_set> ip daddr <firewall_ip> \
    <protocol> dport <service_port> <action>
```

Place **before** the final `return`.
