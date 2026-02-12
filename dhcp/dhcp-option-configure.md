

# DHCPv4 Option Data in ISC Kea

ISC Kea allows `option-data` to be defined at multiple hierarchy levels, below is mentioned at what levels we require.

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



# Recommended Design Pattern

For clean production config:
* Subnet → VLAN-specific values
* Client class → device-type overrides



# Quick Debug Tip

To confirm what a client actually receives:
```bash
tcpdump -i <interface> -nn -vv port 67 or port 68
```
>Note:Look at the ACK packet and inspect option codes.
