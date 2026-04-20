# ISC Kea DHCPv6 Configuration Guide — `isc-kea-stable` 3.0.2

> **Target version:** `isc-kea-stable 3.0.2` (LTS)
> **Validated with:** `kea-dhcp6 -t /etc/kea/kea-dhcp6.conf`
> **Architecture:** L2-direct (no relay), MySQL lease + host backends

---

## Table of Contents

- [Overview & RFC Landscape](#overview--rfc-landscape)
- [What Changed in Kea 3.0.x — Breaking & Deprecated Keys](#what-changed-in-kea-30x--breaking--deprecated-keys)
- [RA Flags & Mode Selection](#ra-flags--mode-selection)
- [Mode 1 — Stateful DHCPv6 (IA\_NA)](#mode-1--stateful-dhcpv6-ia_na)
- [Mode 2 — Stateless DHCPv6 (Information-Request only)](#mode-2--stateless-dhcpv6-information-request-only)
- [Mode 3 — Hybrid (SLAAC + Stateful + PD)](#mode-3--hybrid-slaac--stateful--pd)
- [Common Blocks Reference](#common-blocks-reference)
  - [interfaces-config](#interfaces-config)
  - [control-sockets (3.0.x)](#control-sockets-30x)
  - [lease-database](#lease-database)
  - [hosts-database](#hosts-database)
  - [expired-leases-processing](#expired-leases-processing)
  - [Timers & Lifetimes](#timers--lifetimes)
  - [option-data](#option-data)
  - [hooks-libraries](#hooks-libraries)
  - [loggers](#loggers)
- [Static Host Reservations](#static-host-reservations)
- [Prefix Delegation (IA\_PD)](#prefix-delegation-ia_pd)
- [Validation & Operational Commands](#validation--operational-commands)
- [RFC Quick-Reference Table](#rfc-quick-reference-table)

---

## Overview & RFC Landscape

DHCPv6 is not a single mode — it is a **protocol family** defined primarily by [RFC 8415](https://www.rfc-editor.org/rfc/rfc8415) (which obsoletes RFC 3315, RFC 3633, RFC 3736, RFC 7550, and others). The three operational modes correspond to different flag combinations in IPv6 Router Advertisements (RA), defined in [RFC 4861](https://www.rfc-editor.org/rfc/rfc4861).

| Mode | RA M-flag | RA O-flag | Address Source | DHCPv6 Role |
|---|---|---|---|---|
| **Stateful** | `1` | `1` | DHCPv6 IA_NA only | Address + options |
| **Stateless** | `0` | `1` | SLAAC (RFC 4862) | Options only (DNS, NTP…) |
| **Hybrid** | `1` (some) | `1` | DHCPv6 IA_NA **and/or** SLAAC | Address + PD + options |

> [!IMPORTANT]
> Kea controls **only the DHCP server side**. The RA flags (`M`/`O`) must be configured on your **router / radvd / FRR** independently. Kea does not set RA flags.

---

## What Changed in Kea 3.0.x — Breaking & Deprecated Keys

Before writing any config, review these **mandatory changes** introduced between Kea 2.6 and 3.0.

### ❌ Removed / Renamed Parameters

| Old Key (≤ 2.6) | New Key (≥ 3.0) | Notes |
|---|---|---|
| `"control-socket": {}` | `"control-sockets": [{}]` | Now an **array**. Old singular form is silently upgraded on `config-write`, but should not be used in new configs. |
| `"client-class": "name"` | `"client-classes": ["name"]` | Now a **list**. Old singular form is deprecated; both cannot coexist in the same scope. |
| `"reservation-mode": "..."` | _removed entirely_ | Replaced by fine-grained `reservations-global`, `reservations-in-subnet`, `reservations-out-of-pool`. |

### ⚠️ Behavioural Defaults Changed in 3.0

| Parameter | Old default | New default | RFC / Note |
|---|---|---|---|
| Lease caching | disabled | **enabled** | Reduces DB writes on RENEW when lease unchanged |
| `restrict-commands` (HA hook) | `false` | **`true`** | Only HA commands via HA listener |
| Control Agent (kea-ctrl-agent) | required for HTTP API | **deprecated** | Daemons now expose HTTP directly via `control-sockets` |
| Socket directory | any path | **`/var/run/kea`** or `$KEA_CONTROL_SOCKET_DIR` | Sockets outside this dir are rejected |

### 🔐 Security Additions in 3.0

- Kea Control Agent HTTP API now **requires** a password stored in `kea-api-password` before startup.
- Lease files and the DHCPv6 DUID file may only be written under `$KEA_DHCP_DATA_DIR` (default: `/var/lib/kea`).

---

## RA Flags & Mode Selection

Configure your router/radvd to set the correct flags **before** deploying Kea in any mode.

### radvd example — Stateful

```
interface eth0 {
    AdvSendAdvert on;
    AdvManagedFlag on;       # M=1  → use DHCPv6 for addresses
    AdvOtherConfigFlag on;   # O=1  → use DHCPv6 for options
    prefix 2001:db8:1::/64 {
        AdvAutonomous off;   # disable SLAAC
    };
};
```

### radvd example — Stateless (SLAAC + DHCPv6 options)

```
interface eth0 {
    AdvSendAdvert on;
    AdvManagedFlag off;      # M=0  → addresses via SLAAC
    AdvOtherConfigFlag on;   # O=1  → options via DHCPv6
    prefix 2001:db8:1::/64 {
        AdvAutonomous on;    # enable SLAAC
    };
};
```

### radvd example — Hybrid (SLAAC + IA_NA available)

```
interface eth0 {
    AdvSendAdvert on;
    AdvManagedFlag on;       # M=1  → DHCPv6 addresses for clients that request them
    AdvOtherConfigFlag on;   # O=1  → options via DHCPv6
    prefix 2001:db8:1::/64 {
        AdvAutonomous on;    # SLAAC still available for non-DHCPv6 clients
    };
};
```

---

## Mode 1 — Stateful DHCPv6 (IA_NA)

**RFC 8415 §§ 6.1, 18** — Clients send `SOLICIT` → server replies with `ADVERTISE` → client sends `REQUEST` → server sends `REPLY` containing one or more `IA_NA` options with leased addresses.

All addresses are tracked in the lease database. Clients must renew before T1 and rebind before T2.

```jsonc
// /etc/kea/kea-dhcp6.conf — STATEFUL MODE
// Validate: kea-dhcp6 -t /etc/kea/kea-dhcp6.conf
{
  "Dhcp6": {

    // -----------------------------------------------------------------
    // INTERFACE — RFC 8415 §13.1 (direct L2, no relay)
    // -----------------------------------------------------------------
    "interfaces-config": {
      "interfaces": [ "eth0" ]
    },

    // -----------------------------------------------------------------
    // CONTROL SOCKET — Kea 3.0+ syntax (array, not singular object)
    // Unix socket for local CLI; add HTTP entry for remote API access.
    // Socket path must be under /var/run/kea (or $KEA_CONTROL_SOCKET_DIR).
    // -----------------------------------------------------------------
    "control-sockets": [
      {
        "socket-type": "unix",
        "socket-name": "/var/run/kea/kea-dhcp6-ctrl.sock"
      }
    ],

    // -----------------------------------------------------------------
    // LEASE DATABASE — MySQL
    // Stores all IA_NA / IA_PD bindings (RFC 8415 §14)
    // -----------------------------------------------------------------
    "lease-database": {
      "type": "mysql",
      "name": "kea",
      "user": "kea",
      "password": "secret",
      "host": "127.0.0.1",
      "port": 3306
    },

    // -----------------------------------------------------------------
    // HOSTS DATABASE — MySQL
    // Stores static reservations (RFC 8415 §18.3.12)
    // -----------------------------------------------------------------
    "hosts-database": {
      "type": "mysql",
      "name": "kea",
      "user": "kea",
      "password": "secret",
      "host": "127.0.0.1",
      "port": 3306
    },

    // -----------------------------------------------------------------
    // RESERVATION FLAGS (Kea 3.0 — reservation-mode removed)
    // Enable global reservations in addition to subnet reservations.
    // -----------------------------------------------------------------
    "reservations-global": false,
    "reservations-in-subnet": true,
    "reservations-out-of-pool": false,

    // -----------------------------------------------------------------
    // EXPIRED LEASE CLEANUP
    // RFC 8415 §18.3.12: server must eventually free unclaimed leases
    // -----------------------------------------------------------------
    "expired-leases-processing": {
      "reclaim-timer-wait-time": 10,       // seconds between reclaim scans
      "flush-reclaimed-timer-wait-time": 25,
      "hold-reclaimed-time": 3600,         // keep expired leases 1 h before purge
      "max-reclaim-leases": 100,
      "max-reclaim-time": 250,             // ms per reclaim cycle
      "unwarned-reclaim-cycles": 5
    },

    // -----------------------------------------------------------------
    // T1 / T2 — RFC 8415 §14.2
    // calculate-tee-times=true: Kea derives T1=0.5*preferred, T2=0.8*preferred
    // -----------------------------------------------------------------
    "calculate-tee-times": true,

    // -----------------------------------------------------------------
    // LIFETIMES — RFC 8415 §14.2
    // preferred-lifetime: address preferred until deprecated (SLAAC analogue)
    // valid-lifetime:     address valid until expired
    // -----------------------------------------------------------------
    "preferred-lifetime": 3600,
    "valid-lifetime": 7200,

    // -----------------------------------------------------------------
    // GLOBAL OPTIONS — RFC 8415 §21 / RFC 3646 (DNS)
    // Sent to all clients unless overridden at subnet or pool scope.
    // -----------------------------------------------------------------
    "option-data": [
      {
        "name": "dns-servers",          // option 23 — RFC 3646
        "data": "2001:db8::53, 2001:db8::54"
      },
      {
        "name": "domain-search",        // option 24 — RFC 3646
        "data": "example.com"
      }
    ],

    // -----------------------------------------------------------------
    // HOOK LIBRARIES
    // libdhcp_mysql: MySQL lease backend (open source in 3.0+)
    // libdhcp_host_cmds: host reservation API commands
    // -----------------------------------------------------------------
    "hooks-libraries": [
      { "library": "/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_mysql.so" },
      { "library": "/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_host_cmds.so" }
    ],

    // -----------------------------------------------------------------
    // SUBNET6 — Stateful: pools are REQUIRED (RFC 8415 §18.3.4)
    // Clients receive addresses exclusively from the defined pool.
    // -----------------------------------------------------------------
    "subnet6": [
      {
        "id": 1,
        "subnet": "2001:db8:1::/64",
        "interface": "eth0",

        // IA_NA pool — RFC 8415 §21.4
        "pools": [
          {
            "pool": "2001:db8:1::100 - 2001:db8:1::1ff"
          }
        ],

        // Subnet-scoped options override globals (RFC 8415 §7.5)
        "option-data": [
          {
            "name": "dns-servers",
            "data": "2001:db8:1::1"
          }
        ]
      }
    ],

    // -----------------------------------------------------------------
    // LOGGING
    // -----------------------------------------------------------------
    "loggers": [
      {
        "name": "kea-dhcp6",
        "output_options": [
          {
            "output": "/var/log/kea/kea-dhcp6.log",
            "pattern": "%d %-5p [%c] %m\n",
            "maxsize": 10485760,
            "maxver": 5
          }
        ],
        "severity": "INFO",
        "debuglevel": 0
      }
    ]
  }
}
```

---

## Mode 2 — Stateless DHCPv6 (Information-Request only)

**RFC 8415 §§ 6.5, 18.3.7 / RFC 8106** — Clients configure their own address via SLAAC ([RFC 4862](https://www.rfc-editor.org/rfc/rfc4862)). The DHCPv6 server responds only to `INFORMATION-REQUEST` messages, delivering options (DNS, NTP, domain-search, etc.) but **no addresses**.

> [!NOTE]
> In stateless mode, **no `pools` are defined** and `preferred-lifetime` / `valid-lifetime` apply only to any delegated prefixes or options — not to IA_NA. Kea still requires a `subnet6` entry so it knows which interface and scope to answer from.

```jsonc
// /etc/kea/kea-dhcp6.conf — STATELESS MODE (Information-Request only)
// Validate: kea-dhcp6 -t /etc/kea/kea-dhcp6.conf
{
  "Dhcp6": {

    // -----------------------------------------------------------------
    // INTERFACE
    // -----------------------------------------------------------------
    "interfaces-config": {
      "interfaces": [ "eth0" ]
    },

    // -----------------------------------------------------------------
    // CONTROL SOCKET — Kea 3.0+ plural form
    // -----------------------------------------------------------------
    "control-sockets": [
      {
        "socket-type": "unix",
        "socket-name": "/var/run/kea/kea-dhcp6-ctrl.sock"
      }
    ],

    // -----------------------------------------------------------------
    // LEASE DATABASE
    // Still required by Kea even in stateless mode (daemon requirement),
    // but will store no IA_NA leases when no pools are defined.
    // Use memfile for lightweight stateless-only deployments.
    // -----------------------------------------------------------------
    "lease-database": {
      "type": "memfile",
      "lfc-interval": 3600,
      "name": "/var/lib/kea/kea-leases6.csv"
    },

    // -----------------------------------------------------------------
    // GLOBAL OPTIONS — delivered in INFORMATION-REQUEST replies
    // RFC 8415 §18.3.7 / RFC 3646 / RFC 5908 (NTP)
    // -----------------------------------------------------------------
    "option-data": [
      {
        "name": "dns-servers",          // option 23 — RFC 3646
        "data": "2001:4860:4860::8888, 2001:4860:4860::8844"
      },
      {
        "name": "domain-search",        // option 24 — RFC 3646
        "data": "example.com, corp.example.com"
      }
    ],

    // -----------------------------------------------------------------
    // SUBNET6 — NO pools defined → Kea answers only Information-Request
    // RFC 8415 §18.3.7: server MUST NOT assign addresses when M=0.
    // The subnet entry is still required for interface matching.
    // -----------------------------------------------------------------
    "subnet6": [
      {
        "id": 1,
        "subnet": "2001:db8:1::/64",
        "interface": "eth0"
        // No "pools" key → stateless behaviour
      }
    ],

    // -----------------------------------------------------------------
    // LOGGING
    // -----------------------------------------------------------------
    "loggers": [
      {
        "name": "kea-dhcp6",
        "output_options": [
          {
            "output": "/var/log/kea/kea-dhcp6.log",
            "pattern": "%d %-5p [%c] %m\n",
            "maxsize": 10485760,
            "maxver": 5
          }
        ],
        "severity": "INFO",
        "debuglevel": 0
      }
    ]
  }
}
```

---

## Mode 3 — Hybrid (SLAAC + Stateful + PD)

**RFC 8415 §§ 6.6, 18.3** — The hybrid mode accommodates:

- Clients that use **SLAAC** for their link address (M=1, AdvAutonomous=on in radvd)
- Clients that request a **stateful IA_NA** address (e.g., servers, managed devices)
- Routers/CPEs that request a **delegated prefix via IA_PD** ([RFC 8415 §6.3](https://www.rfc-editor.org/rfc/rfc8415#section-6.3))

All three can coexist on the same subnet. Kea serves only what clients ask for: a client that only sends `INFORMATION-REQUEST` gets options; one that sends `SOLICIT` with `IA_NA` gets an address; one with `IA_PD` gets a prefix.

```jsonc
// /etc/kea/kea-dhcp6.conf — HYBRID MODE (SLAAC + Stateful IA_NA + IA_PD)
// Validate: kea-dhcp6 -t /etc/kea/kea-dhcp6.conf
{
  "Dhcp6": {

    // -----------------------------------------------------------------
    // INTERFACE
    // -----------------------------------------------------------------
    "interfaces-config": {
      "interfaces": [ "eth0" ]
    },

    // -----------------------------------------------------------------
    // CONTROL SOCKETS — Kea 3.0+ (plural, array)
    // Unix socket for local control, HTTP for remote API (no CA needed).
    // -----------------------------------------------------------------
    "control-sockets": [
      {
        "socket-type": "unix",
        "socket-name": "/var/run/kea/kea-dhcp6-ctrl.sock"
      },
      {
        // Direct HTTP API — replaces Kea Control Agent (deprecated in 3.0)
        // Bind to loopback only unless TLS is configured.
        "socket-type": "http",
        "socket-address": "127.0.0.1",
        "socket-port": 8007
      }
    ],

    // -----------------------------------------------------------------
    // LEASE DATABASE — MySQL
    // -----------------------------------------------------------------
    "lease-database": {
      "type": "mysql",
      "name": "kea",
      "user": "kea",
      "password": "secret",
      "host": "127.0.0.1",
      "port": 3306
    },

    // -----------------------------------------------------------------
    // HOSTS DATABASE — MySQL
    // -----------------------------------------------------------------
    "hosts-database": {
      "type": "mysql",
      "name": "kea",
      "user": "kea",
      "password": "secret",
      "host": "127.0.0.1",
      "port": 3306
    },

    // -----------------------------------------------------------------
    // RESERVATION FLAGS
    // -----------------------------------------------------------------
    "reservations-global": false,
    "reservations-in-subnet": true,
    "reservations-out-of-pool": true,   // allow reserved addresses outside pool range

    // -----------------------------------------------------------------
    // EXPIRED LEASE CLEANUP
    // -----------------------------------------------------------------
    "expired-leases-processing": {
      "reclaim-timer-wait-time": 10,
      "flush-reclaimed-timer-wait-time": 25,
      "hold-reclaimed-time": 3600,
      "max-reclaim-leases": 100,
      "max-reclaim-time": 250,
      "unwarned-reclaim-cycles": 5
    },

    // -----------------------------------------------------------------
    // TEE TIMES — RFC 8415 §14.2
    // T1 = 0.5 * preferred-lifetime (renew)
    // T2 = 0.8 * preferred-lifetime (rebind)
    // -----------------------------------------------------------------
    "calculate-tee-times": true,
    "preferred-lifetime": 3600,
    "valid-lifetime": 7200,

    // -----------------------------------------------------------------
    // CLIENT CLASSES — Kea 3.0+ plural form (client-class deprecated)
    // Used below to distinguish CPE routers from end-hosts.
    // RFC 8415 §18.2.6: servers may use vendor class / options to classify
    // -----------------------------------------------------------------
    "client-classes": [
      {
        "name": "CPE_ROUTERS",
        // Match clients sending Vendor Class option (option 16) containing "CPE"
        "test": "substring(option[16].hex, 0, 3) == 'CPE'"
      }
    ],

    // -----------------------------------------------------------------
    // GLOBAL OPTIONS
    // -----------------------------------------------------------------
    "option-data": [
      {
        "name": "dns-servers",
        "data": "2001:db8::53"
      },
      {
        "name": "domain-search",
        "data": "example.com"
      }
    ],

    // -----------------------------------------------------------------
    // HOOK LIBRARIES
    // -----------------------------------------------------------------
    "hooks-libraries": [
      { "library": "/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_mysql.so" },
      { "library": "/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_host_cmds.so" }
    ],

    // -----------------------------------------------------------------
    // SUBNET6 — Hybrid
    // One subnet, three behaviours depending on what the client requests:
    //   • SLAAC clients    → get nothing from Kea (RA-driven, M-flag handled by router)
    //   • IA_NA clients    → get address from pool
    //   • IA_PD clients    → get delegated prefix from pd-pools
    // RFC 8415 §§ 6.1 (IA_NA), 6.3 (IA_PD), 18.3.4, 18.3.8
    // -----------------------------------------------------------------
    "subnet6": [
      {
        "id": 1,
        "subnet": "2001:db8:1::/48",
        "interface": "eth0",

        // IA_NA pool — for end-hosts requesting a managed address
        "pools": [
          {
            "pool": "2001:db8:1:0::100 - 2001:db8:1:0::1ff"
          }
        ],

        // IA_PD pool — for CPE routers requesting a /56 delegated prefix
        // RFC 8415 §21.22 / §18.3.8
        "pd-pools": [
          {
            "prefix": "2001:db8:1:100::",
            "prefix-len": 48,
            "delegated-len": 56,
            // Only CPE_ROUTERS class may obtain a delegated prefix
            "client-classes": [ "CPE_ROUTERS" ]
          }
        ],

        // Static reservations inline (can also live in hosts-database)
        "reservations": [
          {
            "duid": "01:02:03:04:05:06:07:08",
            "ip-addresses": [ "2001:db8:1::10" ],
            "hostname": "server1.example.com"
          }
        ]
      }
    ],

    // -----------------------------------------------------------------
    // LOGGING
    // -----------------------------------------------------------------
    "loggers": [
      {
        "name": "kea-dhcp6",
        "output_options": [
          {
            "output": "/var/log/kea/kea-dhcp6.log",
            "pattern": "%d %-5p [%c] %m\n",
            "maxsize": 10485760,
            "maxver": 5
          }
        ],
        "severity": "INFO",
        "debuglevel": 0
      }
    ]
  }
}
```

---

## Common Blocks Reference

### `interfaces-config`

```jsonc
"interfaces-config": {
  "interfaces": [ "eth0" ]       // Listen on specific interface(s)
  // "interfaces": [ "*" ]       // Listen on ALL interfaces (not recommended in production)
}
```

RFC 8415 §13 requires the server to listen on `ff02::1:2` (All_DHCP_Relay_Agents_and_Servers multicast) on each configured interface.

---

### `control-sockets` (3.0.x)

**Key change from ≤ 2.6:** `control-socket` (singular object) → `control-sockets` (array).

```jsonc
"control-sockets": [
  // Unix socket — local control only, fastest
  {
    "socket-type": "unix",
    "socket-name": "/var/run/kea/kea-dhcp6-ctrl.sock"
    // Path must be under /var/run/kea or $KEA_CONTROL_SOCKET_DIR
  },

  // HTTP — direct API (replaces kea-ctrl-agent, deprecated in 3.0)
  // Bind to loopback unless TLS is also configured.
  {
    "socket-type": "http",
    "socket-address": "127.0.0.1",
    "socket-port": 8007
  }

  // HTTPS — recommended for any non-loopback access
  // {
  //   "socket-type": "https",
  //   "socket-address": "0.0.0.0",
  //   "socket-port": 8007,
  //   "trust-anchor": "/etc/ssl/ca.pem",
  //   "cert-file":   "/etc/ssl/kea.crt",
  //   "key-file":    "/etc/ssl/kea.key"
  // }
]
```

> [!WARNING]
> Kea 3.0 restricts Unix socket paths to `/var/run/kea` by default. Override with the environment variable `KEA_CONTROL_SOCKET_DIR` **before** starting the daemon. Sockets in `/tmp` or other paths will be rejected.

---

### `lease-database`

```jsonc
// MySQL (production)
"lease-database": {
  "type": "mysql",
  "name": "kea",
  "user": "kea",
  "password": "secret",
  "host": "127.0.0.1",
  "port": 3306,
  "reconnect-wait-time": 3000,      // ms
  "max-reconnect-tries": 3,
  "on-fail": "serve-retry-continue" // or "stop-retry-exit"
}

// Memfile (lightweight / stateless deployments)
// "lease-database": {
//   "type": "memfile",
//   "lfc-interval": 3600,
//   "name": "/var/lib/kea/kea-leases6.csv"
// }
```

---

### `hosts-database`

Stores static reservations (DUID → address / prefix / options). Separate from lease-database.

```jsonc
"hosts-database": {
  "type": "mysql",
  "name": "kea",
  "user": "kea",
  "password": "secret",
  "host": "127.0.0.1",
  "port": 3306
}
```

---

### `expired-leases-processing`

Controls how Kea reclaims leases after `valid-lifetime` expires (RFC 8415 §18.3.12).

```jsonc
"expired-leases-processing": {
  "reclaim-timer-wait-time": 10,          // seconds between reclaim scans
  "flush-reclaimed-timer-wait-time": 25,  // seconds between purge scans
  "hold-reclaimed-time": 3600,            // keep expired leases N seconds before DB delete
  "max-reclaim-leases": 100,              // leases reclaimed per cycle (0 = unlimited)
  "max-reclaim-time": 250,                // ms budget per reclaim cycle (0 = unlimited)
  "unwarned-reclaim-cycles": 5            // cycles before warning log if limit hit
}
```

---

### Timers & Lifetimes

| Parameter | RFC | Description |
|---|---|---|
| `preferred-lifetime` | RFC 8415 §14.2 | Seconds until address becomes deprecated. T1 = 0.5×, T2 = 0.8× when `calculate-tee-times: true`. |
| `valid-lifetime` | RFC 8415 §14.2 | Seconds until address expires entirely. Must be ≥ preferred-lifetime. |
| `min-preferred-lifetime` | RFC 8415 §14.2 | Floor for client-requested lifetimes. |
| `max-preferred-lifetime` | RFC 8415 §14.2 | Ceiling for client-requested lifetimes. |
| `calculate-tee-times` | RFC 8415 §14.2 | Let Kea compute T1/T2 automatically. Set `false` to specify `t1-percent` / `t2-percent` manually. |

---

### `option-data`

DHCPv6 options are identified by their IANA-assigned option codes. Common options:

| Name | Option | RFC |
|---|---|---|
| `dns-servers` | 23 | RFC 3646 |
| `domain-search` | 24 | RFC 3646 |
| `sntp-servers` | 31 | RFC 4075 |
| `information-refresh-time` | 32 | RFC 8415 §21.23 |
| `sol-max-rt` | 82 | RFC 7083 |
| `inf-max-rt` | 83 | RFC 7083 |
| `aftr-name` | 64 | RFC 6334 |
| `ntp-server` | 56 | RFC 5908 |

```jsonc
"option-data": [
  {
    "name": "dns-servers",
    "data": "2001:db8::53, 2001:db8::54"
  },
  {
    "name": "information-refresh-time",  // option 32 — RFC 8415 §21.23
    "data": "86400"                       // stateless clients re-query every 24 h
  }
]
```

> [!TIP]
> For stateless deployments, always set `information-refresh-time` (option 32). It controls how often clients send `INFORMATION-REQUEST` to refresh options. Omitting it means clients may cache options indefinitely (RFC 8415 §21.23).

---

### `hooks-libraries`

Most hooks are **open source** in Kea 3.0+ (previously commercial). Commercially licensed exceptions: RBAC, Configuration Backend (CB).

```jsonc
"hooks-libraries": [
  // MySQL lease / host storage (open source in 3.0+)
  { "library": "/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_mysql.so" },

  // PostgreSQL alternative
  // { "library": "/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_pgsql.so" },

  // Host reservation API commands (host6-add, host6-get, etc.)
  { "library": "/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_host_cmds.so" },

  // Lease commands (lease6-add, lease6-get, lease6-del, etc.)
  { "library": "/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_lease_cmds.so" },

  // Prefix Delegation support (required for IA_PD in some builds)
  // { "library": "/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_flex_id.so" },

  // Statistics commands
  { "library": "/usr/lib/x86_64-linux-gnu/kea/hooks/libdhcp_stat_cmds.so" }
]
```

---

### `loggers`

```jsonc
"loggers": [
  {
    "name": "kea-dhcp6",              // root DHCPv6 logger
    "output_options": [
      {
        "output": "/var/log/kea/kea-dhcp6.log",
        "pattern": "%d %-5p [%c] %m\n",
        "maxsize": 10485760,           // 10 MB per file
        "maxver": 5                    // keep 5 rotated files
      }
    ],
    "severity": "INFO",               // DEBUG | INFO | WARN | ERROR | FATAL
    "debuglevel": 0                   // 0–99; only relevant when severity=DEBUG
  },
  {
    // Separate logger for alloc engine (verbose lease assignment tracing)
    "name": "kea-dhcp6.alloc-engine",
    "output_options": [
      { "output": "/var/log/kea/kea-dhcp6-alloc.log" }
    ],
    "severity": "WARN",
    "debuglevel": 0
  }
]
```

---

## Static Host Reservations

Reservations match clients by DUID ([RFC 8415 §11](https://www.rfc-editor.org/rfc/rfc8415#section-11)) or HW address. They may be stored inline in `subnet6` or in `hosts-database`.

```jsonc
"reservations": [
  {
    // Match by DUID-LL (type 3) — RFC 8415 §11.4
    "duid": "00:03:00:01:aa:bb:cc:dd:ee:ff",
    "ip-addresses": [ "2001:db8:1::10" ],
    "prefixes": [ "2001:db8:2:100::/56" ],   // also reserve a delegated prefix
    "hostname": "server1.example.com",
    "option-data": [
      {
        "name": "dns-servers",
        "data": "2001:db8::1"                 // reservation-specific DNS override
      }
    ]
  },
  {
    // Match by HW address (less common in DHCPv6, but supported)
    "hw-address": "aa:bb:cc:dd:ee:ff",
    "ip-addresses": [ "2001:db8:1::20" ]
  }
]
```

---

## Prefix Delegation (IA_PD)

RFC 8415 §§ 6.3, 18.3.8 — Kea can delegate IPv6 prefixes to requesting routers (CPEs). Define `pd-pools` in addition to (or instead of) `pools`.

```jsonc
"pd-pools": [
  {
    "prefix": "2001:db8:2::",        // parent prefix to delegate from
    "prefix-len": 48,                // length of the parent prefix
    "delegated-len": 56,             // length of each delegated prefix (/56 per CPE)
    // Optional: restrict to a class — Kea 3.0+ plural form
    "client-classes": [ "CPE_ROUTERS" ]
  }
]
```

This delegates unique `/56` prefixes carved from `2001:db8:2::/48`. Each CPE receives one `/56` it can then sub-delegate or assign to its own LANs.

---

## Validation & Operational Commands

### Config Validation

```bash
# Validate config file syntax (exits non-zero on error)
kea-dhcp6 -t /etc/kea/kea-dhcp6.conf

# Check full config including hook library loading
kea-dhcp6 -c /etc/kea/kea-dhcp6.conf --check-only
```

### Common API Commands (Unix socket)

```bash
# Fetch running config
echo '{ "command": "config-get", "service": ["dhcp6"] }' \
  | socat UNIX-CONNECT:/var/run/kea/kea-dhcp6-ctrl.sock -

# Write running config back to disk (uses new 3.0 syntax on save)
echo '{ "command": "config-write", "service": ["dhcp6"], "arguments": { "filename": "/etc/kea/kea-dhcp6.conf" } }' \
  | socat UNIX-CONNECT:/var/run/kea/kea-dhcp6-ctrl.sock -

# Live status
echo '{ "command": "status-get", "service": ["dhcp6"] }' \
  | socat UNIX-CONNECT:/var/run/kea/kea-dhcp6-ctrl.sock -

# List active leases (requires libdhcp_lease_cmds.so)
echo '{ "command": "lease6-get-all", "service": ["dhcp6"] }' \
  | socat UNIX-CONNECT:/var/run/kea/kea-dhcp6-ctrl.sock -

# Statistics
echo '{ "command": "statistic-get-all", "service": ["dhcp6"] }' \
  | socat UNIX-CONNECT:/var/run/kea/kea-dhcp6-ctrl.sock -
```

### Systemd

```bash
systemctl start  kea-dhcp6
systemctl enable kea-dhcp6
systemctl reload kea-dhcp6     # triggers config-reload via signal
journalctl -u kea-dhcp6 -f
```

---

## RFC Quick-Reference Table

| RFC | Title | Relevance to this guide |
|---|---|---|
| [RFC 8415](https://www.rfc-editor.org/rfc/rfc8415) | Dynamic Host Configuration Protocol for IPv6 (DHCPv6) | Core protocol — obsoletes RFC 3315, 3633, 3736, 7550 |
| [RFC 4861](https://www.rfc-editor.org/rfc/rfc4861) | Neighbor Discovery for IPv6 | RA M/O flags that select stateful vs stateless mode |
| [RFC 4862](https://www.rfc-editor.org/rfc/rfc4862) | IPv6 Stateless Address Autoconfiguration (SLAAC) | Address self-configuration when M=0 |
| [RFC 3646](https://www.rfc-editor.org/rfc/rfc3646) | DNS Configuration options for DHCPv6 | Options 23 (`dns-servers`), 24 (`domain-search`) |
| [RFC 4075](https://www.rfc-editor.org/rfc/rfc4075) | SNTP Configuration Option for DHCPv6 | Option 31 (`sntp-servers`) |
| [RFC 5908](https://www.rfc-editor.org/rfc/rfc5908) | Network Time Protocol (NTP) Server Option for DHCPv6 | Option 56 (`ntp-server`) |
| [RFC 7083](https://www.rfc-editor.org/rfc/rfc7083) | Modification to Default Values of SOL_MAX_RT and INF_MAX_RT | Options 82, 83; tuning SOLICIT/INFORMATION-REQUEST retries |
| [RFC 6334](https://www.rfc-editor.org/rfc/rfc6334) | Dual-Stack Lite AFTR Name DHCPv6 Option | Option 64 (`aftr-name`) for DS-Lite deployments |
| [RFC 8106](https://www.rfc-editor.org/rfc/rfc8106) | IPv6 Router Advertisement Options for DNS Configuration | RDNSS/DNSSL in RA; complements stateless DHCPv6 |
| [RFC 7550](https://www.rfc-editor.org/rfc/rfc7550) | Issues and Recommendations with Multiple Stateful DHCPv6 Options | Hybrid IA_NA + IA_PD interaction rules (obsoleted/absorbed by RFC 8415) |

---

<details>
<summary><strong>Migration Cheatsheet — Kea 2.6 → 3.0</strong></summary>

```diff
- "control-socket": { "socket-type": "unix", "socket-name": "/tmp/kea.sock" }
+ "control-sockets": [ { "socket-type": "unix", "socket-name": "/var/run/kea/kea-dhcp6-ctrl.sock" } ]

- "client-class": "MANAGED_DEVICES"
+ "client-classes": [ "MANAGED_DEVICES" ]

- "reservation-mode": "all"
+ "reservations-global": true
+ "reservations-in-subnet": true
+ "reservations-out-of-pool": false

# HA hook only:
- "restrict-commands": false
+ "restrict-commands": true    # (now the default — only needed to override back to false)
```

> After any `config-write` on Kea 3.0, the file will be **rewritten in 3.0 syntax**, replacing any legacy keys automatically. Keep a backup before your first write.

</details>
