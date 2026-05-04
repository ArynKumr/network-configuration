# DHCPv6 Option Reference

> **Router / Firewall Deployment Profile — Modern + Legacy Coverage**

**Registries:** [IANA DHCPv6 Parameters](https://www.iana.org/assignments/dhcpv6-parameters/dhcpv6-parameters.xhtml) · [ISC Kea all-options.json (v6)](https://gitlab.isc.org/isc-projects/kea/-/blob/master/doc/examples/kea6/all-options.json?ref_type=heads)

**RFCs:** [RFC 3315](https://datatracker.ietf.org/doc/html/rfc3315) · [RFC 3319](https://datatracker.ietf.org/doc/html/rfc3319) · [RFC 3633](https://datatracker.ietf.org/doc/html/rfc3633) · [RFC 3646](https://datatracker.ietf.org/doc/html/rfc3646) · [RFC 3736](https://datatracker.ietf.org/doc/html/rfc3736) · [RFC 3898](https://datatracker.ietf.org/doc/html/rfc3898) · [RFC 4075](https://datatracker.ietf.org/doc/html/rfc4075) · [RFC 4242](https://datatracker.ietf.org/doc/html/rfc4242) · [RFC 4280](https://datatracker.ietf.org/doc/html/rfc4280) · [RFC 4580](https://datatracker.ietf.org/doc/html/rfc4580) · [RFC 4649](https://datatracker.ietf.org/doc/html/rfc4649) · [RFC 4704](https://datatracker.ietf.org/doc/html/rfc4704) · [RFC 4776](https://datatracker.ietf.org/doc/html/rfc4776) · [RFC 4833](https://datatracker.ietf.org/doc/html/rfc4833) · [RFC 5007](https://datatracker.ietf.org/doc/html/rfc5007) · [RFC 5908](https://datatracker.ietf.org/doc/html/rfc5908) · [RFC 6334](https://datatracker.ietf.org/doc/html/rfc6334) · [RFC 6440](https://datatracker.ietf.org/doc/html/rfc6440) · [RFC 6939](https://datatracker.ietf.org/doc/html/rfc6939) · [RFC 7083](https://datatracker.ietf.org/doc/html/rfc7083) · [RFC 7341](https://datatracker.ietf.org/doc/html/rfc7341) · [RFC 8415](https://datatracker.ietf.org/doc/html/rfc8415) · [RFC 8910](https://datatracker.ietf.org/doc/html/rfc8910) · [RFC 9463](https://datatracker.ietf.org/doc/html/rfc9463)

---

## Overview

This DHCPv6 configuration reference is designed to:

- Support modern IPv6-native enterprise clients
- Cover stateful (IA_NA, IA_PD) and stateless (SLAAC+DHCPv6) deployment models
- Provide full routing, provisioning, and service-discovery support
- Bridge legacy transition mechanisms (DS-Lite, 4o6, MAP) for IPv4-in-IPv6 deployments

> [!NOTE]
> DHCPv6 options use a 16-bit code space (vs. 8-bit in DHCPv4), permitting up to 65535 option codes. All options listed below conform to [IANA DHCPv6 Parameters](https://www.iana.org/assignments/dhcpv6-parameters/dhcpv6-parameters.xhtml) and are verified as supported by the [ISC Kea DHCPv6 engine](https://gitlab.isc.org/isc-projects/kea/-/blob/master/doc/examples/kea6/all-options.json?ref_type=heads).

> [!IMPORTANT]
> DHCPv6 does **not** supply a default gateway. The default route in IPv6 is always delivered via ICMPv6 Router Advertisement (RA) per [RFC 4861](https://datatracker.ietf.org/doc/html/rfc4861). DHCPv6 and RA must be used together for full IPv6 operation.

---

## Key Differences from DHCPv4

| Feature | DHCPv4 | DHCPv6 |
| :--- | :--- | :--- |
| Option code width | 8-bit (0–255) | 16-bit (0–65535) |
| Default gateway delivery | Option 3 (Routers) | ICMPv6 RA only — not DHCPv6 |
| Address assignment | Single address via `yiaddr` | IA_NA (Option 3) or IA_TA (Option 4) container options |
| Prefix delegation | Not native | IA_PD (Option 25) — assigns prefixes to routers |
| Client identifier | Option 61 (Client-ID) | DUID carried in Option 1 (CLIENTID) |
| Relay agent info | Option 82 | Options 18, 37 and others |
| Stateless mode | Not applicable | DHCPv6-Lite via [RFC 3736](https://datatracker.ietf.org/doc/html/rfc3736) — options only, no addresses |
| Message multicast | Broadcast to 255.255.255.255 | Multicast to `ff02::1:2` (link) or `ff05::1:3` (site) |

---

## Table of Contents

- [DHCPv6 Option Reference](#dhcpv6-option-reference)
  - [Overview](#overview)
  - [Key Differences from DHCPv4](#key-differences-from-dhcpv4)
  - [Table of Contents](#table-of-contents)
  - [1. Core Identity \& Address Assignment (Essential)](#1-core-identity--address-assignment-essential)
  - [2. Network Configuration](#2-network-configuration)
  - [3. Prefix Delegation](#3-prefix-delegation)
  - [4. DNS \& Domain Resolution](#4-dns--domain-resolution)
  - [5. Time \& Location Services](#5-time--location-services)
  - [6. Boot \& Device Provisioning](#6-boot--device-provisioning)
  - [7. Relay Agent \& Topology Discovery](#7-relay-agent--topology-discovery)
  - [8. Vendor \& Custom Options](#8-vendor--custom-options)
  - [9. IPv4/IPv6 Transition \& Coexistence](#9-ipv4ipv6-transition--coexistence)
  - [10. Security \& Modern Access Control](#10-security--modern-access-control)
  - [11. Legacy \& Rarely Used Options](#11-legacy--rarely-used-options)
  - [Message Type Quick Reference](#message-type-quick-reference)
  - [Lease Lifetime Model](#lease-lifetime-model)
  - [References](#references)
  - [Disclaimer](#disclaimer)

---

## 1. Core Identity & Address Assignment (Essential)

These options form the foundation of every DHCPv6 exchange. They appear in all message types and govern how clients and servers identify themselves and negotiate address leases.

| Code | Name | Purpose | Specification |
| :---: | :--- | :--- | :--- |
| 1 | CLIENTID | Client DUID (DHCP Unique Identifier) | [RFC 8415 §21.2](https://datatracker.ietf.org/doc/html/rfc8415#section-21.2) |
| 2 | SERVERID | Server DUID | [RFC 8415 §21.3](https://datatracker.ietf.org/doc/html/rfc8415#section-21.3) |
| 3 | IA_NA | Identity Association for Non-temporary Addresses | [RFC 8415 §21.4](https://datatracker.ietf.org/doc/html/rfc8415#section-21.4) |
| 4 | IA_TA | Identity Association for Temporary Addresses | [RFC 8415 §21.5](https://datatracker.ietf.org/doc/html/rfc8415#section-21.5) |
| 5 | IAADDR | IPv6 address within an IA_NA or IA_TA | [RFC 8415 §21.6](https://datatracker.ietf.org/doc/html/rfc8415#section-21.6) |
| 13 | STATUS_CODE | Status code for operations (Success, NoAddrsAvail, etc.) | [RFC 8415 §21.13](https://datatracker.ietf.org/doc/html/rfc8415#section-21.13) |
| 14 | RAPID_COMMIT | Enables 2-message Solicit/Reply exchange | [RFC 8415 §21.14](https://datatracker.ietf.org/doc/html/rfc8415#section-21.14) |

> [!NOTE]
> **DUID Types:** The Client/Server ID options carry a DUID, not a MAC address. DUIDs come in four types: DUID-LLT (Link-Layer + Time, type 1, recommended for most devices), DUID-EN (Enterprise Number, type 2), DUID-LL (Link-Layer only, type 3), and DUID-UUID (type 4, RFC 6355). DUIDs persist across interface changes and reboots, unlike MAC addresses.

---

## 2. Network Configuration

These options deliver IP stack configuration to DHCPv6 clients, analogous to core options in DHCPv4.

| Code | Name | Purpose | Specification |
| :---: | :--- | :--- | :--- |
| 7 | PREFERENCE | Server preference value (0–255); higher wins | [RFC 8415 §21.8](https://datatracker.ietf.org/doc/html/rfc8415#section-21.8) |
| 8 | ELAPSED_TIME | Time since client began current exchange (cs) | [RFC 8415 §21.9](https://datatracker.ietf.org/doc/html/rfc8415#section-21.9) |
| 9 | RELAY_MSG | Encapsulated client message in relay agent traffic | [RFC 8415 §21.10](https://datatracker.ietf.org/doc/html/rfc8415#section-21.10) |
| 11 | AUTH | Authentication for DHCPv6 messages | [RFC 8415 §21.11](https://datatracker.ietf.org/doc/html/rfc8415#section-21.11) |
| 12 | UNICAST | Server unicast address for direct client communication | [RFC 8415 §21.12](https://datatracker.ietf.org/doc/html/rfc8415#section-21.12) |
| 21 | SIP_SERVER_A | SIP server IPv6 addresses | [RFC 3319 §3.2](https://datatracker.ietf.org/doc/html/rfc3319#section-3.2) |
| 22 | SIP_SERVER_D | SIP server domain names | [RFC 3319 §3.1](https://datatracker.ietf.org/doc/html/rfc3319#section-3.1) |

> [!WARNING]
> Option 7 (PREFERENCE) is critical in multi-server deployments. If omitted, all servers default to preference 0. Set this deliberately when running primary/secondary DHCP server pairs to avoid split-brain address assignment.

---

## 3. Prefix Delegation

Prefix Delegation (PD) is a DHCPv6-exclusive capability with no DHCPv4 equivalent. It allows a DHCPv6 server to assign an entire IPv6 prefix — not just a single address — to a requesting router, which then sub-delegates that space to its downstream segments.

| Code | Name | Purpose | Specification |
| :---: | :--- | :--- | :--- |
| 25 | IA_PD | Identity Association for Prefix Delegation | [RFC 8415 §21.21](https://datatracker.ietf.org/doc/html/rfc8415#section-21.21) |
| 26 | IAPREFIX | Delegated prefix within an IA_PD (prefix + length + lifetimes) | [RFC 8415 §21.22](https://datatracker.ietf.org/doc/html/rfc8415#section-21.22) |

**Typical ISP CPE deployment flow:**

1. The home router (CPE) sends a **Solicit** with IA_PD requesting a `/56` or `/48`
2. The ISP's BRAS/BNG responds with an **Advertise** containing the delegated prefix
3. The CPE assigns sub-prefixes (e.g., `/64` per LAN segment) from the delegated pool
4. Downstream clients on each LAN segment receive a `/64` prefix via RA and may use SLAAC or stateful DHCPv6 for their individual addresses

> [!NOTE]
> IA_PD (Option 25) and IA_NA (Option 3) can be requested simultaneously in the same Solicit message. A CPE typically requests a prefix via IA_PD for sub-delegation and an address via IA_NA for its own WAN interface.

---

## 4. DNS & Domain Resolution

DNS configuration is among the most commonly used DHCPv6 option groups, especially in stateless (SLAAC + DHCPv6-Lite) deployments where clients obtain a global address via RA but still need DNS resolver information from DHCPv6.

| Code | Name | Purpose | Specification |
| :---: | :--- | :--- | :--- |
| 23 | DNS_SERVERS | Recursive DNS server IPv6 addresses | [RFC 3646 §3](https://datatracker.ietf.org/doc/html/rfc3646#section-3) |
| 24 | DOMAIN_LIST | DNS search domain list | [RFC 3646 §4](https://datatracker.ietf.org/doc/html/rfc3646#section-4) |

> [!NOTE]
> In a SLAAC + stateless DHCPv6 environment, Options 23 and 24 are often the **only** options the server needs to deliver. The client's IPv6 address and default route come from ICMPv6 RA (via RDNSS, Option M=0, O=1). Deploying a full stateful DHCPv6 server solely for DNS is common and valid.

**RA flag interaction:**

| RA M Flag | RA O Flag | Client Behaviour |
| :---: | :---: | :--- |
| 0 | 0 | SLAAC only — no DHCPv6 at all |
| 0 | 1 | SLAAC for address + DHCPv6 for options (stateless) |
| 1 | 0 | Stateful DHCPv6 for address only — unusual |
| 1 | 1 | Stateful DHCPv6 for address and options — full DHCPv6 |

---

## 5. Time & Location Services

| Code | Name | Purpose | Specification |
| :---: | :--- | :--- | :--- |
| 31 | SNTP_SERVERS | SNTP/NTP server IPv6 addresses | [RFC 4075 §4](https://datatracker.ietf.org/doc/html/rfc4075#section-4) |
| 41 | NTP_SERVER | NTP server addresses/FQDNs/multicast groups (supercedes Option 31) | [RFC 5908 §4](https://datatracker.ietf.org/doc/html/rfc5908#section-4) |
| 42 | TIME_ZONE | POSIX timezone string (e.g., `America/New_York`) | [RFC 4833 §3](https://datatracker.ietf.org/doc/html/rfc4833#section-3) |
| 43 | POSIX_TIMEZONE | POSIX TZ string fallback for non-IANA-tz clients | [RFC 4833 §4](https://datatracker.ietf.org/doc/html/rfc4833#section-4) |

> [!WARNING]
> Option 31 (SNTP_SERVERS) is deprecated. Use Option 41 (NTP_SERVER) for all new deployments. RFC 5908 extends the option to support not just IPv6 addresses but also FQDNs and multicast group addresses, making it strictly more capable.

---

## 6. Boot & Device Provisioning

DHCPv6 supports PXE/network boot provisioning for IPv6-only and dual-stack environments.

| Code | Name | Purpose | Specification |
| :---: | :--- | :--- | :--- |
| 15 | USER_CLASS | Client-supplied user class strings for policy selection | [RFC 8415 §21.15](https://datatracker.ietf.org/doc/html/rfc8415#section-21.15) |
| 16 | VENDOR_CLASS | Client vendor class for server-side classification | [RFC 8415 §21.16](https://datatracker.ietf.org/doc/html/rfc8415#section-21.16) |
| 59 | BOOTFILE_URL | Boot file URL (replaces TFTP server + filename combo from DHCPv4) | [RFC 5970 §3.1](https://datatracker.ietf.org/doc/html/rfc5970#section-3.1) |
| 60 | BOOTFILE_PARAM | Parameters passed to the boot file | [RFC 5970 §3.2](https://datatracker.ietf.org/doc/html/rfc5970#section-3.2) |
| 61 | CLIENT_ARCH_TYPE | Client system architecture type (same semantics as DHCPv4 Option 93) | [RFC 5970 §3.3](https://datatracker.ietf.org/doc/html/rfc5970#section-3.3) |
| 62 | NII | Network Interface Identifier (PXE NIC type/revision) | [RFC 5970 §3.4](https://datatracker.ietf.org/doc/html/rfc5970#section-3.4) |

> [!NOTE]
> Option 59 (BOOTFILE_URL) replaces the two-option DHCPv4 pattern of Option 66 (TFTP Server Name) + Option 67 (Boot File Name). In DHCPv6 these are unified into a single URL, which may use `tftp://`, `http://`, or `ftp://` schemes. HTTPS boot is increasingly common in UEFI Secure Boot environments.

---

## 7. Relay Agent & Topology Discovery

DHCPv6 relay agents forward client messages from link-local scope to a DHCPv6 server on a different subnet. These options carry relay-specific metadata used for client identification, topology mapping, and policy enforcement.

| Code | Name | Purpose | Specification |
| :---: | :--- | :--- | :--- |
| 18 | INTERFACE_ID | Relay interface identifier (analogous to DHCPv4 circuit-id) | [RFC 8415 §21.18](https://datatracker.ietf.org/doc/html/rfc8415#section-21.18) |
| 20 | RECONFIGURE_ACCEPT | Client signals willingness to accept Reconfigure messages | [RFC 8415 §21.20](https://datatracker.ietf.org/doc/html/rfc8415#section-21.20) |
| 37 | REMOTE_ID | Relay agent remote-ID (analogous to DHCPv4 remote-id sub-option) | [RFC 4649 §4](https://datatracker.ietf.org/doc/html/rfc4649#section-4) |
| 38 | SUBSCRIBER_ID | Relay subscriber-ID for AAA policy correlation | [RFC 4580 §3](https://datatracker.ietf.org/doc/html/rfc4580#section-3) |
| 52 | PANA_AGENT | PANA Authentication Agent IPv6 addresses | [RFC 5192 §4](https://datatracker.ietf.org/doc/html/rfc5192#section-4) |
| 68 | CLIENT_LINKLAYERADDR | Client link-layer address supplied by relay (for logging/policy) | [RFC 6939 §5](https://datatracker.ietf.org/doc/html/rfc6939#section-6) |

> [!NOTE]
> Option 18 (INTERFACE_ID) is inserted by the relay agent and must be echoed back by the server in its reply so the relay knows which downstream interface to forward the response to. It is not consumed by the client.

---

## 8. Vendor & Custom Options

| Code | Name | Purpose | Specification |
| :---: | :--- | :--- | :--- |
| 17 | VENDOR_OPTS | Vendor-specific options (enterprise number + sub-options) | [RFC 8415 §21.17](https://datatracker.ietf.org/doc/html/rfc8415#section-21.17) |
| 36 | VSIO / ERO | Vendor-specific information option (relay use) | [RFC 4243](https://datatracker.ietf.org/doc/html/rfc4243) |

**Option 17 structure:** Unlike DHCPv4 Option 43, DHCPv6 Option 17 carries the IANA Private Enterprise Number (PEN) inline, removing the need for out-of-band vendor identification. Sub-options are encoded as TLV (Type-Length-Value) tuples within the vendor data payload.

---

## 9. IPv4/IPv6 Transition & Coexistence

These options support hybrid networks running IPv4-in-IPv6 encapsulation technologies. They are essential during migration phases but should be phased out as native IPv6 penetration matures.

| Code | Name | Purpose | Specification |
| :---: | :--- | :--- | :--- |
| 64 | LQ_CLIENT_LINK | Leasequery: links a client to a specific relay | [RFC 5007 §4.1.2](https://datatracker.ietf.org/doc/html/rfc5007#section-4.1.2) |
| 67 | 4RD_MAP_RULE | 4rd mapping rule for IPv4 Residual Deployment | [RFC 7600](https://datatracker.ietf.org/doc/html/rfc7600) |
| 64 | AFTR_NAME | DS-Lite AFTR (tunnel endpoint) FQDN | [RFC 6334 §3](https://datatracker.ietf.org/doc/html/rfc6334#section-3) |
| 89 | MAP_FLAGS | Mapping of Address and Port (MAP) flags | [RFC 7598 §5](https://datatracker.ietf.org/doc/html/rfc7598#section-5) |
| 90 | MAP_RULE | MAP-E / MAP-T encapsulation rules | [RFC 7598 §4](https://datatracker.ietf.org/doc/html/rfc7598#section-4) |
| 91 | MAP_PORTPARAMS | MAP port parameter set (offset, PSID, etc.) | [RFC 7598 §4.4](https://datatracker.ietf.org/doc/html/rfc7598#section-4.4) |
| 88 | DHCP_4O6_SERVER_ADDR | DHCPv4-over-DHCPv6 (4o6) server address | [RFC 7341 §7.2](https://datatracker.ietf.org/doc/html/rfc7341#section-7.2) |

**Transition technology summary:**

| Technology | Mechanism | DHCPv6 Role |
| :--- | :--- | :--- |
| DS-Lite | IPv4 in IPv6 tunnel to ISP AFTR | Delivers AFTR FQDN via Option 64 |
| MAP-E | Stateless IPv4/IPv6 encapsulation | Delivers mapping rules via Options 89–91 |
| MAP-T | Stateless IPv4/IPv6 translation | Same options as MAP-E |
| 4o6 (DHCP 4o6) | DHCPv4 messages tunnelled over IPv6 | Delivers DHCPv4 server address via Option 88 |

---

## 10. Security & Modern Access Control

| Code | Name | Purpose | Reference |
| :---: | :--- | :--- | :--- |
| 103 | CAPTIVE_PORTAL | Captive portal URI for guest/onboarding networks | [RFC 8910 §4.2](https://datatracker.ietf.org/doc/html/rfc8910#section-4.2) |
| 144 | DNR | Encrypted DNS resolver discovery (DoT/DoH/DoQ) | [RFC 9463 §4](https://datatracker.ietf.org/doc/html/rfc9463#section-4) |

> [!NOTE]
> **Option 103 vs. RA DHCP Option 114:** Captive portal is specified for both DHCPv4 (Option 114, RFC 8910) and DHCPv6 (Option 103, RFC 8910). Both carry the same URI payload. In a dual-stack environment both should be provisioned for full client coverage.

> [!NOTE]
> **Option 144 (DNR):** Delivers Encrypted DNS configuration including the Authentication Domain Name (ADN) and connection parameters for DNS-over-TLS (DoT, port 853), DNS-over-HTTPS (DoH), or DNS-over-QUIC (DoQ) resolvers. This supersedes plain DNS server delivery via Option 23 for security-conscious deployments.

---

## 11. Legacy & Rarely Used Options

> [!CAUTION]
> The options below are included for completeness and legacy interoperability only. They should not be configured in new deployments.

| Code | Name | Notes | Reference |
| :---: | :--- | :--- | :--- |
| 10 | RELAY_MSG | Encapsulated relay message (internal use by relay agents) | [RFC 8415](https://datatracker.ietf.org/doc/html/rfc8415) |
| 19 | RECONFIGURE_MSG | Server-initiated client reconfiguration trigger | [RFC 8415 §21.19](https://datatracker.ietf.org/doc/html/rfc8415#section-21.19) |
| 27 | NIS_SERVERS | NIS server IPv6 addresses | [RFC 3898 §3.1](https://datatracker.ietf.org/doc/html/rfc3898#section-3.1) |
| 28 | NISP_SERVERS | NIS+ server IPv6 addresses | [RFC 3898 §3.2](https://datatracker.ietf.org/doc/html/rfc3898#section-3.2) |
| 29 | NIS_DOMAIN_NAME | NIS domain name | [RFC 3898 §3.3](https://datatracker.ietf.org/doc/html/rfc3898#section-3.3) |
| 30 | NISP_DOMAIN_NAME | NIS+ domain name | [RFC 3898 §3.4](https://datatracker.ietf.org/doc/html/rfc3898#section-3.4) |
| 32 | BCMCS_SERVER_D | BCMCS controller domain name list | [RFC 4280 §3](https://datatracker.ietf.org/doc/html/rfc4280#section-3) |
| 33 | BCMCS_SERVER_A | BCMCS controller IPv6 addresses | [RFC 4280 §4](https://datatracker.ietf.org/doc/html/rfc4280#section-4) |
| 40 | CIVIC_ADDRESS | Civic location for VoIP/E911 | [RFC 4776 §3](https://datatracker.ietf.org/doc/html/rfc4776#section-3) |
| 47 | CLIENT_FQDN | Client's fully qualified domain name for DNS update | [RFC 4704 §4](https://datatracker.ietf.org/doc/html/rfc4704#section-4) |
| 65 | EAP | EAP messages for relay-based authentication | [RFC 6440 §4](https://datatracker.ietf.org/doc/html/rfc6440#section-4) |

---

## Message Type Quick Reference

DHCPv6 replaces the DHCPv4 DISCOVER/OFFER/REQUEST/ACK four-way exchange with a more expressive message set. Understanding these is essential for diagnosing DHCP failures.

| Code | Message | Direction | Purpose |
| :---: | :--- | :--- | :--- |
| 1 | SOLICIT | Client → Server | Discover available servers |
| 2 | ADVERTISE | Server → Client | Announce availability and proposed configuration |
| 3 | REQUEST | Client → Server | Request specific addresses/options from a chosen server |
| 4 | CONFIRM | Client → Server | Verify prior addresses are still appropriate (e.g., after roaming) |
| 5 | RENEW | Client → Server | Extend lease lifetimes with same server |
| 6 | REBIND | Client → Server | Extend leases with any server (after RENEW timeout) |
| 7 | REPLY | Server → Client | Authoritative response to Request/Renew/Rebind/etc. |
| 8 | RELEASE | Client → Server | Relinquish one or more addresses |
| 9 | DECLINE | Client → Server | Report that an address is already in use (DAD failed) |
| 10 | RECONFIGURE | Server → Client | Server-initiated update prompt |
| 11 | INFORMATION-REQUEST | Client → Server | Request options only, no address assignment (stateless mode) |
| 12 | RELAY-FORW | Relay → Server | Relay agent forwarding a client message upstream |
| 13 | RELAY-REPL | Server → Relay | Server response to be forwarded downstream |

---

## Lease Lifetime Model

DHCPv6 uses two lifetime values per address (carried in IAADDR, Option 5) instead of DHCPv4's single lease time:

| Parameter | Field | Behaviour |
| :--- | :--- | :--- |
| **Preferred Lifetime** | `preferred-lifetime` | Address is fully usable. After expiry, address becomes deprecated — still valid for existing connections but not used for new ones. |
| **Valid Lifetime** | `valid-lifetime` | Address remains usable for existing connections. After expiry, the address is removed entirely. |
| **T1** | Carried in IA_NA/IA_PD | Time at which client should contact the same server to RENEW. Typically 50% of preferred lifetime. |
| **T2** | Carried in IA_NA/IA_PD | Time at which client should attempt REBIND with any server. Typically 80% of preferred lifetime. |

> [!WARNING]
> `preferred-lifetime` must always be ≤ `valid-lifetime`. Setting them equal is valid and common. Setting `preferred-lifetime` > `valid-lifetime` is a configuration error and will be rejected by compliant clients.

---

## References

| Standard | Description |
| :--- | :--- |
| [IANA DHCPv6 Parameters](https://www.iana.org/assignments/dhcpv6-parameters/dhcpv6-parameters.xhtml) | Authoritative registry of all DHCPv6 option codes and message types |
| [ISC Kea DHCPv6 all-options.json](https://gitlab.isc.org/isc-projects/kea/-/blob/master/doc/examples/kea6/all-options.json?ref_type=heads) | Kea-supported DHCPv6 option reference |
| [RFC 3315](https://datatracker.ietf.org/doc/html/rfc3315) | DHCPv6 (original specification, superseded by RFC 8415) |
| [RFC 3319](https://datatracker.ietf.org/doc/html/rfc3319) | DHCPv6 Options for SIP Servers |
| [RFC 3633](https://datatracker.ietf.org/doc/html/rfc3633) | IPv6 Prefix Options for DHCPv6 (Prefix Delegation) |
| [RFC 3646](https://datatracker.ietf.org/doc/html/rfc3646) | DNS Configuration Options for DHCPv6 |
| [RFC 3736](https://datatracker.ietf.org/doc/html/rfc3736) | Stateless DHCPv6 |
| [RFC 3898](https://datatracker.ietf.org/doc/html/rfc3898) | NIS Options for DHCPv6 |
| [RFC 4075](https://datatracker.ietf.org/doc/html/rfc4075) | SNTP Configuration Options for DHCPv6 |
| [RFC 4242](https://datatracker.ietf.org/doc/html/rfc4242) | Information Refresh Time Option for DHCPv6 |
| [RFC 4280](https://datatracker.ietf.org/doc/html/rfc4280) | DHCP Options for BMCS |
| [RFC 4580](https://datatracker.ietf.org/doc/html/rfc4580) | DHCPv6 Relay Agent Subscriber-ID Option |
| [RFC 4649](https://datatracker.ietf.org/doc/html/rfc4649) | DHCPv6 Relay Agent Remote-ID Option |
| [RFC 4704](https://datatracker.ietf.org/doc/html/rfc4704) | DHCPv6 Client FQDN Option |
| [RFC 4776](https://datatracker.ietf.org/doc/html/rfc4776) | DHCPv4/v6 Civic Address Location Option |
| [RFC 4833](https://datatracker.ietf.org/doc/html/rfc4833) | Timezone Options for DHCP |
| [RFC 5007](https://datatracker.ietf.org/doc/html/rfc5007) | DHCPv6 Leasequery |
| [RFC 5908](https://datatracker.ietf.org/doc/html/rfc5908) | NTP Server Option for DHCPv6 |
| [RFC 5970](https://datatracker.ietf.org/doc/html/rfc5970) | DHCPv6 Options for Network Boot |
| [RFC 6334](https://datatracker.ietf.org/doc/html/rfc6334) | DHCPv6 Option for DS-Lite (AFTR Name) |
| [RFC 6440](https://datatracker.ietf.org/doc/html/rfc6440) | EAP Re-authentication for DHCPv6 |
| [RFC 6939](https://datatracker.ietf.org/doc/html/rfc6939) | Client Link-Layer Address Option in DHCPv6 |
| [RFC 7083](https://datatracker.ietf.org/doc/html/rfc7083) | Modification of Default Values for SOL_MAX_RT and INF_MAX_RT |
| [RFC 7341](https://datatracker.ietf.org/doc/html/rfc7341) | DHCPv4-over-DHCPv6 Transport |
| [RFC 7598](https://datatracker.ietf.org/doc/html/rfc7598) | DHCPv6 Options for MAP (MAP-E/MAP-T) |
| [RFC 8415](https://datatracker.ietf.org/doc/html/rfc8415) | DHCPv6 (current standard, obsoletes RFC 3315) |
| [RFC 8910](https://datatracker.ietf.org/doc/html/rfc8910) | Captive-Portal Identification in DHCP and RA |
| [RFC 9463](https://datatracker.ietf.org/doc/html/rfc9463) | DHCP and RA Options for Encrypted DNS Discovery |

---

## Disclaimer

> [!WARNING]
> The ISC Kea DHCPv6 engine configuration and supported option set may change between releases. The option support referenced in this document was verified against the Kea `all-options.json` example at the time of writing. Always consult the [official ISC Kea documentation](https://kea.readthedocs.io/en/latest/) and release notes for your specific version before deploying.