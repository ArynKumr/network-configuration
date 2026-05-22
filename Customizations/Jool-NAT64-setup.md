# Configuring Jool NAT64

## Example Configuration

File:

```text
/etc/jool/jool.conf
```

Configuration:

```json
{
    "instance": "default",
    "framework": "netfilter",
    "global": {
        "pool6": "64:ff9b::/96"
    }
}
```

---

# What Jool Does

Jool is a NAT64 translator.

It allows:

* IPv6-only clients
* To communicate with IPv4-only servers

It works together with:

* DNS64 resolver (such as Unbound)
* IPv6 routing
* Linux netfilter framework

---

# NAT64 Workflow

Example flow:

```text
IPv6 Client
    ↓
DNS64 Resolver
    ↓
Synthesized AAAA Record
    ↓
Jool NAT64 Translator
    ↓
IPv4 Internet
```

DNS64 creates fake IPv6 addresses.

Jool translates:

```text
IPv6 ↔ IPv4
```

Without Jool:

* DNS resolution works
* Connections fail

---

# Configuration Breakdown

## instance

```json
"instance": "default"
```

Defines the Jool instance name.

---

## framework

```json
"framework": "netfilter"
```

Tells Jool to integrate with Linux Netfilter.

This is the most common mode.

Alternative modes:

| Framework | Purpose               |
| --------- | --------------------- |
| netfilter | Stateful NAT64        |
| iptables  | Legacy integration    |
| SIIT      | Stateless translation |

Netfilter mode supports:

* Stateful NAT64
* Connection tracking
* Production deployments

---

# Global Section

## pool6

```json
"pool6": "64:ff9b::/96"
```

Defines the NAT64 translation prefix.

This MUST match:

* DNS64 prefix in Unbound
* Network routing
* Client DNS responses

Example synthesized address:

```text
64:ff9b::0808:0808
```

Embedded IPv4:

```text
8.8.8.8
```

---

# Extremely Important Rule

The NAT64 prefix MUST be identical everywhere.

Example:

| Component     | Prefix       |
| ------------- | ------------ |
| Unbound DNS64 | 64:ff9b::/96 |
| Jool pool6    | 64:ff9b::/96 |
| Routing       | 64:ff9b::/96 |
---

# Start Jool

Load the module:

```bash
modprobe jool
```

Start the service:

```bash
systemctl restart jool
```

Enable at boot:

```bash
systemctl enable jool
```

Check status:

```bash
systemctl status jool
```

---

# Verify Jool Instance

Show configured instances:

```bash
jool instance display
```

Expected:

```text
Instance "default"
```

---

# Verify NAT64 Prefix

```bash
jool global display
```

Expected:

```text
pool6: 64:ff9b::/96
```

---

# Example Network Topology

```text
IPv6 Client
    │
    │ IPv6
    ▼
+----------------+
| Router          |
|----------------|
| Unbound DNS64  |
| Jool NAT64     |
+----------------+
    │
    │ IPv4
    ▼
IPv4 Internet
```

---

# Useful Commands

## Show instances

```bash
jool instance display
```

## Show sessions

```bash
jool session display
```

## Show statistics

```bash
jool stats display
```

## Show global config

```bash
jool global display
```

---

# Minimal Working Configuration

```json
{
    "instance": "default",
    "framework": "netfilter",
    "global": {
        "pool6": "64:ff9b::/96"
    }
}
```

---

# Production Recommendations

For serious deployments:

* Use persistent firewall rules
* Monitor conntrack usage
* Tune MTU handling
* Monitor session counts
* Use logging carefully
* Avoid overloading small routers
* Test fragmentation behavior

---

# Documentation Prefixes Used

| Prefix        | Purpose                 |
| ------------- | ----------------------- |
| 2001:db8::/32 | Documentation only      |
| 64:ff9b::/96  | Well-known NAT64 prefix |
