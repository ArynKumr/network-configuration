

# DHCPv4 Option Data in ISC Kea

ISC Kea allows `option-data` to be defined at multiple hierarchy levels.
Each level determines **scope** and **override behavior**.

Hierarchy priority (highest wins):

```
Host Reservation
    ↓
Client Class
    ↓
Subnet
    ↓
Shared Network
    ↓
Global (Dhcp4 root)
```

---

1. Global Level (Server-Wide Options)

Applies to **all clients**, unless overridden at a lower level.

**Use case:** DNS, default gateway, NTP for entire network.

```json
{
  "Dhcp4": {
    "option-data": [
      {
        "name": "domain-name-servers",
        "data": "8.8.8.8, 8.8.4.4"
      },
      {
        "name": "routers",
        "data": "192.168.22.1"
      }
    ]
  }
}
```

Scope: Entire server
Override: Yes (by subnet, class, or reservation)

---

2️. Subnet Level

Applies only to clients within a specific subnet.

**Use case:** Different gateway or DNS per VLAN.

```json
{
  "subnet4": [
    {
      "id": 1,
      "subnet": "192.168.22.0/24",
      "pools": [
        { "pool": "192.168.22.10 - 192.168.22.200" }
      ],
      "option-data": [
        {
          "name": "ntp-servers",
          "data": "216.239.35.0, 216.239.35.4"
        }
      ]
    }
  ]
}
```

Scope: Only this subnet
Override: Yes (by reservation or client class)

---

3. Shared Network Level

Applies to all subnets grouped inside a shared network.

**Use case:** Multiple subnets sharing same physical segment or relay.

```json
{
  "shared-networks": [
    {
      "name": "internal-net",
      "subnet4": [
        { "id": 10, "subnet": "192.168.10.0/24" },
        { "id": 20, "subnet": "192.168.20.0/24" }
      ],
      "option-data": [
        {
          "name": "domain-name",
          "data": "corp.local"
        }
      ]
    }
  ]
}
```

Scope: All subnets in that shared network
Override: Yes (subnet or reservation)

---

4. Client Class Level

Applies only to clients matching a defined class.

**Use case:** Phones, IoT devices, specific vendor class.

```json
{
  "client-classes": [
    {
      "name": "VoIP",
      "test": "option[60].text == 'IPPHONE'",
      "option-data": [
        {
          "name": "tftp-server-name",
          "data": "192.168.22.5"
        }
      ]
    }
  ]
}
```

Scope: Only matching clients
Override: Yes (by reservation)

---

5. Host Reservation Level (Most Specific)

Applies to a specific client (MAC, client-id, etc.).

This has **highest priority**.

**Use case:** Single device custom route or DNS.

```json
{
  "subnet4": [
    {
      "id": 1,
      "subnet": "192.168.22.0/24",
      "reservations": [
        {
          "hw-address": "52:54:00:90:34:02",
          "ip-address": "192.168.22.69",
          "option-data": [
            {
              "name": "classless-static-route",
              "data": "192.168.152.0/24 - 192.168.22.1"
            }
          ]
        }
      ]
    }
  ]
}
```

Scope: One specific host
Override: Overrides everything above

---

## Option Override Example

If defined at multiple levels:

| Level       | DNS value |
| ----------- | --------- |
| Global      | 8.8.8.8   |
| Subnet      | 1.1.1.1   |
| Reservation | 9.9.9.9   |

Client receives:

```
9.9.9.9
```

Because reservation overrides subnet and global.

---

# Recommended Design Pattern

For clean production configs:

* Global → universal defaults
* Subnet → VLAN-specific values
* Client class → device-type overrides
* Reservation → surgical exceptions only

Avoid putting everything globally.
Avoid overusing reservations unless necessary.

---

# Quick Debug Tip

To confirm what a client actually receives:
```bash
tcpdump -i <interface> -nn -vv port 67 or port 68
```
>Note:Look at the ACK packet and inspect option codes.
---
