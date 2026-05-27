# ndppd — IPv6 Neighbor Proxy

## Overview
`ndppd` proxies IPv6 Neighbor Discovery between WAN and LAN. Without it, the ISP sends Neighbor Solicitations for delegated /64 addresses onto the WAN link and gets silence — traffic drops, IPv6 breaks. ndppd intercepts those solicitations and answers on behalf of downstream hosts.

```bash
apt install ndppd      # or apk / pacman
systemctl enable ndppd
```
---
## The Config
`/etc/ndppd.conf` — substitute your WAN interface, LAN interface, and the /64 assigned to LAN :

```conf
route-ttl 30000
address-ttl 30000

proxy <wan_interface> {
    router yes
    timeout 500
    ttl 30000
    promiscuous yes

    rule <prefix>::<length_of_prefix> {
        iface <lan_interface>
    }
}
```

> The `rule` prefix is the /64 on the **LAN** interface, not the WAN. One `rule` block per LAN interface if there are multiple ,you may add `rule` blocks for each LAN interface over which traffic should be proxied.

```bash
systemctl restart ndppd
```

---

## Verification

```bash
# Service is running
systemctl is-active ndppd

# ISP has resolved at least one address (non-empty = working)
ip -6 neigh show dev <wan_interface>

# NDP traffic is flowing
tcpdump -i <wan_interface> -n icmp6
```

If the neighbor table is empty and no NDP traffic is visible, the `rule` prefix is wrong — re-check it against `ip -6 addr show dev <lan_interface>`.

---

## Debugging

Before restarting the service, dry-run the config directly. It will either error out immediately (bad config) or hang waiting for traffic (valid):

```bash
timeout 3 ndppd -d -c /etc/ndppd.conf
```

>Non-zero exit before the timeout = syntax error, fix it before restarting. Still running at timeout = config is clean, kill it and proceed.

---

## Common Errors  

| Symptom | Cause | Fix |
|---|---|---|
| Service fails to start | Config syntax error | `ndppd -d -c /etc/ndppd.conf` — error will print directly |
| NDP visible on WAN but no NA reply | Wrong prefix in `rule` | Prefix must match the LAN interface /64 exactly |
| Works but hosts unreachable | IPv6 forwarding off | Please check `99-ngfw.conf` for `net.ipv6.conf.all.forwarding`|
| Intermittent drops | Timeout too tight | Bump `timeout` from `500` to `1000` |
| Breaks after reboot | Service not enabled | `systemctl enable ndppd` or `systemctl enable --now ndppd` for an immediate launch |
| Stops working after ISP reconnect | Prefix re-delegated | Update `rule` prefix and `systemctl restart ndppd` |
