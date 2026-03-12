# Matching Truth Table


| Field  | Remote Source IP | Public ISP IP | Public Port | Protocol | DNAT Target IP | DNAT Target Port |
| ------ | ---------------- | ------------- | ----------- | -------- | -------------- | ---------------- |
| Case 1 | Specific         | Specific      | Specific    | tcp/udp  | Specific       | Specific         |
| Case 2 | Specific         | Specific      | ALL         | tcp/udp  | Specific       | ALL              |

> NOTE: TC ClassID for all the traffic related to DMZ should be **0069**

---

# Case 1

## Meaning

Traffic from a **specific remote source IP** connecting to a **specific port on the firewall's ISP IP** is forwarded to a **specific port on an internal machine**.

This case uses **maps for marking** and a **set-based DNAT lookup** keyed by:

```
(public_isp_ip , remote_source_ip)
```

The DNAT rule is static, but the **allowed remote IP is dynamically inserted during login**.

---

## Example

* Firewall has 2 ISPs, Airtel and BSNL.
* A specific remote IP connects to **Airtel public IP port 8000**
* The connection is forwarded to **10.1.1.81:8000**
* Access is only granted **after login adds the remote IP into the DMZ set**

---

## Rules

```bash
nft add element inet filter allowed_ip4 { <destination_ip> }

nft add element inet mangle src_client_mark {<destination_ip> . <protocol> . <destination_port> : 0x00<isp_id><tc_class_id>}
nft add element inet mangle dst_client_mark {<destination_ip> . <protocol> . <destination_port> : 0x00<isp_id><tc_class_id>}

nft add set inet nat <dmz_set_name> '{type ipv4_addr . inet_service . ipv4_addr}'

nft insert rule inet nat NAT_PRE ip daddr . th dport . ip saddr @<dmz_set_name> dnat to <destination_ip>:<destination_port>
```

### On Login

```bash
nft add element inet nat <dmz_set_name> {<public_facing_isp_ip> . <public_facing_isp_port> . <public_remote_ip>}
```

---

## Explanation

1. Adds the internal destination client to the **global whitelist**, allowing the host to send traffic out to the internet.
2. Creates a **source marking map entry** used to classify traffic originating from the internal host and specific service port.
3. Creates a **destination marking map entry** used to classify incoming traffic destined for the internal service.
4. Defines maps that associate `(ip, protocol, port)` tuples with **TC/QoS marks**.
5. The prerouting rule applies **traffic classification for outgoing packets** based on `(source IP, protocol, source port)`.
6. The postrouting rule applies **traffic classification for incoming packets** based on `(destination IP, protocol, destination port)`.
7. Creates a DMZ lookup set that matches a **tuple of `(public ISP IP, remote source IP)`**.
8. The NAT rule checks whether `(public ISP IP , remote IP)` exists in the DMZ set and performs DNAT to the internal host and port.
9. When a user successfully logs in, their remote IP is dynamically added to the DMZ set, enabling access.

---

# Case 2

## Meaning

Traffic from a **specific remote source IP** connecting to **any port on the firewall's ISP IP** is forwarded to the **same internal machine**, preserving the original port.

This case provides **full DNAT access to the internal host**, but only for **remote IPs that are dynamically authorized via login**.

---

## Example

* Firewall has 2 ISPs, Airtel and BSNL.
* A remote user logs in from a specific public IP.
* The system allows that IP to access **any port on Airtel's public IP**
* All traffic is forwarded to **10.1.1.81 on the same port**

---

## Rules

```bash
nft add element inet filter allowed_ip4 { <destination_ip> }

nft add element inet mangle user4_marks { <destination_ip> : 0x00<isp_id><tc_class_id> }

nft add set inet nat <dmz_set_name> '{type ipv4_addr . ipv4_addr}'

nft insert rule inet nat NAT_PRE ip daddr . ip saddr @<dmz_set_name> dnat to <destination_ip>
```

### On Login

```bash
nft add element inet nat <dmz_set_name> {<public_facing_isp_ip> . <public_remote_ip>}
```

---

## Explanation

1. Adds the internal client to the **global allowed IP set**, ensuring it can send outbound traffic.
2. Marks all traffic originating from or destined to this internal client with the appropriate **ISP and TC class identifier** for QoS enforcement.
3. Creates a DMZ authorization set that stores **(public ISP IP, remote source IP)** tuples.
4. The NAT rule checks incoming traffic against this set. If the pair matches, the packet is **DNATed to the internal host while preserving the original port**.
5. When a user logs in successfully, their remote IP is inserted into the DMZ set, dynamically granting access to the internal service.

---

If you want, I can also show you something **important you may have missed in these rules** (there are **2 architectural issues in the nft design you pasted** that will break marking and scale badly).
