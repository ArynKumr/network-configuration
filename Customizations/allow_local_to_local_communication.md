# Firewall Self-Access Allow Rules (INPUT Chain)

## Purpose

These rules allow the firewall itself to communicate with:

* **LAN interface addresses**
* **WAN interface addresses**
* **Loopback services**

Without these rules, services running on the firewall (DNS, API, monitoring, etc.) may fail because the `input` chain blocks them.

# Rules

## 1. Allow LAN Interface Self-Traffic

# IPV4

```
nft insert rule inet filter input \
    iifname <lan_iface> \
    ip saddr <ip_on_lan> \
    accept
```

# IPV6

```
nft insert rule inet filter input \
    iifname <lan_iface> \
    ip6 saddr <ip_on_lan> \
    accept
```

---

## 2. Allow WAN Interface Self-Traffic

# IPV4

```
nft insert rule inet filter input \
    iifname <wan_iface> \
    ip saddr <ip_on_wan> \
    accept
```

# IPV6

```
nft insert rule inet filter input \
    iifname <wan_iface> \
    ip6 saddr <ip_on_wan> \
    accept
```

---

## 3. Allow Loopback Traffic

# IPV4

```
nft insert rule inet filter input \
    iifname lo \
    ip saddr 127.0.0.1 \
    accept
```

# IPV6

```
nft insert rule inet filter input \
    iifname lo \
    ip6 saddr ::1 \
    accept
```

---

>NOTE: These rules are needed to be applied during bootup