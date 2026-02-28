# SNAT 

## Truth Table

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
nft add map inet nat client_to_wan '{ type ipv4_addr . inet_proto : ipv4_addr; }'
```

**Example element**

```bash
nft add element inet nat client_to_wan '{ <client_ip/client_subnet> . <protocol> : <isp_ip_from_isp_pool> }'
```

**Rule**

```bash
nft insert rule inet nat NAT_POST meta l4proto '{ tcp, udp }' snat to ip saddr . meta l4proto map @client_to_wan
```

# Case 2 — Exact 4-tuple SNAT (src IP + src port + dst IP + dst port)

**Map**

```bash
nft add map inet nat client_dst_ports '{ type ipv4_addr . inet_service . ipv4_addr . inet_service . inet_proto : ipv4_addr; }'
```

**Example element**

```bash
nft add element inet nat client_dst_ports '{ <client_ip/client_subnet> . <source_port> . <destination_ip_or_subnet>  . <destination_port> . <protocol> : <isp_ip_from_isp_pool> }'
```

**Rules**

```bash
nft insert rule inet nat NAT_POST meta l4proto '{ tcp, udp }' snat to ip saddr . th sport . ip daddr . th dport . meta l4proto map @client_dst_ports
```

# Case 3 — Destination-aware SNAT (client + destination)

**Map**

```bash
nft add map inet nat destination_to_wan '{ type ipv4_addr . ipv4_addr . inet_proto : ipv4_addr; }'
```

**Example elements**

```bash
nft add element inet nat destination_to_wan '{ <client_ip/client_subnet> . <destination_ip_or_subnet> . <protocol> : <isp_ip_from_isp_pool> }'
```

**Rule**

```bash
nft insert rule inet nat NAT_POST meta l4proto '{ tcp, udp }' snat ip saddr . ip daddr . meta l4proto map @destination_to_wan
```

# Case 4 — Client + destination IP + destination port (src-port = any)

**Map**

```bash
nft add map inet nat client_dstport '{ type ipv4_addr . ipv4_addr . inet_service . inet_proto : ipv4_addr; }'
```

**Example**

```bash
nft add element inet nat client_dstport '{ <client_ip/client_subnet> . <destination_ip_or_subnet>  . <destination_port> . <protcol> : <isp_ip_from_isp_pool> }'
```

**Rules**

```bash
nft insert rule inet nat NAT_POST meta l4proto '{ tcp, udp }' snat to ip saddr . ip daddr . th dport . meta l4proto map @client_dstport
```

# Case 5 — Client + source port + destination port (dst IP = any)

**Map**

```bash
nft add map inet nat client_sport_dport '{ type ipv4_addr . inet_service . inet_service . inet_proto : ipv4_addr; }'
```

**Example**

```bash
nft add element inet nat client_sport_dport '{ <client_ip/client_subnet> . <source_port> . <destination_port> . <protocol> : <isp_ip_from_isp_pool> }'
```

**Rules**

```bash
nft insert rule inet nat NAT_POST meta l4proto '{ tcp, udp }' snat to ip saddr . th sport . th dport . meta l4proto map @client_sport_dport
```

# Case 6 — Client + source port (dst IP & dst port = any)

**Map**

```bash
nft add map inet nat client_sport '{ type ipv4_addr . inet_service . inet_proto : ipv4_addr; }'
```

**Example**

```bash
nft add element inet nat client_sport '{ <client_ip/client_subnet> . <source_port> . <protocol> : <isp_ip_from_isp_pool> }'
```

**Rules**

```bash
nft insert rule inet nat NAT_POST meta l4proto '{ tcp, udp }' snat to ip saddr . th sport . meta l4proto map @client_sport
```

# Case 7 — Client + destination port (src-port = any, dst-ip = any)

**Map**

```bash
nft add map inet nat client_dport '{ type ipv4_addr . inet_service . inet_proto : ipv4_addr; }'
```

**Example**

```bash
nft add element inet nat client_dport '{ <client_ip/client_subnet> . <destination_port> . <protocol> : <isp_ip_from_isp_pool> }'
```

**Rules**

```bash
nft insert rule inet nat NAT_POST meta l4proto '{ tcp, udp }' snat to ip saddr . th dport . meta l4proto map @client_dport
```

# Case 8 — Client + source port + destination IP (dst port = any)

**Map**

```bash
nft add map inet nat client_sport_dst '{ type ipv4_addr . inet_service . ipv4_addr . inet_proto : ipv4_addr; }'
```

**Example**

```bash
nft add element inet nat client_sport_dst '{ <client_ip/client_subnet> . <source_port> . <destination_ip_or_subnet> . <protocol> : <isp_ip_from_isp_pool> }'
```

**Rules**

```bash
nft insert rule inet nat NAT_POST meta l4proto '{ tcp, udp }' snat to ip saddr . th sport . ip daddr . meta l4proto map @client_sport_dst
```
