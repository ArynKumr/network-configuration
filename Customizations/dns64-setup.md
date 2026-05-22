# Configuring DNS64 with Unbound for NAT64 Networks

## Example Configuration

File:

```text
/etc/unbound/unbound.conf.d/nat64.conf
```

Configuration:

```conf
server:
    interface: ::
    do-ip6: yes
    
    access-control: <RA_subnet> allow

    module-config: "dns64 validator iterator"
    dns64-prefix: 64:ff9b::/96

    do-nat64: yes
    nat64-prefix: 64:ff9b::/96

forward-zone:
    name: "."
    forward-addr: <Upstream-DNS>
```

# Explanation of Each Directive

## server:

Defines global Unbound server settings.

---

## interface: ::

```conf
interface: ::
```

Listens on all IPv6 interfaces.

Equivalent to:

```text
0.0.0.0 and ::
```

for dual-stack systems.

---

## do-ip6: yes

```conf
do-ip6: yes
```

Enables IPv6 support.

Required for DNS64.

---

## access-control

```conf
access-control: ::1 allow
access-control: 2001:db8:1::/64 allow
```

Controls which clients may query Unbound.

Example:

| Network         | Purpose     |
| --------------- | ----------- |
| ::1             | localhost   |
| 2001:db8:1::/64 | LAN clients |

Without access-control rules, clients may get REFUSED responses.

---

# DNS64 Configuration

## module-config

```conf
module-config: "dns64 validator iterator"
```

Enables:

| Module    | Function                 |
| --------- | ------------------------ |
| dns64     | Synthesizes AAAA records |
| validator | DNSSEC validation        |
| iterator  | Recursive DNS resolution |

Order matters.

Wrong ordering can break DNS64.

---

## dns64-prefix

```conf
dns64-prefix: 64:ff9b::/96
```

Defines the NAT64 synthesis prefix.

The last 32 bits contain the IPv4 address.

Example:

```text
64:ff9b::0808:0808
```

represents:

```text
8.8.8.8
```

---

# NAT64 Configuration

## do-nat64

```conf
do-nat64: yes
```

Enables NAT64 support inside Unbound.

This works together with the DNS64 module.

---

## nat64-prefix

```conf
nat64-prefix: 64:ff9b::/96
```

Defines the NAT64 translation prefix.

This MUST match:

* Your DNS64 prefix
* Your Jool or Tayga NAT64 prefix
* Your network routing

Mismatch = broken connectivity.

---

# Upstream DNS Forwarding

## forward-zone

```conf
forward-zone:
    name: "."
    forward-addr: 2606:4700:4700::1111
```

Forwards all DNS queries to Cloudflare DNS.

Alternative resolvers:

| Provider   | IPv6 Address         |
| ---------- | -------------------- |
| Cloudflare | 2606:4700:4700::1111 |
| Google     | 2001:4860:4860::8888 |
| Quad9      | 2620:fe::fe          |
|            |                      |

---

# Verify DNS64 Operation

Query an IPv4-only domain:

```bash
dig AAAA ipv4only.arpa @2001:db8:1::1
```

Expected:

```text
64:ff9b::c000:aa
64:ff9b::c000:ab
```

These represent:

```text
192.0.0.170
192.0.0.171
```

---


## 3. Firewall blocking ICMPv6

IPv6 depends heavily on ICMPv6.

Blocking it breaks:

* Path MTU discovery
* Neighbor discovery
* SLAAC
* NAT64 reliability

---

## 4. Using private IPv4 behind NAT64 incorrectly

NAT64 normally targets globally routable IPv4.

Trying to reach RFC1918 space through DNS64 often fails unless explicitly routed.

Documentation ranges used here:

| Prefix        | Purpose                 |
| ------------- | ----------------------- |
| 2001:db8::/32 | Documentation only      |
| 64:ff9b::/96  | Well-known NAT64 prefix |
