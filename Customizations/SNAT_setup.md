# SNAT 

Truth Table

| Field | Source IP | Source Port | Destination IP | Destination Port | Protocol | ISP IP
| --- | --- | --- | --- | --- | --- | --- |
| Case 1 | Specific | ALL | ALL | ALL | tcp/udp | ISP IP
| Case 2 | Specific | Specific | Specific | Specific | tcp/udp | ISP IP
| Case 3 | Specific | ALL | Specific | ALL | tcp/udp | ISP IP
| Case 4 | Specific | ALL | Specific | Specific | tcp/udp | ISP IP
| Case 5 | Specific | Specific | ALL | Specific | tcp/udp | ISP IP
| Case 6 | Specific | Specific | ALL | ALL | tcp/udp | ISP IP
| Case 7 | Specific | ALL | ALL | Specific | tcp/udp | ISP IP
| Case 8 | Specific | Specific | Specific | ALL | tcp/udp | ISP IP

# Case 1 — Complete traffic SNAT (client → single ISP IP)

**Map**

```bash
nft add map inet nat client_to_wan { type ipv4_addr : ipv4_addr; }
```

**Example element**

```bash
nft add element inet nat client_to_wan { <client_ip/client_subnet> : <isp_ip_from_isp_pool> }
```

**Rule**

```bash
nft insert rule inet nat NAT_POST snat to ip saddr map @client_to_wan
```

# OR

**Rules**

```bash
# TCP
nft insert rule inet nat NAT_POST meta l4proto udp snat to ip saddr map @client_to_wan

# UDP
nft insert rule inet nat NAT_POST meta l4proto tcp snat to ip saddr map @client_to_wan
```

# Case 2 — Exact 4-tuple SNAT (src IP + src port + dst IP + dst port)

**Map**

```bash
nft add map inet nat client_dst_ports { type ipv4_addr . inet_service . ipv4_addr . inet_service : ipv4_addr; }
```

**Example element**

```bash
nft add element inet nat client_dst_ports { <client_ip/client_subnet> . <source_port> . <destination_ip_or_subnet>  . <destination_port> : <isp_ip_from_isp_pool> }
```

**Rules**

```bash
# TCP
nft insert rule inet nat NAT_POST meta l4proto tcp snat to ip saddr . tcp sport . ip daddr . tcp dport map @client_dst_ports

# UDP
nft insert rule inet nat NAT_POST meta l4proto udp snat to ip saddr . udp sport . ip daddr . udp dport map @client_dst_ports
```

# Case 3 — Destination-aware SNAT (client + destination)

**Map**

```bash
nft add map inet nat destination_to_wan { type ipv4_addr . ipv4_addr : ipv4_addr; }
```

**Example elements**

```bash
nft add element inet nat destination_to_wan { <client_ip/client_subnet> . <destination_ip_or_subnet>  : <isp_ip_from_isp_pool> }
```

**Rule**

```bash
nft insert rule inet nat NAT_POST snat ip saddr . ip daddr map @destination_to_wan
```

# OR

**Rules**

```bash
# TCP
nft insert rule inet nat NAT_POST meta l4proto tcp snat ip saddr . ip daddr map @destination_to_wan

# UDP
nft insert rule inet nat NAT_POST meta l4proto udp snat ip saddr . ip daddr map @destination_to_wan
```

# Case 4 — Client + destination IP + destination port (src-port = any)

**Map**

```bash
nft add map inet nat client_dstport { type ipv4_addr . ipv4_addr . inet_service : ipv4_addr; }
```

**Example**

```bash
nft add element inet nat client_dstport { <client_ip/client_subnet> . <destination_ip_or_subnet>  . <destination_port> : <isp_ip_from_isp_pool> }
```

**Rules**

```bash
# TCP
nft insert rule inet nat NAT_POST meta l4proto tcp snat to ip saddr . ip daddr . tcp dport map @client_dstport

# UDP
nft insert rule inet nat NAT_POST meta l4proto udp snat to ip saddr . ip daddr . udp dport map @client_dstport
```

# Case 5 — Client + source port + destination port (dst IP = any)

**Map**

```bash
nft add map inet nat client_sport_dport { type ipv4_addr . inet_service . inet_service : ipv4_addr; }
```

**Example**

```bash
nft add element inet nat client_sport_dport { <client_ip/client_subnet> . <source_port> . <destination_port> : <isp_ip_from_isp_pool> }
```

**Rules**

```bash
# TCP
nft insert rule inet nat NAT_POST meta l4proto tcp snat to ip saddr . tcp sport . tcp dport map @client_sport_dport

# UDP
nft insert rule inet nat NAT_POST meta l4proto udp snat to ip saddr . udp sport . udp dport map @client_sport_dport
```

# Case 6 — Client + source port (dst IP & dst port = any)

**Map**

```bash
nft add map inet nat client_sport { type ipv4_addr . inet_service : ipv4_addr; }
```

**Example**

```bash
nft add element inet nat client_sport { <client_ip/client_subnet> . <source_port> : <isp_ip_from_isp_pool> }
```

**Rules**

```bash
# TCP
nft insert rule inet nat NAT_POST meta l4proto tcp snat to ip saddr . tcp sport map @client_sport

# UDP
nft insert rule inet nat NAT_POST meta l4proto udp snat to ip saddr . udp sport map @client_sport
```

# Case 7 — Client + destination port (src-port = any, dst-ip = any)

**Map**

```bash
nft add map inet nat case7_client_dport { type ipv4_addr . inet_service : ipv4_addr; }
```

**Example**

```bash
nft add element inet nat client_dport { <client_ip/client_subnet> . <destination_port> : <isp_ip_from_isp_pool> }
```

**Rules**

```bash
# TCP
nft insert rule inet nat NAT_POST meta l4proto tcp snat to ip saddr . tcp dport map @client_dport

# UDP
nft insert rule inet nat NAT_POST meta l4proto udp snat to ip saddr . udp dport map @client_dport
```

# Case 8 — Client + source port + destination IP (dst port = any)

**Map**

```bash
nft add map inet nat client_sport_dst { type ipv4_addr . inet_service . ipv4_addr : ipv4_addr; }
```

**Example**

```bash
nft add element inet nat client_sport_dst { <client_ip/client_subnet> . <source_port> . <destination_ip_or_subnet>  : <isp_ip_from_isp_pool> }
```

**Rules**

```bash
# TCP
nft insert rule inet nat NAT_POST meta l4proto tcp snat to ip saddr . tcp sport . ip daddr map @client_sport_dst

# UDP
nft insert rule inet nat NAT_POST meta l4proto udp snat to ip saddr . udp sport . ip daddr map @client_sport_dst
```
