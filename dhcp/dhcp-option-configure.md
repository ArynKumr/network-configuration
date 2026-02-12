

# DHCPv4 Option Data in ISC Kea

ISC Kea allows `option-data` to be defined at multiple hierarchy levels.
Each level determines **scope** and **override behavior**.

Hierarchy priority (highest wins):

```
Host Reservation (irrelevant to us)
    ↓
Client Class (Yet to be tested)
    ↓
Subnet (Very Relevant)
    ↓
Shared Network (irrelevant to us)
    ↓
Global (Dhcp4 root)
```




1. Subnet Level

    Applies only to clients within a specific subnet.

    **Use case:** Different gateway or DNS per LAN.

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




1. Client Class Level

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


## Option Override Example

  If defined at multiple levels:
| Level       | DNS value |
|-------------|-----------|
| Global      | 8.8.8.8   |
| Subnet      | 1.1.1.1   |
| Reservation | 9.9.9.9   |


    Client receives:

    ```
    9.9.9.9
    ```

Because reservation overrides subnet and global.


# Recommended Design Pattern

For clean production configs:

* Global → universal defaults
* Subnet → VLAN-specific values
* Client class → device-type overrides
* Reservation → surgical exceptions only

Avoid putting everything globally.
Avoid overusing reservations unless necessary.


# Quick Debug Tip

To confirm what a client actually receives:
```bash
tcpdump -i <interface> -nn -vv port 67 or port 68
```
>Note:Look at the ACK packet and inspect option codes.
