>TODO: Put this in your format and validate all the rules are appropriate
## Overview
This document outlines the NFTables boilerplate configuration for all  VPN access scenarios. All scenarios assume the existence of inet filter and `inet nat` tables and include Captive Portal redirection for unauthenticated users.


## Case 1: Full Access (Captive Portal: YES)

Users in this policy have unrestricted access to the network once authenticated.

### 1.1 Infrastructure & Logic (Setup)

Run this once to define the sets, chains, and enforcement rules.

```nft
# Define Sets
nft add set inet filter vpn_<subnet_set_name> '{ type ipv4_addr; flags interval; }'
nft add set inet filter vpn_<user_ip_set_name> '{ type ipv4_addr; flags interval; }'
nft add set inet nat vpn_<subnet_set_name> '{ type ipv4_addr; flags interval; }'
nft add set inet nat vpn_<user_ip_set_name> '{ type ipv4_addr; flags interval; }'

# Define Policy Chain
nft add chain inet filter VPN_<VPN_POLICY_NAME>
nft add rule inet filter VPN_<VPN_POLICY_NAME> accept
nft add rule inet filter VPN_<VPN_POLICY_NAME> return

# Apply Filter Rules (Security & Policy Jump)
nft add rule inet filter forward ip saddr @vpn_<subnet_set_name> drop
nft insert rule inet filter forward ip saddr @vpn_<user_ip_set_name> jump VPN_<VPN_POLICY_NAME>

# Apply NAT Rules (Captive Portal Redirection)
nft insert rule inet nat prerouting ip saddr @vpn_<subnet_set_name> ip saddr != @vpn_<user_ip_set_name> tcp dport 80 redirect to :80
```

### 1.2 User Management (Runtime)

Run these commands to authorize subnets and specific users.

```nft
# Add Subnet to Watchlist (Captive Portal Scope)
nft add element inet filter vpn_<subnet_set_name> { <vpn_ipv4_subnets> }
nft add element inet nat vpn_<subnet_set_name>  { <vpn_ipv4_subnets> }

# Authorize Specific User (Grant Full Access)
nft add element inet filter vpn_<user_ip_set_name> { <vpn_user_ip> }
nft add element inet nat vpn_<user_ip_set_name> { <vpn_user_ip> }
```

---

## Case 2: Restricted Access — Specific IP & Port (Captive Portal: YES)

Users in this policy can only access specific destination IPs on specific ports.

### 2.1 Infrastructure & Logic (Setup)

Run this once to define the sets (including the Service Map) and chains.

```nft
# Define Sets
nft add set inet filter vpn_<subnet_set_name>  '{ type ipv4_addr; flags interval; }'
nft add set inet filter vpn_<user_ip_set_name>  '{ type ipv4_addr; flags interval; }'
nft add set inet filter vpn_<service_map_name> '{ type ipv4_addr . inet_service; flags interval; }'
nft add set inet nat vpn_<subnet_set_name>  '{ type ipv4_addr; flags interval; }'
nft add set inet nat vpn_<user_ip_set_name>  '{ type ipv4_addr; flags interval; }'

# Define Policy Chain with Bi-directional traffic flow
nft add chain inet filter VPN_<VPN_POLICY_NAME>
nft add rule inet filter VPN_<VPN_POLICY_NAME> ip saddr @vpn_<user_ip_set_name> ip daddr . <protocol> dport @vpn_<service_map_name> accept
nft add rule inet filter VPN_<VPN_POLICY_NAME> ip daddr @vpn_<user_ip_set_name> ip saddr . <protocol> sport @vpn_<service_map_name> accept
nft add rule inet filter VPN_<VPN_POLICY_NAME> return

# Apply Filter Rules (Security & Policy Jump)
nft add rule inet filter forward ip saddr @vpn_<subnet_set_name> drop
nft insert rule inet filter forward ip saddr @vpn_<user_ip_set_name> jump VPN_<VPN_POLICY_NAME>

# Apply NAT Rules (Captive Portal Redirection)
nft insert rule inet nat prerouting ip saddr @vpn_<subnet_set_name> ip saddr != @vpn_<user_ip_set_name> tcp dport 80 redirect to :80
```

### 2.2 User & Service Management (Runtime)

Run these commands to define allowed services and authorize users.

```nft
# Add Subnet to Watchlist
nft add element inet filter vpn_<subnet_set_name> { <user_ip_subnet> }
nft add element inet nat vpn_<subnet_set_name>  { <user_ip_subnet> }

# Define Allowed Services (Destination IP . Port)
nft add element inet filter vpn_<service_map_name> { <destination_ip> . <selected_port> }

# Authorize Specific User
nft add element inet filter vpn_<user_ip_set_name> { <vpn_user_ip> }
nft add element inet nat vpn_<user_ip_set_name> { <vpn_user_ip> }
```

---

## Case 3: Semi-Restricted — IP Only, No Port (Captive Portal: YES)

Users in this policy can access specific destination IPs, but all ports are allowed.

### 3.1 Infrastructure & Logic (Setup)

Run this once.

```nft
# Define Sets
nft add set inet filter vpn_<subnet_set_name> '{ type ipv4_addr; flags interval; }'
nft add set inet filter vpn_<user_ip_set_name> '{ type ipv4_addr; flags interval; }'
nft add set inet filter vpn_<allowed_ip_set_name> '{ type ipv4_addr; flags interval; }'
nft add set inet nat vpn_<subnet_set_name> '{ type ipv4_addr; flags interval; }'
nft add set inet nat vpn_<user_ip_set_name> '{ type ipv4_addr; flags interval; }'

# Define Policy Chain
nft add chain inet filter VPN_<VPN_POLICY_NAME>
nft add rule inet filter VPN_<VPN_POLICY_NAME> ip saddr @vpn_<user_ip_set_name> ip daddr @vpn_<allowed_ip_set_name> accept
nft add rule inet filter VPN_<VPN_POLICY_NAME> ip daddr @vpn_<user_ip_set_name> ip saddr @vpn_<allowed_ip_set_name> accept
nft add rule inet filter VPN_<VPN_POLICY_NAME> return

# Apply Filter Rules
nft add rule inet filter forward ip saddr @vpn_<subnet_set_name> drop
nft insert rule inet filter forward ip saddr @vpn_<user_ip_set_name> jump VPN_<VPN_POLICY_NAME>

# Apply NAT Rules (Captive Portal Redirection)
nft insert rule inet nat prerouting ip saddr @vpn_<subnet_set_name> ip saddr != @vpn_<user_ip_set_name> tcp dport 80 redirect to :80
```

### 3.2 User & Destination Management (Runtime)

Run these commands to authorize subnets, whitelist destinations, and add users.

```nft
# Add Subnet to Watchlist
nft add element inet filter vpn_<subnet_set_name> { <vpn_ipv4_subnets> }
nft add element inet nat vpn_<subnet_set_name> { <vpn_ipv4_subnets> }

# Whitelist a Destination IP (Allow access to this server)
nft add element inet filter vpn_<allowed_ip_set_name> { <destination_ip> }

# Authorize Specific User
nft add element inet filter vpn_<user_ip_set_name> { <vpn_user_ip> }
nft add element inet nat vpn_<user_ip_set_name> { <vpn_user_ip> }
```
# Case 4: Full Access (Captive Portal: NO)

## 4.1 Infrastructure & Logic (Setup)
Run once to define sets, chains, and policy behavior.

```nft
nft add set inet filter vpn_<user_ip_set_name> '{ type ipv4_addr; flags interval; }'

nft add chain inet filter VPN_<VPN_POLICY_NAME>
nft add rule inet filter VPN_<VPN_POLICY_NAME> ip saddr @vpn_<user_ip_set_name> accept
nft add rule inet filter VPN_<VPN_POLICY_NAME> return

nft insert rule inet filter forward ip saddr @vpn_<user_ip_set_name> jump VPN_<VPN_POLICY_NAME>
````

## 4.2 User Management (Runtime)

```nft
nft add element inet filter vpn_<user_ip_set_name> { <vpn_user_ip> }
```

---

# Case 5: Restricted Access — Specific IP & Port (Captive Portal: NO)

## 5.1 Infrastructure & Logic (Setup)

Run once to define sets and policy chain.

```nft
nft add set inet filter vpn_<user_ip_set_name> '{ type ipv4_addr; flags interval; }'
nft add set inet filter vpn_<service_map_name> '{ type ipv4_addr . inet_service; flags interval; }'

nft add chain inet filter VPN_<VPN_POLICY_NAME>
nft add rule inet filter VPN_<VPN_POLICY_NAME> ip saddr @vpn_<user_ip_set_name> ip daddr . tcp dport @vpn_<service_map_name> accept
nft add rule inet filter VPN_<VPN_POLICY_NAME> ip daddr @vpn_<user_ip_set_name> ip saddr . tcp sport @vpn_<service_map_name> accept
nft add rule inet filter VPN_<VPN_POLICY_NAME> return

nft insert rule inet filter forward ip saddr @vpn_<user_ip_set_name> jump VPN_<VPN_POLICY_NAME>
```

## 5.2 User & Service Management (Runtime)

```nft
nft add element inet filter vpn_<user_ip_set_name> { <vpn_user_ip> }
nft add element inet filter vpn_<service_map_name> { <destination_ip> . <selected_port> }
```

---

# Case 6: Semi-Restricted — IP Only (Captive Portal: YES)

## 6.1 Infrastructure & Logic (Setup)

Run once.

```nft
nft add set inet filter vpn_<user_ip_set_name> '{ type ipv4_addr; flags interval; }'
nft add set inet filter vpn_<allowed_ip_set_name> '{ type ipv4_addr; flags interval; }'
nft add set inet nat vpn_<user_ip_set_name> '{ type ipv4_addr; flags interval; }'

nft add chain inet filter VPN_<VPN_POLICY_NAME>
nft add rule inet filter VPN_<VPN_POLICY_NAME> ip saddr @vpn_<user_ip_set_name> ip daddr @vpn_<allowed_ip_set_name> accept
nft add rule inet filter VPN_<VPN_POLICY_NAME> ip daddr @vpn_<user_ip_set_name> ip saddr @vpn_<allowed_ip_set_name> accept
nft add rule inet filter VPN_<VPN_POLICY_NAME> return

nft insert rule inet filter forward ip saddr @vpn_<user_ip_set_name> jump VPN_<VPN_POLICY_NAME>

nft insert rule inet nat prerouting ip saddr @vpn_<user_ip_set_name> tcp dport 80 redirect to :80
```

## 6.2 User & Destination Management (Runtime)

```nft
nft add element inet filter vpn_<user_ip_set_name> { <vpn_user_ip> }
nft add element inet filter vpn_<allowed_ip_set_name> { <destination_ip> }
nft add element inet nat vpn_<user_ip_set_name> { <vpn_user_ip> }
```
