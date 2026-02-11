
# DHCP Relay Across L3 Boundaries (Production-Ready)

This guide describes the method to deploy an `ISC DHCP Relay Agent` with a `ISC-Kea DHCP Server` when clients and server are separated by Layer-3 boundaries (VLANs, routed ports, bridges).


1. Installation

  ```bash
  sudo apt update && sudo apt install isc-dhcp-relay -y
  ```

1. Kea Server Configuration

    - Kea must have a subnet that matches the relay agent’s `gateway address`.

      Example `kea-dhcp4.conf`

      ```json
      {
        "Dhcp4": {
          "interfaces-config": {
            "interfaces": [ "eth0" ]
          },
          "subnet4": [
            {
              "id": 1,
              "subnet": "192.168.10.0/24",
              "pools": [
                { "pool": "192.168.10.50 - 192.168.10.200" }
              ],
              "relay": {
                "ip-address": "192.168.10.1" //This is the gateway address that is expected
              },
              "option-data": [
                { "name": "routers", "data": "192.168.10.1" }
              ]
            }
          ]
        }
      }
      ```

    - `relay.ip-address` must equal the relay agent’s IP on that subnet.


1. Firewall Requirements

    Allow:

    * UDP 67, 68 (DHCPv4)
    * UDP 546, 547 (DHCPv6)


1. Summary Table

    | Aspect           | Flat Network       | Relay-Based Network |
    | ---------------- | ------------------ | ------------------- |
    | L2 boundary      | Same               | Different           |
    | DHCP traffic     | Broadcast          | Unicast via relay   |
    | Subnet selection | Incoming interface | `gateway address`            |
    | Complexity       | Low                | Medium              |


1. Troubleshooting

    Run on the relay host:

    ```bash
    tcpdump -i any port 67 or port 68 -n -vv
    ```

    Expected packet flow:

    1. BOOTREQUEST from `0.0.0.0` on client interface
    2. BOOTREQUEST from `Relay_IP` to `Kea_IP`
    3. BOOTREPLY from `Kea_IP` to `Relay_IP`
    4. BOOTREPLY from `Relay_IP` to client MAC


1. Templated DHCP Relay Units

    This setup allows multiple independent relay instances on one host.

    Service Definition

    `/etc/systemd/system/isc-dhcp-relay@.service`

    ```ini
    [Unit]
    Description=ISC DHCP Relay (%I)
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=forking
    PIDFile=/run/dhcrelay-%I.pid
    EnvironmentFile=/etc/default/isc-dhcp-relay-%I
    ExecStart=/usr/sbin/dhcrelay -q -pf /run/dhcrelay-%I.pid $OPTIONS $INTF_CMD $SERVERS
    Restart=on-failure

    [Install]
    WantedBy=multi-user.target
    ```

    

    ### Instance Configuration Files

    Each instance uses its own file:

    ```
    /etc/default/isc-dhcp-relay-<instance>
    ```

    Example:

    ```bash
    # Interfaces the relay listens on (client-facing and server-facing)
    INTERFACES=""

    # Kea DHCP server IP
    SERVERS="10.50.50.1"

    # Relay options
    # -4  IPv4 only
    # -D  Debug logging
    # -a  Append relay agent info
    # -iu Upstream interface
    # -id Downstream interfaces
    OPTIONS="-4 -D -id br0 -iu eth0"
    INTF_CMD=""
    ```

    Enable the instance:

    ```bash
    systemctl enable --now isc-dhcp-relay@<instance>
    ```


    ⚠️ Critical Rule: The base file must be empty

      ```
      /etc/default/isc-dhcp-relay
      ```

      * File must exist
      * File must contain nothing

      If it contains variables, systemd silently merges them with instance files and breaks relay behavior.

      Correct state:

      ```bash
      ls -l /etc/default/isc-dhcp-relay
      cat /etc/default/isc-dhcp-relay
      ```

      Zero output is correct.


    Sanity Checks

    ```bash
    systemctl status 'isc-dhcp-relay@*'
    ps -ef | grep dhcrelay
    ```

    Each instance must:

    * Have its own PID
    * Bind only intended interfaces
    * Forward only to its configured server
    NOTE:The base `/etc/default/isc-dhcp-relay` file must be empty so that only instance-specific environment files control relay behavior.

    Reference:
    [dhcrelay-man](https://kb.isc.org/docs/isc-dhcp-44-manual-pages-dhcrelay)

    ---
    >TODO: Testing of isc-dhcp-relay over dhcpv6
    ---
# Network Topologies as DHCP Relay Host
Purpose: Configuring the Firewall to appropriately act as a relay agent (For the case of Uplink DHCP) for L2/L3 connectivity including VLANs and Bridges.

1. Flat/Direct DHCP

    Direct connection between Server and Client (No relay).
    ```ini
    # /etc/systemd/network/10-flat.network
    [Match]
    Name=eth0
    [Network]
    Address=192.168.1.1/24
    ```

1. VLAN-based Topology

    Creating tagged interfaces for segmented traffic.
    `10-vlan10.netdev`
    ```ini
    # Creates the vlan itself, similarly we make vlan20---vlan_n
    [NetDev]
    Name=vlan10
    Kind=vlan

    [VLAN]
    Id=10 #Each Vlan gets a specific id
    ```
    `vlan10-trunk.network`
    ```ini
    #Adds the vlans to the physical interface. 
    #Also this interface does not get an IP address. 
    #It must remain un-addressed(In the case of tagged vlans).
    [Match]
    Name=eth1 #Physical Interface from which the Vlans are related to.
    [Network]
    VLAN=vlan10
    ```
    `10-vlan10.network`
    ```ini
    #assigns the ip address to the vlan. similar with vlan20
    [Match]
    Name=vlan10
    [Network]
    Address=10.10.10.1/24
    ```

1. Bridge-based Topology

    Grouping multiple ports into a single logical broadcast domain.
    `br0.netdev`
    ```ini
    # /etc/systemd/network/br0.netdev
    [NetDev]     
    Name=br0     
    Kind=bridge  
    ```
    `br0.network`
    ```ini
    # /etc/systemd/network/br0.network
    [Match]                      
    Name = br0                               
    [Network]                    
    Address = 10.10.10.1/24 
    ```

    `bind.network`
    ```ini
    # /etc/systemd/network/bind.network
    [Match]
    Name=eth0 eth1

    [Network]
    Bridge=br0
    ```
