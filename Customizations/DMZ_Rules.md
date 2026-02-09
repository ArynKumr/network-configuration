Matching Truth Table
---------------------------

| Field | Remote Source IP | Public ISP IP | Public Port | Protocol | DNAT Target IP | DNAT Target Port | Action |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Case 1 | ALL | Specific | Specific | tcp/udp | Specific | Specific | allow |
| Case 2 | ALL | Specific | Range | tcp/udp | Specific | Range | allow |
| Case 3 | ALL | Specific | ALL | ALL | Specific | ALL | allow |
| Case 4 | Specific | Specific | Specific | tcp/udp | Specific | Specific | allow |
| Case 5 | Specific | Specific | Range | tcp/udp | Specific | Range | allow |
| Case 6 | Specific | Specific | ALL | ALL | Specific | ALL | allow |


* * *

# Case 1

**Meaning:**  

Forwards traffic arriving on a specific public IP and port combination to a specific internal client IP and port, allowing any remote source IP to access an internal service through port forwarding.


**Rules:**  

```
nft add element inet filter allowed_ip4 { <client_ip> }
nft add rule inet mangle prerouting ip saddr <client_ip> <protocol> sport <client_port> meta mark set 0x00<isp_mark><tc_class_marks>
nft add rule inet mangle forward ip daddr <client_ip> <protocol> dport <client_port> meta mark set 0x00<isp_mark><tc_class_marks>
nft insert rule inet nat NAT_PRE ip daddr <public_facing_isp_ip> <protocol> dport <public_facing_isp_port> dnat to <client_ip>:<client_port>
nft insert rule inet filter FILTER_FORWARD ip daddr <client_ip> <action>
```

**Explanation:**  

1. Adds the client to the global whitelist so the firewall allows general outgoing traffic.
2. Tags traffic originating from the internal client and source port.  
Used for ISP/QoS classification of **outgoing** traffic.
3. Tags traffic destined **to** the internal client.  
Allows control of incoming bandwidth so downloads don’t saturate the network.
4. Ensures traffic hitting the public WAN IP on a specific port is redirected to the internal host.
5. Since the `forward` chain policy is `drop`, forwarded packets must be explicitly allowed **after DNAT**.
* * *

# Case 2
**Meaning:**  
Forwards traffic arriving on a specific public IP and a range of ports to a specific internal client IP and corresponding port range, allowing any remote source IP to access internal services through port pool forwarding.

**Rules:**  

```
nft add element inet filter allowed_ip4 { <client_ip> }
nft add rule inet mangle prerouting ip saddr <client_ip> <protocol> sport <starting_client_port>-<ending_client_port>  meta mark set 0x00<isp_mark><tc_class_marks>
nft add rule inet mangle forward ip daddr <client_ip> <protocol> dport <starting_client_port>-<ending_client_port> meta mark set 0x00<isp_mark><tc_class_marks>
nft insert rule inet nat NAT_PRE ip daddr <public_facing_isp_ip> <protocol> dport <starting_public_facing_isp_port>-<ending_public_facing_isp_port> dnat to <client_ip>:<starting_client_port>-<ending_client_port>
nft insert rule inet filter FILTER_FORWARD ip daddr <client_ip> <action>
```

* * *

**Explanation:**  

1. Adds the client to the global whitelist so the firewall allows general outgoing traffic.
2. Tags traffic originating from the internal client and source ports.  
Used for ISP/QoS classification of **outgoing** traffic.
3. Tags traffic destined **to** the internal client.  
Allows control of incoming bandwidth so downloads don’t saturate the network.
4. Ensures traffic hitting the public WAN IP on a specific pool of port is redirected to the internal host.
5. Since the `forward` chain policy is `drop`, forwarded packets must be explicitly allowed **after DNAT**.
* * *

# Case 3
**Meaning:**  
Full DNAT to a specific internal client for all incoming traffic on a public IP, allowing any remote source IP to access all ports on the internal service.

**Rules:**  

```
nft add element inet filter allowed_ip4 { <client_ip> }
nft add element inet mangle user4_marks { <client_ip> : 0x00<isp_mark><tc_class_marks> }
nft insert rule inet nat NAT_PRE ip daddr <public_facing_isp_ip> dnat to <client_ip>
nft insert rule inet filter FILTER_FORWARD ip daddr <client_ip> <action>
```

* * *

**Explanation:**  
1. Allows the internal client to send traffic **out** to the internet. Without this, the host can receive packets but cannot reply.
2. Labels all traffic from the client for bandwidth management. Ensures forwarded DMZ traffic still respects TC class limits.
3. All packets hitting the public ISP IP are destination-NATed to the internal client before routing decisions occur.
4. Explicitly allows traffic through the `forward` chain. Required when the default policy is `drop`.

* * *

# Case 4
**Meaning:**  
Forwards traffic arriving on a specific public IP and port from a specific remote source IP to a specific internal client IP and port, restricting access to the internal service to only the designated source IP.

**Rules:**  

```
nft add element inet filter allowed_ip4 { <client_ip> }
nft add rule inet mangle prerouting ip saddr <client_ip> <protocol> sport <client_port> meta mark set 0x00<isp_mark><tc_class_marks>
nft add rule inet mangle forward ip daddr <client_ip> <protocol> dport <client_port> meta mark set 0x00<isp_mark><tc_class_marks>
nft insert rule inet nat NAT_PRE ip saddr <public_remote_ip> ip daddr <public_facing_isp_ip> <protocol> dport <public_facing_isp_port> dnat to <client_ip>:<client_port>
nft insert rule inet filter FILTER_FORWARD ip saddr <public_remote_ip> ip daddr <client_ip> <action>
```

* * *

**Explanation:**  

1. Adds the client to the global whitelist so the firewall allows general outgoing traffic.
2. Tags traffic originating from the internal client and source port.  
Used for ISP/QoS classification of **outgoing** traffic.
3. Tags traffic destined **to** the internal client.  
Allows control of incoming bandwidth so downloads don't saturate the network.
4. Ensures traffic hitting the public WAN IP on a specific port from a specific source is redirected to the internal host.
5. Since the `forward` chain policy is `drop`, forwarded packets must be explicitly allowed **after DNAT**.
* * *

# Case 5
**Meaning:**  
Forwards traffic arriving on a specific public IP and a range of ports from a specific remote source IP to a specific internal client IP and corresponding port range, restricting access to the internal service to only the designated source IP with port pool forwarding.

**Rules:**  

```
nft add element inet filter allowed_ip4 { <client_ip> }
nft add rule inet mangle prerouting ip saddr <client_ip> <protocol> sport <starting_client_port>-<ending_client_port> meta mark set 0x00<isp_mark><tc_class_marks>
nft add rule inet mangle forward ip daddr <client_ip> <protocol> dport <starting_client_port>-<ending_client_port> meta mark set 0x00<isp_mark><tc_class_marks>
nft insert rule inet nat NAT_PRE ip saddr <public_remote_ip> ip daddr <public_facing_isp_ip> <protocol> dport <starting_public_facing_isp_port>-<ending_public_facing_isp_port> dnat to <client_ip>:<starting_client_port>-<ending_client_port>
nft insert rule inet filter FILTER_FORWARD ip saddr <public_remote_ip> ip daddr <client_ip> <action>
```

* * *

**Explanation:**  

1. Adds the client to the global whitelist so the firewall allows general outgoing traffic.
2. Tags traffic originating from the internal client and source ports.  
Used for ISP/QoS classification of **outgoing** traffic.
3. Tags traffic destined **to** the internal client.  
Allows control of incoming bandwidth so downloads don't saturate the network.
4. Ensures traffic hitting the public WAN IP on a specific pool of ports (e.g., 64000 to 65000) is redirected to the internal hosts (5000 to 6000) and mapped one to one. Also requires that the range of ports be the same.
5. Since the `forward` chain policy is `drop`, forwarded packets must be explicitly allowed **after DNAT**.
* * *

# Case 6
**Meaning:**  
Full DNAT to a specific internal client for all incoming traffic on a public IP from a specific remote source IP, allowing only the designated source IP to access all ports on the internal service.

**Rules:**  

```
nft add element inet filter allowed_ip4 { <client_ip> }
nft add element inet mangle user4_marks { <client_ip> : 0x00<isp_mark><tc_class_marks> }
nft insert rule inet nat NAT_PRE ip saddr <public_remote_ip> ip daddr <public_facing_isp_ip> dnat to <client_ip>
nft insert rule inet filter FILTER_FORWARD ip saddr <public_remote_ip> ip daddr <client_ip> <action>
```

* * *

**Explanation:**  
1. Allows the internal client to send traffic **out** to the internet. Without this, the host can receive packets but cannot reply.
2. Labels all traffic from the client for bandwidth management. Ensures forwarded DMZ traffic still respects TC class limits.
3. All packets hitting the public ISP IP from a specific source are destination-NATed to the internal client before routing decisions occur.
4. Explicitly allows traffic through the `forward` chain. Required when the default policy is `drop`.

* * *