# L2/L3 IPv6 Delegation Matrix — radvd, ndppd, isc-kea-dhcp6

## Implementation-level reference for configurable interfaces

---

## 1. Layer Model

These three daemons sit at different points in the IPv6 address-assignment
and neighbor-resolution pipeline. None of them is a full replacement for
another — they cover disjoint responsibilities that must be configured
consistently on shared interfaces.

```
                      L3 — Address / Prefix Authority
        +----------------------+      +----------------------+
        |        radvd         |      |    isc-kea-dhcp6      |
        |  RA / SLAAC hints    |      |  Stateful IA_NA/IA_PD |
        |  "here is a prefix,  |      |  "here is YOUR exact  |
        |   figure it out"     |      |   address, from me"   |
        +-----------+----------+      +-----------+-----------+
                    |                             |
                    +--------------+--------------+
                                   |
                          Same L2 broadcast domain
                                   |
                    +--------------+--------------+
                    |                             |
        +-----------+----------+                  |
        |         ndppd        |                  |
        |  L2 — Neighbor proxy |                  |
        |  "I'll answer NS on  |                  |
        |   behalf of hosts    |                  |
        |   behind me"         |                  |
        +----------------------+                  |
                    |                             |
                WAN-facing                   LAN-facing
              (upstream link)            (client segment)
```

**radvd** and **kea-dhcp6** both operate at L3 and both answer the
question "what address should this client use" — but by different
mechanisms (advertisement vs. lease). **ndppd** operates at L2 and
answers a completely different question — "who owns this address on the
wire" — for a segment where the *actual* router is not directly attached.

---

## 2. Responsibility Matrix

| Aspect | radvd | ndppd | isc-kea-dhcp6 |
|---|---|---|---|
| OSI layer | L3 (ICMPv6 ND/RA) | L2 (ICMPv6 NS/NA proxy) | L3 (DHCPv6, UDP/547) |
| Protocol | RFC 4861/4862 | RFC 4861 (NS/NA proxying, no RFC of its own) | RFC 8415 |
| Primary interface role | LAN / client-facing | WAN-facing (proxy side) **and** LAN-facing (rule `iface`) | LAN / client-facing |
| What it hands the client | On-link prefix + flags (M/O bits), optional RDNSS | Nothing directly — invisible to clients; makes their addresses reachable from upstream | Exact address (IA_NA), delegated prefix (IA_PD), DNS, and other options |
| State kept | None (stateless broadcast of config) | Learned neighbor cache (LAN side) + proxied entries (WAN side) | Full lease table (MariaDB/memfile) — address, DUID, expiry, state |
| Authoritative for address uniqueness? | No — client self-selects via SLAAC | No — has no opinion on addressing, purely forwards discovery | Yes — hands out exact addresses, tracks conflicts |
| Config keys per interface | `interface <name> { AdvSendAdvert; prefix; RDNSS; }` | `proxy <wan_if> { rule <prefix> { iface <lan_if> } }` | `interfaces-config.interfaces[]`, `subnet6[].interface` |
| Fails silently if... | `forwarding=0` on interface (RAs simply don't route) | Wrong prefix in `rule` (NDP proxied for the wrong /64) | Socket bind race at startup (see below) — reports `active` regardless |
| Depends on the other two? | No (independent of ndppd/kea) | Needs to know the LAN prefix that kea/radvd are managing — configured manually, no auto-discovery | No (independent of radvd/ndppd), but M/O flags in radvd tell clients *whether* to bother calling it |

---

## 3. The M/O Bit Contract Between radvd and kea-dhcp6

This is the actual coupling point between the two L3 daemons — there is
no protocol-level handshake between them, only a **convention** enforced
by matching config:

| radvd setting | Client behaviour | Required kea-dhcp6 config |
|---|---|---|
| `AdvManagedFlag off; AdvOtherConfigFlag off;` | SLAAC only — client self-assigns from the advertised prefix, ignores DHCPv6 entirely | kea-dhcp6 config is irrelevant; clients never contact it |
| `AdvManagedFlag off; AdvOtherConfigFlag on;` | SLAAC for address, DHCPv6 **stateless** for options only (DNS, domain search) | `subnet6` may omit `pools` entirely — kea only serves `option-data` |
| `AdvManagedFlag on; AdvOtherConfigFlag on;` (lab default) | Client ignores the advertised prefix for addressing, sends DHCPv6 SOLICIT for a stateful IA_NA lease | `subnet6[].pools` **must** exist with a real range; without it, ADVERTISE carries NoAddrsAvail |
| `AdvManagedFlag on;` but interface has **no** matching kea `subnet6` for that prefix | Client sends SOLICIT into the void — no server responds, client retries with exponential backoff, never gets an address | Misconfiguration — every subnet advertised with M=1 needs a corresponding `subnet6.subnet` in kea |

**Implementation rule:** for every `interface` block in `radvd.conf` with
`AdvManagedFlag on`, there must be exactly one `subnet6` entry in
`kea-dhcp6.conf` whose `subnet` matches the advertised prefix and whose
`interface` field matches the *same* interface name kea sees for that
segment (which may differ from radvd's interface name if the two daemons
run in different netns/containers, as in the lab — radvd and kea both
use `host0` internally, but that's a coincidence of both being nspawn
containers with a single veth; it is not guaranteed in general).

---

## 4. The ndppd Coupling Point — Manual, Not Automatic

ndppd has **no visibility** into what radvd or kea-dhcp6 are doing. Its
`rule` prefix is a static text field that must be kept in sync by hand
(or by tooling) with whatever prefix radvd advertises and kea assigns
from:

```
radvd.conf     : prefix fd00:cafe:1::/64 { ... }
kea-dhcp6.conf : subnet6[].subnet = "fd00:cafe:1::/64"
                 subnet6[].pools[].pool = "fd00:cafe:1::100 - fd00:cafe:1::1ff"
ndppd.conf     : rule fd00:cafe:1::/64 { iface host0 }
                 ^^^^^^^^^^^^^^^^^^^^^ must match the /64 above exactly
```

If any one of these three prefix values drifts from the other two:

- **ndppd prefix too broad** (e.g. `/48` instead of `/64`): it proxies NS
  for addresses that don't exist on the LAN, potentially answering NS
  for the WAN's own segment — ND loops/black-holing.
- **ndppd prefix too narrow**: only some client addresses become
  reachable from upstream; symptomatically looks like intermittent
  connectivity per-client.
- **kea pool outside radvd's advertised prefix**: DHCPv6 hands out
  addresses the LAN's on-link prefix doesn't cover — clients ARP/NDP for
  their own gateway using the wrong on-link determination logic.

**Implementation rule:** treat the LAN `/64` as a single source-of-truth
value substituted into all three config files from one place (a
variable, template, or generator script) — never hand-edit each
independently in production.

---

## 5. Per-Container Interface Role Reference (as configured in this lab)

| Container | Interface | Role | Owning daemon(s) | Address type on this interface |
|---|---|---|---|---|
| `radvd` | `host0` | LAN, RA source | radvd | Static (`fd00:cafe:1::1/64`) |
| `kea` | `host0` | LAN, DHCPv6 server | kea-dhcp6 | Static (`fd00:cafe:1::2/64`) |
| `ndppd` | `host0` | LAN-facing proxy target | ndppd (`rule ... { iface host0 }`) | Static (`fd00:cafe:1::3/64`) |
| `ndppd` | `veth-wan-nd` | WAN-facing proxy source | ndppd (`proxy veth-wan-nd { ... }`) | Static (`fd00:cafe:ffff::2/64`) |
| `client1`/`client2` | `host0` | LAN, client | none (consumer of radvd + kea) | Dynamic (SLAAC and/or DHCPv6) |
| host | `veth-wan-host` | Simulated upstream | none (routes to ndppd's WAN side) | Static (`fd00:cafe:ffff::1/64`) |

Note that **kea and radvd both bind `host0` in separate containers** —
this only works because each container has its own network namespace;
if kea and radvd shared a namespace, both daemons attempting to manage
RA/DHCP behaviour on the same physical interface would need careful
socket-option coordination (`SO_REUSEADDR` is not sufficient for RA vs.
DHCPv6 since they're different protocols on different sockets — the real
conflict would be operational, e.g. both trying to be "the" address
authority for the segment).

---

## 6. Configurable-Interface Checklist (apply per new LAN segment)

When adding a new routed IPv6 segment to this stack, every one of the
following must be updated together — this is the practical version of
the coupling described above:

1. **radvd.conf** — new `interface <if> { prefix <segment>/64 { ... }; }`
   block; `AdvManagedFlag`/`AdvOtherConfigFlag` chosen per section 3.
2. **kea-dhcp6.conf** — new `subnet6` entry with matching `subnet` and a
   `pools` range carved from the same `/64`; `interfaces-config.interfaces`
   must list the new interface name.
3. **ndppd.conf** — new `rule <segment>/64 { iface <if> }` block *if and
   only if* this segment's addresses need to be reachable from a WAN/
   upstream link the router doesn't directly attach to. Purely local
   segments with a real routed path do not need an ndppd rule.
4. **Router's own address** — must hold an address inside the new prefix
   on the interface radvd/kea are advertising from (the router's
   own `::1`-style address in the segment), or clients have no usable
   default gateway.
5. **sysctl** — `net.ipv6.conf.<if>.forwarding=1` wherever radvd is
   running; DAD must be allowed to settle before either radvd or kea
   binds to the interface (see startup-ordering note below).
6. **Startup ordering** — bring the interface up, wait for DAD to clear
   the tentative flag, *then* start the daemon that binds to it. This
   applies independently to radvd and kea-dhcp6 — both bind link-local
   addresses at startup and both fail (differently — radvd refuses to
   start; kea starts but silently has no open socket) if raced.
