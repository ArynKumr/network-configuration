* * *

GeoIP Set Management (Add / Delete / Flush Subnets)
===================================================

**Purpose:**  
Safely manage large GeoIP subnet lists in the `inet geo` table, including:

*   removing specific subnets,
*   completely emptying GeoIP sets, and
*   bulk-loading subnets from files.

This applies to both **IPv4** and **IPv6** geofencing sets.

* * *

Target Sets
-----------

*   `inet geo geo_v4` → IPv4 country subnets
*   `inet geo geo_v6` → IPv6 country prefixes

These sets **must already exist**.

* * *

1\. Delete Specific Subnets (Selective Removal)
-----------------------------------------------

**Use when:**  
You want to remove _only certain subnets_ from the GeoIP sets  
(e.g. correcting bad GeoIP data, unblocking a region).

### IPv4

```
nft delete element inet geo geo_v4 { $(subnets) }
```

### IPv6

```
nft delete element inet geo geo_v6 { $(subnets) }
```

**Notes:**

*   `$(subnets)` must expand to a **comma-separated list** of valid CIDRs
*   Non-existent elements are silently ignored
*   No reload required — changes apply immediately

* * *

2\. Completely Empty GeoIP Sets (Hard Reset)
--------------------------------------------

**Use when:**  
You want to **disable geofencing entirely** or rebuild the list from scratch.

### Flush IPv4 GeoIP Set

```
nft flush set inet geo geo_v4
```

### Flush IPv6 GeoIP Set

```
nft flush set inet geo geo_v6
```

**Important:**

*   This removes **all entries**
*   The set still exists — only contents are wiped
*   Geofencing becomes effectively disabled until reloaded

* * *

3\. GeoIP Subnet File Format (Bulk Load)
----------------------------------------

**Use when:**  
Managing **large country IP lists** via files (recommended).

### File Example (`geo_v4_subnets.nft`)
```
`geo_v4_subnets.nft`
add element inet geo geo_v4 { $(subnets) }
```

### File Example (`geo_v6_subnets.nft`)

```
`geo_v6_subnets.nft`
add element inet geo geo_v6 { $(subnets) }
```

**Requirements:**

*   `$(subnets)` must expand before execution  
    (e.g. via shell substitution or template generation)
*   CIDRs must match the set type:
    *   `geo_v4` → IPv4 only
    *   `geo_v6` → IPv6 only

* * *

4\. Apply the Subnet File
-------------------------

Once the file is created:

```
nft -f <path/to/subnet_file>
```

**Behavior:**

*   Adds subnets incrementally
*   Does **not** flush existing entries unless explicitly done beforehand
*   Safe to run multiple times (idempotent for identical CIDRs)

* * *

Recommended Safe Update Workflow (DO THIS)
------------------------------------------

```
# 1. Flush old data
nft flush set inet geo geo_v4
nft flush set inet geo geo_v6

# 2. Load new GeoIP data
nft -f /path/to/geo_v4_subnets.nft
nft -f /path/to/geo_v6_subnets.nft
```

This avoids:

*   stale prefixes,
*   partial country blocks,
*   silent false positives.

* * *

