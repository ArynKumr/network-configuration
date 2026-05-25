# 🔍 Configuring DNS64 with Unbound for NAT64 Networks

> **Unbound** acts as both a DNS64 resolver and a forwarding resolver. It synthesizes fake AAAA records for IPv4-only domains, enabling IPv6-only clients to reach them via a NAT64 translator like Jool.

---

## Prerequisites

Before you begin, make sure you have:

- [ ] Unbound installed with DNS64 support compiled in
- [ ] A working NAT64 translator (e.g. Jool) using the same prefix
- [ ] Your LAN's IPv6 subnet and upstream DNS resolver addresses on hand


---

## How It Works

```
IPv6 Client
    │
    │  AAAA query for ipv4only.arpa
    ▼
Unbound (DNS64)
    │
    │  No AAAA found upstream → synthesizes one using NAT64 prefix
    ▼
Synthesized AAAA: 64:ff9b::c000:aa  (embeds 192.0.0.170)
    │
    ▼
Jool NAT64  →  IPv4 Internet
```

> **Without DNS64:** IPv6-only clients can't resolve IPv4-only hostnames. Without Jool: DNS resolves, but connections fail at the network layer.

---

## Write the Configuration

Create `/etc/unbound/unbound.conf.d/nat64.conf`:

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
    forward-addr: <upstream-dns>
```

---

## Configuration Reference

### `interface: ::`

Listens on all IPv6 interfaces — equivalent to binding both `0.0.0.0` and `::` on a dual-stack system.

---

### `do-ip6: yes`

Enables IPv6 support. Required for DNS64 to function.

---

### `access-control`

Controls which clients are permitted to query Unbound. Without explicit rules, clients receive `REFUSED` responses.

```conf
access-control: ::1 allow               # localhost
access-control: 2001:db8:1::/64 allow   # LAN clients
```

Add one line per subnet that needs DNS access.

---

### `module-config`

```conf
module-config: "dns64 validator iterator"
```

Loads the DNS processing pipeline in order:

| Module | Function |
|---|---|
| `dns64` | Synthesizes AAAA records for IPv4-only domains |
| `validator` | DNSSEC validation |
| `iterator` | Recursive DNS resolution |

> **Order matters.** Incorrect ordering breaks DNS64 synthesis.

---

### `dns64-prefix` and `nat64-prefix`

```conf
dns64-prefix: 64:ff9b::/96
nat64-prefix: 64:ff9b::/96
```

Both must be set to the same NAT64 translation prefix. The last 32 bits of the synthesized address embed the target IPv4 address:

```
IPv4 target:          8.8.8.8
                      └─────┘
Synthesized AAAA:     64:ff9b::0808:0808
```

---

### `do-nat64: yes`

Activates NAT64 support inside Unbound, working in conjunction with the `dns64` module.

---

### `forward-zone`

Forwards all DNS queries upstream. Prefer IPv6-capable resolvers:

```conf
forward-zone:
    name: "."
    forward-addr: 2606:4700:4700::1111
```

| Provider | IPv6 Address |
|---|---|
| Cloudflare | `2606:4700:4700::1111` |
| Google | `2001:4860:4860::8888` |
| Quad9 | `2620:fe::fe` |

---

## ⚠️ Critical: Prefix Consistency

The NAT64 prefix **must be identical** across every component. A mismatch silently breaks connectivity.

| Component | Prefix | Must Match |
|---|---|---|
| `dns64-prefix` (Unbound) | `64:ff9b::/96` | ✅ |
| `nat64-prefix` (Unbound) | `64:ff9b::/96` | ✅ |
| Jool `pool6` | `64:ff9b::/96` | ✅ |
| Routing table | `64:ff9b::/96` | ✅ |

---

## Restart Unbound

```bash
sudo systemctl restart unbound

# Enable on boot
sudo systemctl enable unbound
```

---

## Verify DNS64 Operation

Query an IPv4-only domain and confirm synthesized AAAA records come back:

```bash
dig AAAA ipv4only.arpa @<your-unbound-ip>
```

Expected response:

```
64:ff9b::c000:aa    →  192.0.0.170
64:ff9b::c000:ab    →  192.0.0.171
```

If you see the NAT64 prefix embedded in the response, DNS64 synthesis is working correctly.

---

## Troubleshooting

**Clients getting `REFUSED`?**
→ Add an `access-control` line for their subnet in `nat64.conf`.

**No AAAA records synthesized?**
→ Confirm `module-config` includes `dns64` and is ordered correctly: `"dns64 validator iterator"`.

**Synthesis works but connections fail?**
→ Verify the prefix in `dns64-prefix` matches `pool6` in Jool exactly.

**ICMPv6 issues / unreliable NAT64?**
→ Check that your firewall is not blocking ICMPv6. IPv6 depends on it for path MTU discovery, neighbor discovery, and SLAAC. Blocking ICMPv6 breaks NAT64 reliability.

**Can't reach RFC1918 addresses through NAT64?**
→ NAT64 targets globally routable IPv4 by default. Reaching private address space (`10.x`, `192.168.x`, etc.) requires explicit routing and is not supported in standard deployments.

---

## Reference: IP Prefix Notation

| Prefix | Purpose |
|---|---|
| `2001:db8::/32` | Documentation / examples only (RFC 3849) |
| `64:ff9b::/96` | Well-known NAT64 prefix (RFC 6052) |

---

## Further Reading

- [Unbound DNS64 documentation](https://unbound.docs.nlnetlabs.nl/)
- [RFC 6147 — DNS64: DNS Extensions for Network Address Translation from IPv6 Clients to IPv4 Servers](https://www.rfc-editor.org/rfc/rfc6147)
- [RFC 6052 — IPv6 Addressing of IPv4/IPv6 Translators](https://www.rfc-editor.org/rfc/rfc6052)
