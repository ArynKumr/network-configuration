* * *

NGINX Stream Reverse Proxy (TCP / UDP) — Deployment & Firewall Policy
=====================================================================

Purpose
-------

This module enables **Layer-4 reverse proxying** (TCP/UDP) using NGINX **stream** mode.

Typical use cases:

*   exposing internal services behind a firewall
*   proxying non-HTTP protocols (VPNs, game servers, custom daemons)
*   decoupling public ISP IP from backend service IP
*   controlling access via nftables instead of application logic

* * *

Architecture Overview
---------------------

```
Remote Client
     |
     |  TCP/UDP
     v
[Firewall Public ISP IP : Port]
     |
     |  nftables (input)
     v
[NGINX Stream Listener]
     |
     |  TCP/UDP
     v
[Internal Backend Server]
```

Key points:

*   NGINX **terminates nothing** at L7
*   No TLS inspection
*   No HTTP headers
*   Pure socket forwarding

* * *

1\. Install Required NGINX Module
---------------------------------

```bash
apt install libnginx-mod-stream
```

This enables:

*   `stream {}` context
*   TCP/UDP proxying
*   L4 load-balancing and forwarding

* * *

2\. Create Stream Configuration Directory
-----------------------------------------

```bash
mkdir -p /etc/nginx/stream.d/
```

This directory will hold **per-port / per-protocol** configs.

* * *

3\. Enable Stream Context in `nginx.conf`
-----------------------------------------

Edit:

```bash
/etc/nginx/nginx.conf
```

Minimal required structure:

```nginx
user www-data;
worker_processes auto;
worker_cpu_affinity auto;
pid /run/nginx.pid;
error_log /var/log/nginx/error.log;

include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 768;
}

################ STREAM ENABLE ################
stream {
    include /etc/nginx/stream.d/*.conf;
}
################ STREAM ENABLE ################
```

⚠️ Without this block, **stream configs are ignored**.

* * *

4\. Define Stream Proxy Rules
-----------------------------

Each file defines **one listener**.

### Format
`/etc/nginx/stream.d/<protocol>_<firewall_public_isp_port>.conf`

```
server {
    listen <firewall_public_isp_ip>:<firewall_public_isp_port> <protocol>;
    proxy_pass <actual_internal_server_ip>:<actual_internal_server_port>;
}
```


### TCP Example

`/etc/nginx/stream.d/tcp_9000.conf`

```nginx
server {
    listen 10.1.1.98:9000 tcp;
    proxy_pass 10.1.1.106:8000;
}
```

### UDP Example

`/etc/nginx/stream.d/udp_9000.conf`

```nginx
server {
    listen 10.1.1.98:9000 udp;
    proxy_pass 10.1.1.106:8000;
}
```

### Important Notes

*   `listen IP` **must be the firewall’s public ISP IP**
*   Backend IP is **never exposed**
*   Same port can be used for TCP and UDP independently

* * *

5\. Reload NGINX
----------------

```bash
nginx -t
systemctl reload nginx
```

If this fails, **do not touch firewall rules yet**.

* * *

6\. Firewall Access Control (nftables)
--------------------------------------

NGINX listens on the **firewall itself**, so rules go in:

```
inet filter input
```

Below are **four canonical access control cases**.

* * *

Case 1 — Fully Locked (IP + Port + Protocol)
--------------------------------------------

**Most secure**

```bash
nft add rule inet filter input \
    ip saddr <source_remote_ip> \
    <protocol> sport <source_remote_port> \
    ip daddr <firewall_public_isp_ip> \
    <protocol> dport <firewall_public_isp_port> \
    accept
```

### Use when:

*   static remote peer
*   known client port
*   strict compliance

* * *

Case 2 — Public Service (Port Only)
-----------------------------------

```bash
nft add rule inet filter input \
    ip daddr <firewall_public_isp_ip> \
    <protocol> dport <firewall_public_isp_port> \
    accept
```

### Use when:

*   public-facing service
*   client IPs unknown
*   still protocol + port scoped

* * *

Case 3 — Port-Restricted Clients (Any IP)
-----------------------------------------

```bash
nft add rule inet filter input \
    <protocol> sport <source_remote_port> \
    ip daddr <firewall_public_isp_ip> \
    <protocol> dport <firewall_public_isp_port> \
    accept
```

### Use when:

*   client software uses fixed source port
*   IPs change (NAT, CGNAT)

⚠️ Less secure than Case 1.

* * *

Case 4 — IP-Restricted Clients (Any Source Port)
------------------------------------------------

```bash
nft add rule inet filter input \
    ip saddr <source_remote_ip> \
    ip daddr <firewall_public_isp_ip> \
    <protocol> dport <firewall_public_isp_port> \
    accept
```

### Use when:

*   trusted IP
*   dynamic client ports

* * *

Security Model Summary
----------------------

| Case | IP Scoped | Port Scoped | Security |
| --- | --- | --- | --- |
| 1 | ✅ | ✅ | Highest |
| 2 | ❌ | ✅ | Medium |
| 3 | ❌ | ⚠️ partial | Medium-Low |
| 4 | ✅ | ❌ | Medium |

* * *

Critical Design Rules (Do Not Break These)
------------------------------------------

1.  **No DNAT needed**
    *   NGINX terminates locally
2.  **Only INPUT chain matters**
3.  **Do not expose backend IP**
4.  **Do not mix NAT + stream proxy**
5.  **Firewall decides access, not NGINX**

* * *

Validation Checklist
--------------------

```bash
ss -lntup | grep 9000
nft list chain inet filter input
tcpdump -i <wan_iface> port 9000
```

Expected:

*   socket listening on public IP
*   packets accepted by input chain
*   backend sees proxied traffic only

* * *

One-Line Summary
----------------

> This module exposes internal TCP/UDP services via NGINX stream on a public ISP IP, with nftables enforcing all access control at the firewall input layer.

If you want next:

*   multi-backend load balancing
*   health checks
*   proxy timeouts tuning
*   nftables logging for stream traffic



---
Powered by [ChatGPT Exporter](https://www.chatgptexporter.com)