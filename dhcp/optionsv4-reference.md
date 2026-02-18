# DHCPv4 Option Reference

> **Router / Firewall Deployment Profile — Modern + Legacy Coverage**

**Registries:** [IANA BOOTP/DHCP Parameters](https://www.iana.org/assignments/bootp-dhcp-parameters/bootp-dhcp-parameters.xhtml) · [ISC Kea all-options.json](https://gitlab.isc.org/isc-projects/kea/-/blob/master/doc/examples/kea4/all-options.json?ref_type=heads)

**RFCs:** [RFC 2132](https://datatracker.ietf.org/doc/html/rfc2132) · [RFC 2241](https://datatracker.ietf.org/doc/html/rfc2241) · [RFC 2610](https://datatracker.ietf.org/doc/html/rfc2610) · [RFC 3011](https://datatracker.ietf.org/doc/html/rfc3011) · [RFC 3397](https://datatracker.ietf.org/doc/html/rfc3397) · [RFC 3442](https://datatracker.ietf.org/doc/html/rfc3442) · [RFC 3679](https://datatracker.ietf.org/doc/html/rfc3679) · [RFC 3925](https://datatracker.ietf.org/doc/html/rfc3925) · [RFC 4578](https://datatracker.ietf.org/doc/html/rfc4578) · [RFC 5969](https://datatracker.ietf.org/doc/html/rfc5969) · [RFC 8910](https://datatracker.ietf.org/doc/html/rfc8910) · [RFC 8925](https://datatracker.ietf.org/doc/html/rfc8925) · [RFC 9463](https://datatracker.ietf.org/doc/html/rfc9463)

---

## Overview

This DHCP configuration reference is designed to:

- Support modern enterprise clients
- Maintain compatibility with legacy systems
- Provide full routing and provisioning support
- Preserve historical protocol interoperability where required

> [!NOTE]
> All options listed below conform to [IANA BOOTP/DHCP Parameters](https://www.iana.org/assignments/bootp-dhcp-parameters/bootp-dhcp-parameters.xhtml) and are verified as supported by the [ISC Kea DHCPv4 engine](https://gitlab.isc.org/isc-projects/kea/-/blob/master/doc/examples/kea4/all-options.json?ref_type=heads).

---

## Table of Contents

- [1. Core Network Operation](#1-core-network-operation-essential)
- [2. Advanced Routing & IP Behavior](#2-advanced-routing--ip-behavior-situational)
- [3. Legacy Enterprise Infrastructure](#3-legacy-enterprise-infrastructure)
  - [NetBIOS / WINS](#netbios--wins-pre-active-directory-windows)
  - [NIS / NIS+](#nis--nis-unix-legacy)
  - [Novell NetWare / Banyan VINES](#novell-netware--banyan-vines)
- [4. Boot & Device Provisioning](#4-boot--device-provisioning)
- [5. Application Service Location](#5-application-service-location-legacy-model)
- [6. Service Discovery & Directory Extensions](#6-service-discovery--directory-extensions)
- [7. Mobility, Transition & Specialized Networking](#7-mobility-transition--specialized-networking)
- [8. Security & Modern Access Control](#8-security--modern-access-control)
- [9. Historical / Rarely Used Options](#9-historical--rarely-used-options)
- [10. Vendor & Custom Options](#10-vendor--custom-options)

---

## 1. Core Network Operation (Essential)

Required for basic IP connectivity. Core standards are defined in [RFC 2132](https://datatracker.ietf.org/doc/html/rfc2132).

| Code | Name | Purpose | Specification |
| :---: | :--- | :--- | :--- |
| 1 | Subnet Mask | Defines client subnet boundary | [RFC 2132 §3.3](https://datatracker.ietf.org/doc/html/rfc2132#section-3.3) |
| 3 | Routers | Default gateway | [RFC 2132 §3.5](https://datatracker.ietf.org/doc/html/rfc2132#section-3.5) |
| 6 | Domain Name Servers | DNS resolution | [RFC 2132 §3.8](https://datatracker.ietf.org/doc/html/rfc2132#section-3.8) |
| 15 | Domain Name | Default DNS suffix | [RFC 2132 §3.17](https://datatracker.ietf.org/doc/html/rfc2132#section-3.17) |
| 26 | Interface MTU | Defines client MTU | [RFC 2132 §4.6](https://datatracker.ietf.org/doc/html/rfc2132#section-4.6) |
| 28 | Broadcast Address | Subnet broadcast | [RFC 2132 §3.14](https://datatracker.ietf.org/doc/html/rfc2132#section-3.14) |
| 42 | NTP Servers | Time synchronization | [RFC 2132 §8.3](https://datatracker.ietf.org/doc/html/rfc2132#section-8.3) |
| 54 | DHCP Server Identifier | Identifies DHCP server | [RFC 2132 §9.7](https://datatracker.ietf.org/doc/html/rfc2132#section-9.7) |
| 119 | Domain Search | DNS search domains | [RFC 3397](https://datatracker.ietf.org/doc/html/rfc3397) |
| 121 | Classless Static Route | Modern route injection | [RFC 3442](https://datatracker.ietf.org/doc/html/rfc3442) |

---

## 2. Advanced Routing & IP Behavior (Situational)

These options influence routing behavior and IP stack characteristics of the client.

> [!WARNING]
> Option 33 (Static Routes) is superseded by Option 121 (Classless Static Route) in modern environments. Use Option 33 only where clients do not support RFC 3442.

| Code | Name | Use Case | Reference |
| :---: | :--- | :--- | :--- |
| 19 | IP Forwarding | Enable client routing | [RFC 2132 §4.1](https://datatracker.ietf.org/doc/html/rfc2132#section-4.1) |
| 23 | Default IP TTL | Set default IPv4 Time to Live | [RFC 2132 §4.3](https://datatracker.ietf.org/doc/html/rfc2132#section-4.3) |
| 31 | Router Discovery | ICMP router discovery | [RFC 2132 §5.1](https://datatracker.ietf.org/doc/html/rfc2132#section-5.1) |
| 33 | Static Routes | Legacy route injection | [RFC 2132 §7.6](https://datatracker.ietf.org/doc/html/rfc2132#section-7.6) |
| 35 | ARP Cache Timeout | ARP aging control | [RFC 2132 §6.3](https://datatracker.ietf.org/doc/html/rfc2132#section-6.3) |
| 118 | Subnet Selection | Multi-subnet relay environments | [RFC 3011](https://datatracker.ietf.org/doc/html/rfc3011) |

---

## 3. Legacy Enterprise Infrastructure

> [!IMPORTANT]
> The options in this section are required only in environments still running older directory or naming systems. They are not needed in modern deployments.

### NetBIOS / WINS (Pre-Active Directory Windows)

| Code | Name | Reference |
| :---: | :--- | :--- |
| 44 | NetBIOS Name Servers | [RFC 2132 §8.7](https://datatracker.ietf.org/doc/html/rfc2132#section-8.7) |
| 46 | NetBIOS Node Type | [RFC 2132 §8.9](https://datatracker.ietf.org/doc/html/rfc2132#section-8.9) |

### NIS / NIS+ (Unix Legacy)

| Code | Name | Reference |
| :---: | :--- | :--- |
| 40 | NIS Domain | [RFC 2132 §8.1](https://datatracker.ietf.org/doc/html/rfc2132#section-8.1) |
| 64 | NIS+ Domain Name | [RFC 2132 §8.11](https://datatracker.ietf.org/doc/html/rfc2132#section-8.11) |

### Novell NetWare / Banyan VINES

| Code | Name | Reference |
| :---: | :--- | :--- |
| 85 | NDS Servers | [RFC 2241](https://datatracker.ietf.org/doc/html/rfc2241) |
| 75 | StreetTalk Server | [RFC 2132 §10.8](https://datatracker.ietf.org/doc/html/rfc2132#section-10.8) |

---

## 4. Boot & Device Provisioning

Required for PXE boot, diskless systems, and automated appliance deployment.

| Code | Name | Use | Reference |
| :---: | :--- | :--- | :--- |
| 66 | TFTP Server Name | Boot server hostname | [RFC 2132 §9.4](https://datatracker.ietf.org/doc/html/rfc2132#section-9.4) |
| 67 | Boot File Name | Boot image path | [RFC 2132 §9.5](https://datatracker.ietf.org/doc/html/rfc2132#section-9.5) |
| 93 | Client System Architecture | PXE architecture type | [RFC 4578](https://datatracker.ietf.org/doc/html/rfc4578) |
| 97 | UUID/GUID | Client identifier | [RFC 4578](https://datatracker.ietf.org/doc/html/rfc4578) |

---

## 5. Application Service Location (Legacy Model)

This is a historical model for service discovery that predates DNS SRV records. Not recommended for new deployments.

| Code | Name | Reference |
| :---: | :--- | :--- |
| 9 | LPR Servers | [RFC 2132 §3.11](https://datatracker.ietf.org/doc/html/rfc2132#section-3.11) |
| 48 | Font Servers | [RFC 2132 §9.1](https://datatracker.ietf.org/doc/html/rfc2132#section-9.1) |
| 69 | SMTP Server | [RFC 2132 §10.2](https://datatracker.ietf.org/doc/html/rfc2132#section-10.2) |
| 72 | WWW Server | [RFC 2132 §10.5](https://datatracker.ietf.org/doc/html/rfc2132#section-10.5) |

> [!NOTE]
> Option 48 (Font Servers) is defined in RFC 2132 §9.1, not §8.11. The §8.11 reference belongs to Option 64 (NIS+ Domain Name).

---

## 6. Service Discovery & Directory Extensions

| Code | Name | Reference |
| :---: | :--- | :--- |
| 78 | SLP Directory Agent | [RFC 2610](https://datatracker.ietf.org/doc/html/rfc2610) |
| 112 | NetInfo Server Address | [RFC 3679](https://datatracker.ietf.org/doc/html/rfc3679) |

---

## 7. Mobility, Transition & Specialized Networking

| Code | Name | Reference |
| :---: | :--- | :--- |
| 68 | Mobile IP Home Agent | [RFC 2132 §9.6](https://datatracker.ietf.org/doc/html/rfc2132#section-9.6) |
| 108 | v6-only-preferred | [RFC 8925](https://datatracker.ietf.org/doc/html/rfc8925) |
| 212 | 6rd (IPv6 Rapid Deployment) | [RFC 5969](https://datatracker.ietf.org/doc/html/rfc5969) |

---

## 8. Security & Modern Access Control

| Code | Name | Purpose | Reference |
| :---: | :--- | :--- | :--- |
| 114 | Captive Portal | Guest network login URI | [RFC 8910](https://datatracker.ietf.org/doc/html/rfc8910) |
| 162 | v4 DNR | Encrypted DNS server discovery | [RFC 9463](https://datatracker.ietf.org/doc/html/rfc9463) |

---

## 9. Historical / Rarely Used Options

> [!CAUTION]
> These options are included for completeness and legacy interoperability only. They should not be configured in new deployments.

| Code | Name | Reference |
| :---: | :--- | :--- |
| 2 | Time Offset | [RFC 2132 §3.4](https://datatracker.ietf.org/doc/html/rfc2132#section-3.4) |
| 5 | Name Servers (IEN-116) | [RFC 2132 §3.7](https://datatracker.ietf.org/doc/html/rfc2132#section-3.7) |

---

## 10. Vendor & Custom Options

| Code | Name | Reference |
| :---: | :--- | :--- |
| 43 | Vendor Specific Info | [RFC 2132 §8.4](https://datatracker.ietf.org/doc/html/rfc2132#section-8.4) |
| 60 | Vendor Class Identifier | [RFC 2132 §9.13](https://datatracker.ietf.org/doc/html/rfc2132#section-9.13) |
| 124 | VIVCO (Vendor-Identifying Vendor Class) | [RFC 3925](https://datatracker.ietf.org/doc/html/rfc3925) |

---

## References

| Standard | Description |
| :--- | :--- |
| [IANA BOOTP/DHCP Parameters](https://www.iana.org/assignments/bootp-dhcp-parameters/bootp-dhcp-parameters.xhtml) | Authoritative registry of all DHCP option codes |
| [ISC Kea all-options.json](https://gitlab.isc.org/isc-projects/kea/-/blob/master/doc/examples/kea4/all-options.json?ref_type=heads) | Kea-supported option reference |
| [RFC 2132](https://datatracker.ietf.org/doc/html/rfc2132) | DHCP Options and BOOTP Vendor Extensions |
| [RFC 2241](https://datatracker.ietf.org/doc/html/rfc2241) | Novell NDS Options |
| [RFC 2610](https://datatracker.ietf.org/doc/html/rfc2610) | DHCP Options for Service Location Protocol |
| [RFC 3011](https://datatracker.ietf.org/doc/html/rfc3011) | IPv4 Subnet Selection Option |
| [RFC 3397](https://datatracker.ietf.org/doc/html/rfc3397) | DHCP Domain Search Option |
| [RFC 3442](https://datatracker.ietf.org/doc/html/rfc3442) | Classless Static Route Option |
| [RFC 3679](https://datatracker.ietf.org/doc/html/rfc3679) | Unused DHCP Option Codes (NetInfo) |
| [RFC 3925](https://datatracker.ietf.org/doc/html/rfc3925) | Vendor-Identifying Vendor Options |
| [RFC 4578](https://datatracker.ietf.org/doc/html/rfc4578) | DHCP Options for PXE |
| [RFC 5969](https://datatracker.ietf.org/doc/html/rfc5969) | IPv6 Rapid Deployment (6rd) |
| [RFC 8910](https://datatracker.ietf.org/doc/html/rfc8910) | Captive-Portal Identification in DHCP |
| [RFC 8925](https://datatracker.ietf.org/doc/html/rfc8925) | IPv6-Only Preferred Option |
| [RFC 9463](https://datatracker.ietf.org/doc/html/rfc9463) | DHCP and RA Options for Encrypted DNS Discovery |

---

## Disclaimer

> [!WARNING]
> The ISC Kea DHCPv4 engine configuration and supported option set may change between releases. The option support referenced in this document was verified against the Kea `all-options.json` example at the time of writing. Always consult the [official ISC Kea documentation](https://kea.readthedocs.io/en/latest/) and release notes for your specific version before deploying.