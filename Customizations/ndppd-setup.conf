# Configuring ndppd for IPv6 Neighbor Proxying

## Example Configuration

File:

```text
/etc/ndppd.conf
```

Configuration:

```conf
route-ttl 30000
address-ttl 30000

proxy <wan_iface> {
    router yes
    timeout 500
    ttl 30000
    promiscuous yes

    rule <isp_ipv6_prefix> {
        iface <lan_iface>
    }
}
```

---

# What ndppd Does

`ndppd` is an IPv6 Neighbor Discovery Proxy Daemon.

It proxies IPv6 Neighbor Discovery Protocol (NDP) messages between interfaces.

---

# Why ndppd Exists

Unlike IPv4:

* IPv6 heavily relies on Neighbor Discovery
* Routers need to answer Neighbor Solicitations
* Upstream devices often expect addresses to exist directly on-link

Problem:

```text
ISP Router
    │
    │ thinks all addresses are on <wan_iface>
    ▼
Your Router
    │
    ├── <lan_iface> → internal network
```

Without ndppd:

* ISP sends Neighbor Solicitation
* Nobody answers
* Traffic dies

ndppd answers on behalf of downstream devices.

---

Traffic flow:

```text
ISP → <wan_iface> → ndppd → <lan_iface> → internal host
```