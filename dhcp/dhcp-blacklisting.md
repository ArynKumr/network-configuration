# DHCP Blacklisting — MAC-Based Client Denial

This guide describes the method to permanently blacklist a client by MAC address on a Linux host acting as both a **firewall/router** (nftables) and a **DHCP server** (ISC Kea DHCPv4), where both services are co-located on the same machine.

**LAN Interface:** `enp1s0` — directly connected clients  
**WAN Interface:** `enp7s0` — upstream internet connection  

---

1. ## Overview

   Blacklisting a client by MAC address requires enforcement at two independent layers. Neither layer alone is sufficient.

   | Layer | Tool | What It Blocks |
   |-------|------|----------------|
   | Firewall | nftables `netdev` ingress | All routed and host-bound traffic |
   | DHCP Server | Kea `DROP` client class | Lease issuance |

   These two layers cover different gaps:

   - **nftables** cannot reliably block DHCP. Kea reads packets via raw sockets at the driver level, before the kernel network stack and therefore before nftables processes anything.
   - **Kea** has no awareness of general network traffic. A client with a static IP can still route through the firewall if nftables does not block them.

   Both must be configured together for a complete block.

---

2. ## Layer 1 — nftables

   ### Why `inet filter` Does Not Work

   The `inet filter` family processes packets after the kernel has already consumed the Ethernet header. On a non-bridged physical interface like `enp1s0`, `ether saddr` matching in `inet` is unreliable — the L2 context is gone by the time the hook fires. The rule loads without error and counters may increment intermittently, but blocked MACs fall through.

   ⚠️ **Do not use `inet filter` for MAC-based blocking on a non-bridged physical interface.**

   This applies to both the `input` chain (traffic destined for the firewall host) and the `forward` chain (traffic being routed to the internet). Both chains have the same limitation.

   ### Correct Approach — `netdev` Ingress

   The `netdev` family attaches directly to the interface at ingress, before any L3 processing. MAC address context is fully available. A drop here covers all traffic paths — both destined for the firewall host and traffic being forwarded through it.

   Create `/etc/nftables/macblock.nft`:

   ```nft
   table netdev macblock {
       set perma_blocked_mac_users {
           type ether_addr
           elements = { }
       }

       chain ingress_lan {
           type filter hook ingress device "enp1s0" priority filter; policy accept;
           ether saddr @perma_blocked_mac_users counter drop
           udp dport 67 limit rate 10/second burst 20 packets accept
           udp dport 67 counter drop
       }
   }
   ```

   Load the ruleset:

   ```bash
   nft -f /etc/nftables/macblock.nft
   ```

   Include it in your main nftables config for persistence:

   ```nft
   include "/etc/nftables/macblock.nft"
   ```

   ### Managing the Blocklist

   All changes are live immediately. No reload required.

   ```bash
   # Block a single client
   nft add element netdev macblock perma_blocked_mac_users { 52:54:00:6c:eb:43 }

   # Block multiple clients
   nft add element netdev macblock perma_blocked_mac_users { 52:54:00:6c:eb:43, 52:54:00:37:3a:6e }

   # Unblock a client
   nft delete element netdev macblock perma_blocked_mac_users { 52:54:00:6c:eb:43 }

   # List currently blocked MACs
   nft list set netdev macblock perma_blocked_mac_users
   ```

   ### Verifying the Rule

   ```bash
   watch -n 1 nft list chain netdev macblock ingress_lan
   ```

   The counter on `ether saddr @perma_blocked_mac_users counter drop` should increment when a blocked client sends traffic. If it does not, verify the device name in the chain matches the actual interface name on this host.

   > **Note:** The counter incrementing for DHCP traffic from a blocked client does not confirm DHCP was blocked. Kea may have already received a copy of the packet before nftables acted. See Layer 2.

---

3. ## Layer 2 — Kea DHCPv4

   ### Why Kea Must Be Configured Separately

   Kea DHCPv4 uses **raw sockets (`AF_PACKET`)** on directly connected interfaces. Raw sockets read frames directly from the NIC driver — before the kernel network stack, and therefore before nftables, processes anything.

   Packet sequence for a `DHCPDISCOVER` from a blocked client:

   ```
   Frame arrives on enp1s0
         │
         ├──► Kea raw socket captures frame at driver level  ← happens first
         │
         └──► Kernel network stack
                     │
                     └──► nftables netdev ingress
                                 │
                                 └──► DROP — kernel discards its copy
   ```

   Kea has the packet before nftables runs. The drop verdict does not affect what Kea already received.

   The socket type cannot be changed to UDP (which would pass through the normal stack and be subject to nftables) because this deployment serves **directly connected clients**. These clients have no IP address during discovery. Kea requires raw sockets to construct and send a valid response to them. Switching to UDP would break DHCP for all directly connected clients.

   **Kea must deny the lease itself. This cannot be delegated to nftables.**

   ### Configuration — DROP Class Reservation

   Kea has a built-in `DROP` client class. Clients assigned to it have their packets silently discarded before any lease processing occurs.

   Requirements:
   - `early-global-reservations-lookup` must be `true`
   - Reservations must be at the **top-level global scope**, not inside `subnet4`
   - Each MAC address requires its own reservation object

   Example `kea-dhcp4.conf`:

   ```json
   {
     "Dhcp4": {
       "interfaces-config": {
         "interfaces": ["enp1s0"]
       },
       "early-global-reservations-lookup": true,
       "reservations": [
         {
           "hw-address": "52:54:00:6c:eb:43",
           "client-classes": ["DROP"]
         },
         {
           "hw-address": "52:54:00:37:3a:6e",
           "client-classes": ["DROP"]
         }
       ],
       "lease-database": {
         "type": "memfile",
         "persist": true,
         "name": "/var/lib/kea/kea-leases4.csv"
       },
       "subnet4": [
         {
           "id": 420,
           "subnet": "10.10.0.0/24",
           "pools": [
             { "pool": "10.10.0.10 - 10.10.0.240" }
           ]
         }
       ],
       "valid-lifetime": 3600,
       "renew-timer": 900,
       "rebind-timer": 1800
     }
   }
   ```

   ### Common Mistakes

   ⚠️ **Reservation inside `subnet4` instead of global scope:**

   ```json
   // WRONG — early-global-reservations-lookup does not apply to subnet-scoped reservations
   "subnet4": [
     {
       "id": 420,
       "subnet": "10.10.0.0/24",
       "reservations": [
         {
           "hw-address": "52:54:00:6c:eb:43",
           "client-classes": ["DROP"]
         }
       ]
     }
   ]
   ```

   The early lookup phase only checks the top-level `reservations` array. A subnet-scoped reservation is never reached in time — the DROP class is never assigned and the client receives a lease.

   ⚠️ **Multiple MACs in a single `hw-address` field:**

   ```json
   // WRONG — invalid syntax
   {
     "hw-address": "52:54:00:6c:eb:43 or 52:54:00:37:3a:6e",
     "client-classes": ["DROP"]
   }
   ```

   Each MAC must be a separate reservation object.

   ⚠️ **Trailing commas in JSON:**

   ```json
   // WRONG — invalid JSON, Kea will warn and may misparse
   "pools": [
     { "pool": "10.10.0.10 - 10.10.0.240" }
   ],
   ```

   ⚠️ **Duplicate MAC across global and subnet scope:**

   If a MAC appears in both the global `reservations` array and inside a `subnet4` block, Kea will fail to start:

   ```
   failed to add new host using the HW address '...' to the IPv4 subnet id '0'
   as this host has already been added
   ```

   Reservations must exist in exactly one place — the global scope.

   ### Validation

   Always validate before reloading:

   ```bash
   # Step 1 — validate JSON syntax
   python3 -m json.tool /etc/kea/kea-dhcp4.conf

   # Step 2 — validate Kea semantics
   kea-dhcp4 -t /etc/kea/kea-dhcp4.conf
   ```

   The output of step 2 must contain no `ERROR` lines. Resolve all warnings — they indicate config that may be misparsed.

   Reload after confirming clean:

   ```bash
   systemctl reload kea-dhcp4

   # or via control socket
   echo '{"command": "config-reload"}' | socat - /run/kea/kea-dhcp4.sock
   ```

   ### Sanity Checks

   ```bash
   # Check whether a lease was issued to a blocked MAC
   grep "52:54:00:6c:eb:43" /var/lib/kea/kea-leases4.csv

   # Watch Kea logs while the blocked client attempts to connect
   journalctl -u kea-dhcp4 -f
   ```

   Expected: Kea logs the packet as dropped due to the `DROP` class. If a `DHCPACK` is logged instead, the global reservation is not being applied — re-check scope and `early-global-reservations-lookup`.

   > **Note on existing leases:** Adding a block does not revoke leases the client already holds. The client can use their current IP until the lease timer expires. To force immediate expiry, remove the lease entry from `/var/lib/kea/kea-leases4.csv` and restart (not reload) Kea.

   ```bash
   systemctl restart kea-dhcp4
   ```

---

4. ## DHCP Discover Flood Mitigation

   Even with the `DROP` class correctly configured, Kea must receive and perform a reservation lookup for every `DHCPDISCOVER` before denying it. A client spoofing random source MACs — MACs not in the reservation list — will bypass both the nftables MAC block and the Kea reservation check, generating continuous lookup overhead.

   The rate limiting rules already included in the `netdev` ingress chain cap total DHCP volume reaching Kea regardless of source MAC:

   ```nft
   udp dport 67 limit rate 10/second burst 20 packets accept
   udp dport 67 counter drop
   ```

   These fire before Kea's raw socket captures the frame, making this the only layer capable of volume-limiting DHCP traffic before it reaches Kea.

   Tune to your environment. Under normal conditions, even a large LAN will not exceed a few DHCP packets per second.

---

5. ## Known Limitations

   | Limitation | Detail |
   |------------|--------|
   | nftables cannot block DHCP | Kea raw socket bypasses the entire netfilter subsystem. Only the Kea `DROP` class reservation prevents lease issuance. |
   | Socket type cannot be changed to UDP | This deployment serves directly connected clients which require raw sockets. Switching to UDP would break DHCP for those clients. |
   | Rate limiting is a volume cap, not per-client | A single spoofing client can consume the full allowed rate. Kea-level handling remains required for targeted blocking. |
   | Two independent blocklists | The nftables set and Kea global reservations are not linked. Both must be updated manually on every block and unblock operation. |
   | Existing leases are not revoked | A newly blocked client retains their current lease until expiry. Forced revocation requires manual intervention. |

---

6. ## Open Items

   > TODO: Blocklist synchronisation — no automated mechanism exists to keep the nftables set and Kea reservations in sync. Candidates are a sync script driven from one source of truth, or a shared database backend for Kea (MySQL/PostgreSQL). No approach selected.

   > TODO: eBPF / XDP DHCP interception — XDP operates at the driver receive path, below `AF_PACKET`. In theory it is the only layer capable of intercepting a `DHCPDISCOVER` before Kea's raw socket receives it. An eBPF program is already partially integrated on this host for session tracking. Whether it can be safely extended to handle DHCP frame filtering has not been tested. Interaction with Kea's internal BPF filter on a multi-address interface must also be evaluated. Requires dedicated discussion with the eBPF maintainer before any implementation.
