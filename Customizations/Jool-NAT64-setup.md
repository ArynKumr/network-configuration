# Setting Up Jool NAT64

> **Jool** is a Linux NAT64 translator that bridges IPv6-only clients with IPv4-only servers — no dual-stack required.

---

## Prerequisites

Before you begin, make sure you have:

- [ ] `jool` kernel module installed
- [ ] Unbound (or another DNS64-capable resolver) configured

---

## How It Works

Jool sits between your IPv6 network and the IPv4 internet, working alongside a DNS64 resolver to transparently translate traffic:

```
IPv6 Client
    │
    ▼
DNS64 Resolver  ←── synthesizes fake AAAA records
    │
    ▼
Jool NAT64      ←── translates IPv6 ↔ IPv4
    │
    ▼
IPv4 Internet
```

> **Without Jool:** DNS resolution succeeds, but connections fail at the network layer.

---

## Network Topology

```
IPv6 Client
    │  (IPv6)
    ▼
+----------------------------+
│         Router             │
│  ┌──────────────────────┐  │
│  │   Unbound  (DNS64)   │  │
│  ├──────────────────────┤  │
│  │   Jool     (NAT64)   │  │
│  └──────────────────────┘  │
+----------------------------+
    │  (IPv4)
    ▼
IPv4 Internet
```

---

##  Create the Configuration File

Create `/etc/jool/jool.conf` with the following minimal configuration:

```json
{
    "instance": "default",
    "framework": "netfilter",
    "global": {
        "pool6": "64:ff9b::/96"
    }
}
```

### Configuration Reference

| Key | Value | Description |
|---|---|---|
| `instance` | `"default"` | Name of this Jool instance |
| `framework` | `"netfilter"` | Integration mode (see below) |
| `pool6` | `"64:ff9b::/96"` | NAT64 translation prefix |

#### Available Frameworks

| Framework | Use Case |
|---|---|
| `netfilter` | ✅ Stateful NAT64 — recommended for production |
| `iptables` | Legacy integration |
| `SIIT` | Stateless translation |

---

## Load the Kernel Module

```bash
sudo modprobe jool
```

---

## Start & Enable the Service

```bash
# Start Jool now
sudo systemctl restart jool

# Enable Jool to start on boot
sudo systemctl enable jool
```

---

## Verify the Setup

**Check service status:**
```bash
systemctl status jool
```

**Confirm the instance is running:**
```bash
jool instance display
# Expected output:
# Instance "default"
```

**Confirm the NAT64 prefix:**
```bash
jool global display
# Expected output:
# pool6: 64:ff9b::/96
```

---

## ⚠️ Critical: Prefix Consistency

The NAT64 prefix **must be identical** across all three components. Mismatches are a common source of silent failures.

| Component | Prefix | Must Match |
|---|---|---|
| Unbound DNS64 | `64:ff9b::/96` | ✅ |
| Jool `pool6` | `64:ff9b::/96` | ✅ |
| Routing table | `64:ff9b::/96` | ✅ |

**Example — how the prefix works:**

A DNS64 resolver synthesizes an IPv6 address by embedding the target IPv4 address into the NAT64 prefix:

```
IPv4 target:          8.8.8.8
                      └─────┘
Synthesized AAAA:     64:ff9b::0808:0808
```

Jool strips the prefix and routes the packet to the real IPv4 destination.

---

## Useful Commands

```bash
# List all running Jool instances
jool instance display

# Inspect active NAT64 sessions
jool session display

# Show translation statistics
jool stats display

# Show current global configuration
jool global display
```

---

## Reference: IP Prefix Notation
- [ ] `radvd` installed on your Linux router

| Prefix | Purpose |
|---|---|
| `2001:db8::/32` | Documentation / examples only (RFC 3849) |
| `64:ff9b::/96` | Well-known NAT64 prefix (RFC 6052) |
>NOTE: Don't allow serve of `64:ff9b::/96` — use a private prefix instead.
>NOTE: Use a private prefix instead of `64:ff9b::/96` to avoid conflicts with public NAT64 services ,also the reason why it is hardcoded in [nftables](../nftables.conf)
---

## Production Checklist

Before going live, consider the following:

- [ ] Persist firewall rules across reboots
- [ ] Monitor `conntrack` table usage under load
- [ ] Tune MTU handling to avoid fragmentation issues
- [ ] Set up session count monitoring and alerting
- [ ] Validate fragmented packet behavior in your environment

>NOTE: NAT64 translation is stateful and CPU-bound

---

## Troubleshooting

**Connections fail even though DNS resolves?**
→ Verify Jool is running: `systemctl status jool`

**Wrong addresses being translated?**
→ Check that `pool6` in `jool.conf` matches the prefix configured in Unbound DNS64.

**Module not found?**
→ Ensure `jool-dkms` (or equivalent) is installed for your kernel version.

---

## Further Reading

- [Jool documentation](https://nicmx.github.io/Jool/)
- [RFC 6146 — Stateful NAT64](https://www.rfc-editor.org/rfc/rfc6146)
- [RFC 6052 — IPv6 Addressing of IPv4/IPv6 Translators](https://www.rfc-editor.org/rfc/rfc6052)
