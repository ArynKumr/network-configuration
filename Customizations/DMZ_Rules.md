Matching Truth Table
---------------------------

| Field | Remote Source IP | Public ISP IP | Public Port | Protocol | DNAT Target IP | DNAT Target Port | Action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Case 1 | ALL | Specific | Specific | tcp/udp | Specific | Specific | allow |
| Case 2 | ALL | Specific | Range | tcp/udp | Specific | Range | allow |
| Case 3 | ALL | Specific | ALL | tcp/udp | Specific | ALL | allow |
| Case 4 | Specific | Specific | Specific | tcp/udp | Specific | Specific | allow |
| Case 5 | Specific | Specific | Range | tcp/udp | Specific | Range | allow |
| Case 6 | Specific | Specific | ALL | tcp/udp | Specific | ALL | allow |




1. Case 1

    **Meaning:**  

    Anyone from public connecting to a specific port of our firewall's specific ISP ip, connects to a specific local port on a local machine.

    Example:
    - Firewall has 2 ISPs, Airtel and BSNL.
    - Someone connecting from Airtel's public IP, port 8000
    - Their connection goes to local IP 10.1.1.81:8000

    **Rules:**  



    ```bash
    nft add element inet filter allowed_ip4 { <client_ip> }
    nft add rule inet mangle prerouting ip saddr <client_ip> <protocol> sport <client_port> meta mark set 0x00<isp_mark><tc_class_marks>
    nft add rule inet mangle forward ip daddr <client_ip> <protocol> dport <client_port> meta mark set 0x00<isp_mark><tc_class_marks>
    nft insert rule inet nat NAT_PRE ip daddr <public_facing_isp_ip> <protocol> dport <public_facing_isp_port> dnat to <client_ip>:<client_port>
    nft insert rule inet filter FILTER_FORWARD ip daddr <client_ip> <action>
    ```

    **Explanation:**  

    1. Adds the client to the global whitelist so the firewall allows general outgoing traffic.
    1. Tags traffic originating from the internal client and source port. Used for ISP/QoS classification of **outgoing** traffic.
    1. Tags traffic destined **to** the internal client. Allows control of incoming bandwidth so downloads don’t saturate the network.
    1. Ensures traffic hitting the public WAN IP on a specific port is redirected to the internal host.
    1. Since the `forward` chain policy is `drop`, forwarded packets must be explicitly allowed **after DNAT**.

1. Case 2

    **Meaning:**  

    Anyone from public connecting to a range of ports on our firewall's specific ISP ip, connects to a corresponding port range on a local machine.

    Example:
    - Firewall has 2 ISPs, Airtel and BSNL.
    - Someone connecting from Airtel's public IP, ports 8000-8100
    - Their connection goes to local IP 10.1.1.81:8000-8100

    **Rules:**  

    ```bash
    nft add element inet filter allowed_ip4 { <client_ip> }
    nft add rule inet mangle prerouting ip saddr <client_ip> <protocol> sport <starting_client_port>-<ending_client_port>  meta mark set 0x00<isp_mark><tc_class_marks>
    nft add rule inet mangle forward ip daddr <client_ip> <protocol> dport <starting_client_port>-<ending_client_port> meta mark set 0x00<isp_mark><tc_class_marks>
    nft insert rule inet nat NAT_PRE ip daddr <public_facing_isp_ip> <protocol> dport <starting_public_facing_isp_port>-<ending_public_facing_isp_port> dnat to <client_ip>:<starting_client_port>-<ending_client_port>
    nft insert rule inet filter FILTER_FORWARD ip daddr <client_ip> <action>
    ```


    **Explanation:**  

    1. Adds the client to the global whitelist so the firewall allows general outgoing traffic.
    1. Tags traffic originating from the internal client and source ports.
    Used for ISP/QoS classification of **outgoing** traffic.
    1. Tags traffic destined **to** the internal client.
    Allows control of incoming bandwidth so downloads don’t saturate the network.
    1. Ensures traffic hitting the public WAN IP on a specific pool of port is redirected to the internal host.
    1. Since the `forward` chain policy is `drop`, forwarded packets must be explicitly allowed **after DNAT**.

    > Note: Ensure traffic hitting the public WAN IP on a specific port range (eg 1000-2000) is redirected to the same  internal ports (1000-2000) and mapped one to one.

    > Different ranges are NOT ALLOWED. eg: internal 1000-2000 CANNOT BE MAPPED TO external 2000-3000 

1. Case 3

    **Meaning:**  

    Anyone from public connecting to any port on our firewall's specific ISP ip, connects to the same internal machine for all ports.

    Example:
    - Firewall has 2 ISPs, Airtel and BSNL.
    - Someone connecting from any public IP to any port on Airtel's ISP IP
    - Their connection goes to local IP 10.1.1.81 on the same port

    **Rules:**  

    ```bash
    nft add element inet filter allowed_ip4 { <client_ip> }
    nft add element inet mangle user4_marks { <client_ip> : 0x00<isp_mark><tc_class_marks> }
    nft insert rule inet nat NAT_PRE ip daddr <public_facing_isp_ip> dnat to <client_ip>
    nft insert rule inet filter FILTER_FORWARD ip daddr <client_ip> <action>
    ```


    **Explanation:**  
    1. Allows the internal client to send traffic **out** to the internet. Without this, the host can receive packets but cannot reply.
    1. Labels all traffic from the client for bandwidth management. Ensures forwarded DMZ traffic still respects TC class limits.
    1. All packets hitting the public ISP IP are destination-NATed to the internal client before routing decisions occur.
    1. Explicitly allows traffic through the `forward` chain. Required when the default policy is `drop`.

    ***
    OR(For specific protocol)
    -

    Full DNAT to a specific internal client for all incoming traffic using a specific protocol on a public IP, allowing any remote source IP to access all ports on the internal service.

    **Rules:**  

    ```bash
    nft add element inet filter allowed_ip4 { <client_ip> }
    nft add element inet mangle user4_marks { <client_ip> : 0x00<isp_mark><tc_class_marks> }
    nft insert rule inet nat NAT_PRE ip daddr <public_facing_isp_ip> ip protocol <protocol> dnat to <client_ip>
    nft insert rule inet filter FILTER_FORWARD ip daddr <client_ip> <action>
    ```


    **Explanation:**  
    1. Allows the internal client to send traffic **out** to the internet. Without this, the host can receive packets but cannot reply.
    1. Labels all traffic from the client for bandwidth management. Ensures forwarded DMZ traffic still respects TC class limits.
    1. All packets hitting the public ISP IP are destination-NATed to the internal client before routing decisions occur.
    1. Explicitly allows traffic through the `forward` chain. Required when the default policy is `drop`.


1. Case 4

    **Meaning:**  

    Traffic from a specific remote source IP connecting to a specific port on our firewall's specific ISP IP connects to a specific local port on a local machine.

    Example:
    - Firewall has 2 ISPs, Airtel and BSNL.
    - Someone from a specific public IP connecting to Airtel's public IP, port 8000
    - Their connection goes to local IP 10.1.1.81:8000
    - Only this specific source IP can access this service.

    **Rules:**  

    ```bash
    nft add element inet filter allowed_ip4 { <client_ip> }
    nft add rule inet mangle prerouting ip saddr <client_ip> <protocol> sport <client_port> meta mark set 0x00<isp_mark><tc_class_marks>
    nft add rule inet mangle forward ip daddr <client_ip> <protocol> dport <client_port> meta mark set 0x00<isp_mark><tc_class_marks>
    nft insert rule inet nat NAT_PRE ip saddr <public_remote_ip> ip daddr <public_facing_isp_ip> <protocol> dport <public_facing_isp_port> dnat to <client_ip>:<client_port>
    nft insert rule inet filter FILTER_FORWARD ip saddr <public_remote_ip> ip daddr <client_ip> <action>
    ```


    **Explanation:**  

    1. Adds the client to the global whitelist so the firewall allows general outgoing traffic.
    1. Tags traffic originating from the internal client and source port. Used for ISP/QoS classification of **outgoing** traffic.
    1. Tags traffic destined **to** the internal client. Allows control of incoming bandwidth so downloads don't saturate the network.
    1. Ensures traffic hitting the public WAN IP on a specific port from a specific source is redirected to the internal host.
    1. Since the `forward` chain policy is `drop`, forwarded packets must be explicitly allowed **after DNAT**.

1. Case 5

    **Meaning:**  

    Traffic from a specific remote source IP connecting to a range of ports on our firewall's specific ISP IP connects to a corresponding port range on a local machine.

    Example:
    - Firewall has 2 ISPs, Airtel and BSNL.
    - Someone from a specific public IP connecting to Airtel's public IP, ports 8000-8100
    - Their connection goes to local IP 10.1.1.81:8000-8100
    - Only this specific source IP can access this port range.

    **Rules:**  

    ```bash
    nft add element inet filter allowed_ip4 { <client_ip> }
    nft add rule inet mangle prerouting ip saddr <client_ip> <protocol> sport <starting_client_port>-<ending_client_port> meta mark set 0x00<isp_mark><tc_class_marks>
    nft add rule inet mangle forward ip daddr <client_ip> <protocol> dport <starting_client_port>-<ending_client_port> meta mark set 0x00<isp_mark><tc_class_marks>
    nft insert rule inet nat NAT_PRE ip saddr <public_remote_ip> ip daddr <public_facing_isp_ip> <protocol> dport <starting_public_facing_isp_port>-<ending_public_facing_isp_port> dnat to <client_ip>:<starting_client_port>-<ending_client_port>
    nft insert rule inet filter FILTER_FORWARD ip saddr <public_remote_ip> ip daddr <client_ip> <action>
    ```


    **Explanation:**  

    1. Adds the client to the global whitelist so the firewall allows general outgoing traffic.
    1. Tags traffic originating from the internal client and source ports. Used for ISP/QoS classification of **outgoing** traffic.
    1. Tags traffic destined **to** the internal client. Allows control of incoming bandwidth so downloads don't saturate the network.
    1. Since the `forward` chain policy is `drop`, forwarded packets must be explicitly allowed **after DNAT**.
    > Note: Ensure traffic hitting the public WAN IP on a specific port range (eg 1000-2000) is redirected to the same  internal ports (1000-2000) and mapped one to one.

    > Different ranges are NOT ALLOWED. eg: internal 1000-2000 CANNOT BE MAPPED TO external 2000-3000 

1. Case 6

    **Meaning:**  

    Traffic from a specific remote source IP connecting to any port on our firewall's specific ISP IP connects to the same internal machine for all ports.

    Example:
    - Firewall has 2 ISPs, Airtel and BSNL.
    - Someone from a specific public IP connecting to any port on Airtel's ISP IP
    - Their connection goes to local IP 10.1.1.81 on the same port
    - Only this specific source IP can access this service.

    **Rules:**  

    ```bash
    nft add element inet filter allowed_ip4 { <client_ip> }
    nft add element inet mangle user4_marks { <client_ip> : 0x00<isp_mark><tc_class_marks> }
    nft insert rule inet nat NAT_PRE ip saddr <public_remote_ip>  ip daddr <public_facing_isp_ip> dnat to <client_ip>
    nft insert rule inet filter FILTER_FORWARD ip saddr <public_remote_ip> ip daddr <client_ip> <action>
    ```
    ***
    OR (for a sepcific protocol)
    -

    Full DNAT to a specific internal client for all incoming traffic on a public IP from a specific remote source IP using a specific protocol, allowing only the designated source IP to access all ports on the internal service.

    **Rules:**  

    ```bash
    nft add element inet filter allowed_ip4 { <client_ip> }
    nft add element inet mangle user4_marks { <client_ip> : 0x00<isp_mark><tc_class_marks> }
    nft insert rule inet nat NAT_PRE ip saddr <public_remote_ip> ip protocol <protocol> ip daddr <public_facing_isp_ip> dnat to <client_ip>
    nft insert rule inet filter FILTER_FORWARD ip saddr <public_remote_ip> ip daddr <client_ip> <action>
    ```


    **Explanation:**  
    1. Allows the internal client to send traffic **out** to the internet. Without this, the host can receive packets but cannot reply.
    1. Labels all traffic from the client for bandwidth management. Ensures forwarded DMZ traffic still respects TC class limits.
    1. All packets hitting the public ISP IP from a specific source are destination-NATed to the internal client before routing decisions occur.
    1. Explicitly allows traffic through the `forward` chain. Required when the default policy is `drop`.

