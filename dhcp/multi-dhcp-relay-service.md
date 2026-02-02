---

# DHCP Relay systemd Template Unit (`isc-dhcp-relay@.service`)

This setup uses a **templated systemd unit** to allow running **multiple independent DHCP relay instances**, each with its own configuration and interface set.

---

## Service Unit Definition

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

---

## How this unit works

* `%I` is the **instance name** (for example: `lan`, `vlan10`, `br0`)
* Each instance:

  * Reads its own environment file
  * Writes its own PID file
  * Runs an independent `dhcrelay` process

This allows **multiple relay agents** on the same system without conflicts.

---

## Instance Configuration Files

Each relay instance **must** have its own config file:

```
/etc/default/isc-dhcp-relay-<instance>
```

Example:

```
/etc/default/isc-dhcp-relay-br0
```

### Example instance configuration

```bash
SERVERS="10.50.50.1"
OPTIONS="-4 -D -id br0 -iu eth0"
INTF_CMD=""
```

Enable the instance:

```bash
systemctl enable --now isc-dhcp-relay@br0
```

---

## ⚠️ Critical Note: Base config file must be empty

### **The base file**

```
/etc/default/isc-dhcp-relay
```

**MUST exist but MUST be empty.**

### Why this matters

* `isc-dhcp-relay` packages expect `/etc/default/isc-dhcp-relay` to exist
* If it contains variables (`SERVERS`, `OPTIONS`, etc):

  * systemd will **merge them implicitly**
  * instance-specific values may be overridden or duplicated
  * relay processes may start with **unexpected arguments**

systemd does **not** warn you when this happens.
It just quietly does the wrong thing.

### Correct state

```bash
# File exists
ls -l /etc/default/isc-dhcp-relay

# But contains nothing
cat /etc/default/isc-dhcp-relay
```

Zero output is the desired output.

---

## Why templated units are used instead of a single relay

Using `isc-dhcp-relay@.service` allows:

* Multiple relays on different interfaces
* Clear separation of VLANs / bridges
* Independent restart and logging
* Predictable `giaddr` behavior
* Easier debugging in complex L3 topologies

This is **not optional** once you move past a single flat network.

---

## Sanity check

List running relay instances:

```bash
systemctl status 'isc-dhcp-relay@*'
```

Verify processes:

```bash
ps -ef | grep dhcrelay
```

Each instance should:

* Have its own PID
* Use only its intended interfaces
* Forward only to its intended server

---

## One sentence that saves hours

> The base `/etc/default/isc-dhcp-relay` file must be empty so that only instance-specific environment files control relay behavior.

Put that sentence in bold in your guide. Someone will ignore it anyway, but at least you tried.

If you want, next we can:

* tie this cleanly into your bridge-based LAN
* document relay + Kea subnet matching end-to-end
* or add failure-mode diagrams so people stop guessing

You’re building this correctly. It’s just systemd doing systemd things.
