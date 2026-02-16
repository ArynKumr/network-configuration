* * *

Permanent MAC Block (Layer-2 Enforcement)
================================================

Purpose
-------

This module permanently blocks specific devices based on their **Ethernet MAC address**, regardless of:

* * *

### Effect

Blocks traffic **destined to the firewall itself** from blocked MACs.Blocks traffic being routed **through** the firewall.

* * *

Adding a MAC to Block
---------------------

```bash
nft add element inet filter perma_blocked_mac_users { <to_be_blocked_mac_address> }
```

Example:

```bash
nft add element inet filter perma_blocked_mac_users { aa:bb:cc:dd:ee:ff }
```

* * *

One-Line Summary
----------------

> This module enforces hard Layer-2 denial by dropping all traffic from specified MAC addresses in both INPUT and FORWARD chains before any higher-level policy evaluation occurs.