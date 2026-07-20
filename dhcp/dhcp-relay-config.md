# DHCP Relay Across L3 Boundaries (Production-Ready)

This guide describes the method to deploy an `ISC DHCP Relay Agent` with a `ISC-Kea DHCP Server` when clients and server are separated by Layer-3 boundaries (VLANs, routed ports, bridges). Covers both DHCPv4 (`dhcrelay -4`) and DHCPv6 (`dhcrelay -6`) — the two protocols relay very differently at the packet level even though they share the same daemon and systemd template.


1. Installation

  ```bash
  sudo apt update && sudo apt install isc-dhcp-relay -y
  ```

1. Kea Server Configuration

    - Kea must have a subnet that matches the relay agent’s `gateway address`.

      Example `kea-dhcp4.conf`

      ```json
      {
        "Dhcp4": {
          "interfaces-config": {
            "interfaces": [ "eth0" ]
          },
          "subnet4": [
            {
              "id": 1,
              "subnet": "192.168.10.0/24",
              "pools": [
                { "pool": "192.168.10.50 - 192.168.10.200" }
              ],
              "relay": {
                "ip-address": "192.168.10.1" //This is the gateway address that is expected
              },
              "option-data": [
                { "name": "routers", "data": "192.168.10.1" }
              ]
            }
          ]
        }
      }
      ```

    - `relay.ip-address` must equal the relay agent’s IP on that subnet.


1. Firewall Requirements

    Allow:

    * UDP 67, 68 (DHCPv4)
    * UDP 546, 547 (DHCPv6)


1. Summary Table

    | Aspect           | Flat Network       | Relay-Based Network |
    | ---------------- | ------------------ | ------------------- |
    | L2 boundary      | Same               | Different           |
    | DHCP traffic     | Broadcast          | Unicast via relay   |
    | Subnet selection | Incoming interface | `gateway address`            |
    | Complexity       | Low                | Medium              |

    ### DHCPv4 Relay vs DHCPv6 Relay

    | Aspect | DHCPv4 (`dhcrelay -4`) | DHCPv6 (`dhcrelay -6`) |
    | ---- | ---- | ---- |
    | Client to relay transport | Broadcast (`255.255.255.255`) | Multicast (`ff02::1:2`, link-scoped) |
    | Relay to server transport | Unicast, raw BOOTREQUEST forwarded | Unicast, wrapped in `RELAY-FORW` |
    | Server to relay transport | Unicast BOOTREPLY | Unicast `RELAY-REPL` (wraps original reply) |
    | Subnet-selection field | `giaddr` (gateway address) | `link-address` inside `RELAY-FORW` |
    | Kea config field | `relay.ip-address` (single string) | `relay.ip-addresses` (list) |
    | Nesting | Not supported | Multiple relay hops supported |
    | Firewall ports | UDP 67/68 | UDP 546/547 |


1. Troubleshooting

    Run on the relay host:

    ```bash
    tcpdump -i any port 67 or port 68 -n -vv
    ```

    Expected packet flow:

    1. BOOTREQUEST from `0.0.0.0` on client interface
    2. BOOTREQUEST from `Relay_IP` to `Kea_IP`
    3. BOOTREPLY from `Kea_IP` to `Relay_IP`
    4. BOOTREPLY from `Relay_IP` to client MAC


1. Templated DHCP Relay Units

    This setup allows multiple independent relay instances on one host.

    Service Definition

    `/etc/systemd/system/isc-dhcp-relay@.service`

    ```ini
    [Unit]
    Description=ISC DHCP Relay (%I)
    After=network-online.target
    Wants=network-online.target

    [Service]
    Type=forking
    PIDFile=/run/dhcrelay-%I.pid
    EnvironmentFile=/etc/default/isc-dhcp-relay-%I
    ExecStart=/usr/sbin/dhcrelay -q -pf /run/dhcrelay-%I.pid $OPTIONS $INTF_CMD $SERVERS
    Restart=on-failure

    [Install]
    WantedBy=multi-user.target
    ```

    

    ### Instance Configuration Files

    Each instance uses its own file:

    ```
    /etc/default/isc-dhcp-relay-<instance>
    ```

    Example:

    ```bash
    # Interfaces the relay listens on (client-facing and server-facing)
    INTERFACES=""

    # Kea DHCP server IP
    SERVERS="10.50.50.1"

    # Relay options
    # -4  IPv4 only
    # -D  Debug logging
    # -a  Append relay agent info
    # -iu Upstream interface
    # -id Downstream interfaces
    OPTIONS="-4 -D -id br0 -iu eth0"
    INTF_CMD=""
    ```

    Enable the instance:

    ```bash
    systemctl enable --now isc-dhcp-relay@<instance>
    ```


    ⚠️ Critical Rule: The base file must be empty

      ```
      /etc/default/isc-dhcp-relay
      ```

      * File must exist
      * File must contain nothing

      If it contains variables, systemd silently merges them with instance files and breaks relay behavior.

      Correct state:

      ```bash
      ls -l /etc/default/isc-dhcp-relay
      cat /etc/default/isc-dhcp-relay
      ```

      Zero output is correct.


    Sanity Checks

    ```bash
    systemctl status 'isc-dhcp-relay@*'
    ps -ef | grep dhcrelay
    ```

    Each instance must:

    * Have its own PID
    * Bind only intended interfaces
    * Forward only to its configured server
    NOTE:The base `/etc/default/isc-dhcp-relay` file must be empty so that only instance-specific environment files control relay behavior.

    Reference:
    [dhcrelay-man](https://kb.isc.org/docs/isc-dhcp-44-manual-pages-dhcrelay)

    ---

# DHCPv6 Relay Agent

DHCPv6 relay is a **different mechanism from DHCPv4 relay**, not just the
same thing on a different port. There is no broadcast in IPv6 — clients
send `SOLICIT`/`REQUEST` to the multicast group
`ff02::1:2` (`All_DHCP_Relay_Agents_and_Servers`), scoped to the local
link. The relay agent listens on that multicast group on the
client-facing interface, wraps the entire client packet inside a
`RELAY-FORW` message, and forwards it out the server-facing interface —
by default to the multicast group `All_DHCP_Servers` (`ff05::1:3`),
since `dhcrelay -6` has no CLI option to unicast to a specific server
address (see the invocation section below). Kea's reply comes back as a
unicast `RELAY-REPL`, which the relay unwraps and multicasts back to the
client. This has practical config consequences:

- **No `relay.ip-address` gateway-address matching** the way DHCPv4 does
  it. DHCPv6 relay instead carries a `link-address` field inside
  `RELAY-FORW` — an address the relay owns on the client's link — which
  Kea uses to select the subnet. Configure it the same conceptual way,
  but the field name in Kea's config differs (see below).
- **Multiple relays can nest** — a packet can pass through several
  relay agents before reaching the server, each adding its own
  `RELAY-FORW` layer. Single-hop is the common case and the one covered
  here.
- **`-l` (lower/downstream) and `-u` (upper/upstream)** are the only
  interface flags `dhcrelay -6` accepts — v4's `-i`/`-id`/`-iu` flags do
  not apply in `-6` mode, and v6 mode takes no trailing server-address
  argument on the command line at all (see the invocation section
  below).

## Kea DHCPv6 Server Configuration

```json
{
    "Dhcp6": {
        "interfaces-config": {
            "interfaces": [ "eth0" ]
        },
        "subnet6": [
            {
                "id": 1,
                "subnet": "2001:db8:10::/64",
                "pools": [
                    { "pool": "2001:db8:10::100 - 2001:db8:10::1ff" }
                ],
                "relay": {
                    "ip-addresses": [ "2001:db8:10::1" ]
                },
                "option-data": [
                    { "name": "dns-servers", "data": "2001:4860:4860::8888" }
                ]
            }
        ]
    }
}
```

- `relay.ip-addresses` is a **list**, not a single string — DHCPv6
  supports multiple relay addresses per subnet (e.g. a relay with both a
  global and a ULA address on the client link). DHCPv4's equivalent
  field takes exactly one address; this is a real schema difference, not
  a style choice.
- The address(es) listed must match the relay agent's address **on the
  client-facing interface** — this is what Kea compares against the
  `link-address` field in the incoming `RELAY-FORW`.

## dhcrelay Invocation (DHCPv6)

```bash
dhcrelay -6 -l eth1 -u eth0
```

There is **no trailing server-address argument in `-6` mode** — this is
a real difference from v4, not an oversight. `dhcrelay -6` forwards
`RELAY-FORW` out the upper interface(s) to the multicast group
`All_DHCP_Servers` (`ff05::1:3`, site-scoped) by default. Reachability to
Kea from there depends on Kea listening on that link, or on routing
that carries the multicast to it — not on anything specified at the
command line.

| Flag | Meaning |
|---|---|
| `-6` | IPv6 mode (mutually exclusive with `-4`) |
| `-l <if>[%address][#index]` | Lower / client-facing interface — where `ff02::1:2` is heard. Repeatable (`-l if0 -l if1 ...`). The optional `%address` suffix pins the link-address dhcrelay reports in `RELAY-FORW`; without it, dhcrelay uses the first non-link-local address on the interface. |
| `-u <if>` | Upper / server-facing interface — where `RELAY-FORW` is sent. Repeatable (`-u if0 -u if1 ...`). No address suffix — no way to unicast to a specific server IP from the CLI. |

## Instance Configuration File (v6 variant)

Same templated `isc-dhcp-relay@.service` unit as the v4 setup — the
service file is protocol-agnostic since it just execs `$OPTIONS`. Only
the per-instance environment file changes:

```bash
# /etc/default/isc-dhcp-relay-v6lan
INTERFACES=""

# CRITICAL: leave SERVERS empty for v6 instances.
# The shared unit file appends $SERVERS unconditionally:
#   ExecStart=... $OPTIONS $INTF_CMD $SERVERS
# dhcrelay -6 does not accept a trailing server address the way -4 does —
# if SERVERS is non-empty here, the resulting command line is invalid
# and the service will fail to start.
SERVERS=""

# -6  IPv6 only
# -D  Debug logging
# -l  Lower (client-facing) interface — repeatable
# -u  Upper (server-facing) interface — repeatable
OPTIONS="-6 -D -l br0 -u eth0"
INTF_CMD=""
```

```bash
systemctl enable --now isc-dhcp-relay@v6lan
```

## Running v4 and v6 Relay Simultaneously

Because the template is instantiated per-name (`isc-dhcp-relay@<instance>`),
a v4 relay and a v6 relay can run side by side on the same host as two
independent instances, each with its own environment file:

```bash
/etc/default/isc-dhcp-relay-v4lan   # OPTIONS="-4 -D -id br0 -iu eth0"  SERVERS="10.50.50.1"
/etc/default/isc-dhcp-relay-v6lan   # OPTIONS="-6 -D -l br0 -u eth0"    SERVERS=""
```

```bash
systemctl enable --now isc-dhcp-relay@v4lan
systemctl enable --now isc-dhcp-relay@v6lan
```

Both instances can point at the same physical interfaces even though the
flag names differ between modes (`-id`/`-iu` for v4, `-l`/`-u` for v6) —
`dhcrelay` binds protocol-specific sockets (UDP/67-68 for v4, UDP/546-547
for v6), so there is no port conflict between the two instances. The
`⚠️ Critical Rule` about the base `/etc/default/isc-dhcp-relay` file
being empty applies identically to both.

## Firewall Requirements (v6-specific)

DHCPv6 relay traffic additionally requires:

* UDP 547 inbound on the client-facing interface, destination
  `ff02::1:2` (multicast — not unicast, don't filter by destination
  address alone)
* UDP 547 between relay and Kea server, unicast
* ICMPv6 must not be blocked on the client-facing link — Neighbor
  Discovery still has to function independently of DHCPv6 relay for the
  link to work at all

## Troubleshooting (v6)

```bash
tcpdump -i any port 547 -n -vv
```

Expected packet flow (single relay hop, default multicast forwarding):

1. `SOLICIT` from client's link-local address to `ff02::1:2`, on the
   client-facing (`-l`) interface
2. `RELAY-FORW` from the relay's upper-interface address to
   `All_DHCP_Servers` (`ff05::1:3`), out the `-u` interface,
   encapsulating the original `SOLICIT`, `link-address` set to the
   relay's client-facing address
3. `RELAY-REPL` from `Kea_IP` back to the relay, encapsulating Kea's
   `ADVERTISE` — unicast, since Kea replies directly to the relay that
   forwarded the request
4. `ADVERTISE` (unwrapped) from `Relay_IP` back to `ff02::1:2` on the
   client-facing interface

Step 2 is multicast by default because `-u` takes no destination
address — if Kea is not directly attached to the upper-side link (i.e.
this is a multi-hop relay chain, or Kea sits behind routing that doesn't
carry that multicast group), step 2 needs a further relay hop or an
explicit route/multicast-forwarding rule upstream. This is a structural
difference from v4, where the server address is always explicit on the
command line.

If step 2 never appears, check `link-address` — a relay with no address
configured on the client-facing interface has nothing valid to put in
that field and Kea will reject the packet. If step 3 never appears,
recheck `relay.ip-addresses` in the `subnet6` block against the relay's
actual address — this is the single most common DHCPv6 relay
misconfiguration.

---
>TODO: Load-test relay under concurrent v4+v6 client churn; validate
>behaviour when a client-facing segment has multiple relay addresses
>configured (multi-address `relay.ip-addresses` matching).
---
# Network Topologies as DHCP Relay Host
Purpose: Configuring the Firewall to appropriately act as a relay agent (For the case of Uplink DHCP) for L2/L3 connectivity including VLANs and Bridges.

1. Flat/Direct DHCP

    Direct connection between Server and Client (No relay).
    ```ini
    # /etc/systemd/network/10-flat.network
    [Match]
    Name=eth0
    [Network]
    Address=192.168.1.1/24
    ```

1. VLAN-based Topology

    Creating tagged interfaces for segmented traffic.
    `10-vlan10.netdev`
    ```ini
    # Creates the vlan itself, similarly we make vlan20---vlan_n
    [NetDev]
    Name=vlan10
    Kind=vlan

    [VLAN]
    Id=10 #Each Vlan gets a specific id
    ```
    `vlan10-trunk.network`
    ```ini
    #Adds the vlans to the physical interface. 
    #Also this interface does not get an IP address. 
    #It must remain un-addressed(In the case of tagged vlans).
    [Match]
    Name=eth1 #Physical Interface from which the Vlans are related to.
    [Network]
    VLAN=vlan10
    ```
    `10-vlan10.network`
    ```ini
    #assigns the ip address to the vlan. similar with vlan20
    [Match]
    Name=vlan10
    [Network]
    Address=10.10.10.1/24
    ```

1. Bridge-based Topology

    Grouping multiple ports into a single logical broadcast domain.
    `br0.netdev`
    ```ini
    # /etc/systemd/network/br0.netdev
    [NetDev]     
    Name=br0     
    Kind=bridge  
    ```
    `br0.network`
    ```ini
    # /etc/systemd/network/br0.network
    [Match]                      
    Name = br0                               
    [Network]                    
    Address = 10.10.10.1/24 
    ```

    `bind.network`
    ```ini
    # /etc/systemd/network/bind.network
    [Match]
    Name=eth0 eth1

    [Network]
    Bridge=br0
    ```
