# Receive/Transmit Packet Steering (RPS / XPS / RFS) — Tuning Guide

> **Scope:** Linux kernel software packet steering on multi-core systems.  
> Applies to any NIC/DSA setup; examples use a 4-core system with one
> multi-queue uplink (`<uplink>`, 16 Tx queues) and several single-queue
> virtual/DSA switch ports (`<sw0>`, `<sw1>`, …).  
> **Replace every `<placeholder>` with your actual interface names before use.**

---

## Table of Contents

1. [Background — RSS, RPS, XPS, RFS](#background)
2. [Prerequisites & Inspection Commands](#prerequisites--inspection-commands)
3. [Applying the Tuning](#applying-the-tuning)
4. [Generalised Script](#generalised-script)
5. [Verification](#verification)
6. [Undo / Revert Script](#undo--revert-script)
7. [Persistence](#persistence)
8. [Tuning Notes & Caveats](#tuning-notes--caveats)
9. [References](#references)

---

## Background

### RSS — Receive Side Scaling (hardware)

RSS is the **hardware** baseline.  The NIC hashes each incoming flow
(src IP, dst IP, src port, dst port) and steers it to one of N hardware Rx
queues.  Each queue is bound to a separate CPU via an IRQ affinity setting.

```
NIC hardware
  └─ hash(flow) → Rx queue 0  → IRQ → CPU 0
                → Rx queue 1  → IRQ → CPU 1
                ...
```

RSS requires multi-queue NIC support.  **Single-queue NICs and DSA virtual
interfaces get no RSS benefit** — all interrupts land on one CPU.

### RPS — Receive Packet Steering (software RSS)

RPS is the **software emulation of RSS**.  It re-dispatches packets from the
interrupt CPU to a target CPU by hashing the flow tuple and consulting a CPU
bitmask (`rps_cpus`) stored per Rx queue.  This spreads softirq processing
across cores even on single-queue or virtual interfaces.

```
Rx interrupt → CPU N (processes minimal work)
                └─ hash(flow) → pick CPU from rps_cpus mask → process softirq
```

### RFS — Receive Flow Steering (auto-enabled with RPS)

**RFS is automatically activated when RPS is enabled and
`rps_sock_flow_entries > 0`.**  It extends RPS by steering packets to the CPU
where the _application socket_ is currently running, improving cache locality.

Two tables control this:

| Sysctl / sysfs | Purpose |
|---|---|
| `/proc/sys/net/core/rps_sock_flow_entries` | Global flow table size (power of 2) |
| `/sys/class/net/<iface>/queues/rx-N/rps_flow_cnt` | Per-queue flow entry budget |

Rule of thumb: `rps_sock_flow_entries` ≥ sum of all `rps_flow_cnt` values.
A value of `32768` (32 K) works well for home/SOHO routers.

### XPS — Transmit Packet Steering

XPS maps **Tx queues → CPUs** (the reverse of RPS).  When a CPU enqueues a
packet it preferentially uses the Tx queue assigned to it, keeping Tx cache-hot
and avoiding lock contention between cores.

On a multi-queue NIC with 16 Tx queues and 4 cores, assign 4 queues per core:

```
CPU 0 (mask 0x1) → tx-0  … tx-3
CPU 1 (mask 0x2) → tx-4  … tx-7
CPU 2 (mask 0x4) → tx-8  … tx-11
CPU 3 (mask 0x8) → tx-12 … tx-15
```

For single-queue virtual interfaces there is only `tx-0`; set its mask to **all
cores** (`0xf` for 4 cores) so any CPU can use it without steering overhead.

---

## Prerequisites & Inspection Commands

### Identify your interfaces

```bash
# List all network interfaces
ip link show

# Or via sysfs
ls /sys/class/net/
```

Categorise them:
- **Multi-queue uplink** — the physical NIC with multiple Tx queues (e.g. your
  WAN-side Ethernet port connected directly to the SoC).
- **Single-queue virtual/DSA ports** — VLAN subinterfaces, DSA switch ports,
  bridge members, etc.  Each has only `rx-0` / `tx-0`.

```bash
# Count Rx and Tx queue directories for any interface
ls /sys/class/net/<iface>/queues/
```

### Check number of CPUs (build the correct hex mask)

```bash
# Number of online CPUs
nproc

# All-CPUs hex mask: 2^nproc - 1
#   4 cores  → 0xf
#   8 cores  → 0xff
#   16 cores → 0xffff
python3 -c "print(hex((1 << $(nproc)) - 1))"
```

### Check current ring sizes and queue counts

```bash
# Hardware ring sizes — adjust with ethtool -G to absorb bursts
# (may show n/a on virtual/DSA interfaces)
ethtool -g <uplink>

# Number of Rx/Tx hardware queues the driver exposes
ethtool -l <uplink>

# Directly list queue directories in sysfs
ls /sys/class/net/<uplink>/queues/
ls /sys/class/net/<sw0>/queues/
```

### Snapshot current RPS / XPS defaults before touching anything

```bash
IFACE=<uplink>    # repeat for each interface as needed

# Current RPS CPU mask on Rx queue 0
cat /sys/class/net/$IFACE/queues/rx-0/rps_cpus

# Current per-queue RFS flow count
cat /sys/class/net/$IFACE/queues/rx-0/rps_flow_cnt

# Current global RFS socket flow table
cat /proc/sys/net/core/rps_sock_flow_entries

# Current XPS CPU mask on Tx queue 0
cat /sys/class/net/$IFACE/queues/tx-0/xps_cpus
```

> **Tip — save a full snapshot before tuning:**
> ```bash
> for iface in $(ls /sys/class/net/); do
>     for rxq in /sys/class/net/$iface/queues/rx-*/; do
>         printf '%s rps_cpus=%s rps_flow_cnt=%s\n' \
>             "$rxq" \
>             "$(cat ${rxq}rps_cpus 2>/dev/null)" \
>             "$(cat ${rxq}rps_flow_cnt 2>/dev/null)"
>     done
>     for txq in /sys/class/net/$iface/queues/tx-*/; do
>         printf '%s xps_cpus=%s\n' \
>             "$txq" "$(cat ${txq}xps_cpus 2>/dev/null)"
>     done
> done > defaults-$(date +%F).txt
> cat /proc/sys/net/core/rps_sock_flow_entries >> defaults-$(date +%F).txt
> ```

---

## Applying the Tuning

### Key sysfs values

| Value | Meaning |
|---|---|
| `f` (hex) | Bitmask `0b1111` — all 4 CPUs; adjust for your core count |
| `1`, `2`, `4`, `8` | Single-bit masks for CPU 0, 1, 2, 3 respectively |
| `32768` | 32 K flow table entries (power of 2, suits SOHO routers) |

---

## Generalised Script

Save as `/etc/network/rps-xps-apply.sh` and `chmod +x` it.

```bash
#!/bin/sh
# rps-xps-apply.sh — Enable RPS, RFS, and XPS
#
# ┌─────────────────────────────────────────────────────────────────────────┐
# │  CONFIGURE THESE VARIABLES FOR YOUR SYSTEM                             │
# │                                                                         │
# │  ALL_CPUS_MASK   hex bitmask covering all CPU cores (2^N - 1)          │
# │                  4 cores → f   8 cores → ff   16 cores → ffff          │
# │                                                                         │
# │  MULTIQUEUE_NIC  the uplink NIC that has multiple Tx queues            │
# │                  (find with: ls /sys/class/net/<iface>/queues/)         │
# │                                                                         │
# │  TX_QUEUES       total Tx queue count on MULTIQUEUE_NIC                │
# │                  (find with: ethtool -l <iface>)                       │
# │                                                                         │
# │  SINGLE_Q_IFACES space-separated list of single-queue interfaces       │
# │                  (DSA ports, VLAN subinterfaces, bridge members, etc.)  │
# │                                                                         │
# │  FLOW_CNT        per-queue RFS flow entry count                        │
# │  SOCK_FLOW       global RFS socket flow table (>= sum of FLOW_CNT)     │
# └─────────────────────────────────────────────────────────────────────────┘

ALL_CPUS_MASK="f"                      # adjust: ff for 8 cores, ffff for 16
MULTIQUEUE_NIC="<uplink>"             # e.g. eth0, enp3s0, end0
TX_QUEUES=16                          # e.g. output of: ethtool -l <uplink>
SINGLE_Q_IFACES="<sw0> <sw1> <sw2>"  # e.g. wan lan0 lan1 vlan10 vlan20
FLOW_CNT=32768
SOCK_FLOW=32768

# ── RPS on all interfaces (software RSS; works on single-queue too) ───────
for iface in $MULTIQUEUE_NIC $SINGLE_Q_IFACES; do
    for rxq in /sys/class/net/$iface/queues/rx-*/; do
        echo "$ALL_CPUS_MASK" > "${rxq}rps_cpus"
        echo "$FLOW_CNT"      > "${rxq}rps_flow_cnt"
    done
done

# ── Global RFS socket flow table ─────────────────────────────────────────
# Setting this > 0 while rps_cpus is non-zero automatically activates RFS.
echo "$SOCK_FLOW" > /proc/sys/net/core/rps_sock_flow_entries

# ── XPS on multi-queue NIC: one CPU per queue group ──────────────────────
#    Queues are split evenly across CPUs.
#    CPU mask for CPU N = (1 << N), written as hex.
#
#    Example — 16 Tx queues / 4 CPUs (4 queues per CPU):
#      q  0- 3  → CPU 0  mask = 0x1
#      q  4- 7  → CPU 1  mask = 0x2
#      q  8-11  → CPU 2  mask = 0x4
#      q 12-15  → CPU 3  mask = 0x8
#
NCPUS=$(nproc)
QPU=$(( TX_QUEUES / NCPUS ))   # queues per CPU
for cpu in $(seq 0 $(( NCPUS - 1 )) ); do
    mask=$(( 1 << cpu ))
    start=$(( cpu * QPU ))
    end=$(( start + QPU - 1 ))
    for q in $(seq $start $end); do
        printf '%x\n' $mask \
            > /sys/class/net/$MULTIQUEUE_NIC/queues/tx-$q/xps_cpus
    done
done

# ── XPS on single-queue interfaces: all CPUs on tx-0 ─────────────────────
# With only one queue any CPU may use it; spread the mask to avoid contention.
for iface in $SINGLE_Q_IFACES; do
    echo "$ALL_CPUS_MASK" > /sys/class/net/$iface/queues/tx-0/xps_cpus
done

echo "RPS / XPS / RFS applied successfully."
```

---

## Verification

After running the script, confirm the values landed:

```bash
# RPS mask on every Rx queue of the uplink
for rxq in /sys/class/net/<uplink>/queues/rx-*/; do
    echo "$rxq → $(cat ${rxq}rps_cpus)"
done

# XPS mask on every Tx queue of the uplink
for txq in /sys/class/net/<uplink>/queues/tx-*/; do
    echo "$txq → $(cat ${txq}xps_cpus)"
done

# RPS / XPS on a single-queue interface
cat /sys/class/net/<sw0>/queues/rx-0/rps_cpus
cat /sys/class/net/<sw0>/queues/tx-0/xps_cpus

# Global RFS flow table
cat /proc/sys/net/core/rps_sock_flow_entries

# Live softirq distribution — watch for spread across all CPUs
watch -n1 cat /proc/net/softnet_stat

# Per-CPU RFS hits
# Column 10 = rps_needed (packets steered by RPS/RFS)
# Column 11 = rps_throttled (should be low)
awk '{print "CPU" NR-1, "rps_needed=" $10, "throttled=" $11}' \
    /proc/net/softnet_stat
```

---

## Undo / Revert Script

> **Note:** Keep this as a separate `rps-xps-undo.sh`.  Run it to return to
> kernel defaults for benchmarking, bisecting a regression, or before
> unloading a driver.

Kernel defaults:

| knob | default |
|---|---|
| `rps_cpus` | `00` (disabled) |
| `rps_flow_cnt` | `0` |
| `xps_cpus` | `00` (disabled / auto) |
| `rps_sock_flow_entries` | `0` |

```bash
#!/bin/sh
# rps-xps-undo.sh — Revert RPS / XPS / RFS to kernel defaults
#
# Mirror the variables from rps-xps-apply.sh:
MULTIQUEUE_NIC="<uplink>"
SINGLE_Q_IFACES="<sw0> <sw1> <sw2>"

echo "Reverting RPS / XPS / RFS to kernel defaults..."

# ── Disable RPS and per-queue RFS ─────────────────────────────────────────
for iface in $MULTIQUEUE_NIC $SINGLE_Q_IFACES; do
    for rxq in /sys/class/net/$iface/queues/rx-*/; do
        echo 0 > "${rxq}rps_cpus"     2>/dev/null || true
        echo 0 > "${rxq}rps_flow_cnt" 2>/dev/null || true
    done
done

# ── Disable global RFS ────────────────────────────────────────────────────
echo 0 > /proc/sys/net/core/rps_sock_flow_entries

# ── Disable XPS on multi-queue NIC ───────────────────────────────────────
for txq in /sys/class/net/$MULTIQUEUE_NIC/queues/tx-*/; do
    echo 0 > "${txq}xps_cpus" 2>/dev/null || true
done

# ── Disable XPS on single-queue interfaces ───────────────────────────────
for iface in $SINGLE_Q_IFACES; do
    echo 0 > /sys/class/net/$iface/queues/tx-0/xps_cpus 2>/dev/null || true
done

echo "Done. All steering disabled."
```

---

## Persistence

These sysfs writes are **not persistent** across reboots.  Options:

### Option A — rc.local / init script

```bash
echo '/etc/network/rps-xps-apply.sh' >> /etc/rc.local
```

### Option B — systemd service

```ini
# /etc/systemd/system/rps-xps.service
[Unit]
Description=Apply RPS/XPS/RFS packet steering
After=network.target

[Service]
Type=oneshot
ExecStart=/etc/network/rps-xps-apply.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

```bash
systemctl enable --now rps-xps.service
```
---

## Tuning Notes & Caveats

| Topic | Detail |
|---|---|
| **RSS vs RPS** | If your uplink NIC supports RSS natively (multi-queue + IRQ affinity already spread), RPS on that NIC adds little. RPS shines on single-queue and virtual (DSA, VLAN, bridge) interfaces where RSS cannot help. |
| **RFS auto-activation** | Setting `rps_cpus` to a non-zero mask **and** `rps_sock_flow_entries > 0` is sufficient — no separate toggle exists for RFS. |
| **CPU mask width** | The mask must cover the highest CPU number on the system. 4-core → 4-bit mask (`0`–`f`); 8-core → 8-bit (`0`–`ff`); 16-core → `0`–`ffff`. |
| **NUMA systems** | On NUMA machines, prefer masks that confine RPS to the NUMA node where the NIC's IRQ is handled, to avoid cross-node memory traffic. |
| **Flow count sizing** | `rps_flow_cnt` × (number of Rx queues across all interfaces) should not exceed `rps_sock_flow_entries`, or RFS entries will be evicted under load. |
| **XPS on single-queue** | Setting `xps_cpus` to all-CPUs on a single `tx-0` is effectively a no-op for steering but harmless; it sets the preferred-queue hint uniformly. |
| **Ring sizes first** | Ring size (`ethtool -g`) is separate from queue count (`ethtool -l`). Increase ring depth (`ethtool -G`) to absorb bursts *before* tuning CPU steering. |
| **Monitoring** | In `/proc/net/softnet_stat`: column 2 = dropped, column 3 = time-squeezed (both indicate CPU saturation); columns 10–11 show RPS/RFS activity per CPU. |

---

## References

### Linux Kernel Documentation

| Document | URL |
|---|---|
| Scaling in the Linux Networking Stack (canonical RPS/RFS/XPS reference) | https://www.kernel.org/doc/html/latest/networking/scaling.html |
| `sysctl` networking parameters | https://www.kernel.org/doc/html/latest/networking/ip-sysctl.html |
| DSA — Distributed Switch Architecture | https://www.kernel.org/doc/html/latest/networking/dsa/dsa.html |

### Kernel Source

| File | Relevance |
|---|---|
| `net/core/dev.c` | RPS / RFS flow table implementation (`get_rps_cpu()`, `rps_may_expire_flow()`) |
| `net/core/net-sysfs.c` | sysfs knobs: `rps_cpus`, `rps_flow_cnt`, `xps_cpus` |
| `include/linux/netdevice.h` | `struct softnet_data`, `struct rps_dev_flow_table` definitions |

### Commit History (key introductions)

| Kernel version | Change |
|---|---|
| 2.6.35 | RPS introduced — `net: Receive Packet Steering` (Tom Herbert) |
| 2.6.35 | RFS introduced alongside RPS — `net: Receive Flow Steering` (Tom Herbert) |
| 2.6.38 | XPS introduced — `net: Transmit Packet Steering` (Tom Herbert) |

> Browse individual commits at https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git

### Man Pages & Runtime Files

| Reference | Notes |
|---|---|
| `man 8 ethtool` | `-g` (get ring), `-G` (set ring), `-l` (get channels), `-L` (set channels), `-x` (show RSS hash indirection table) |
| `/proc/net/softnet_stat` | Per-CPU softirq stats; columns: total, dropped, time-squeezed, …, rps_needed, rps_throttled |
| `/proc/sys/net/core/rps_sock_flow_entries` | Global RFS socket flow table size |
| `/sys/class/net/<iface>/queues/rx-N/rps_cpus` | RPS CPU bitmask for Rx queue N |
| `/sys/class/net/<iface>/queues/rx-N/rps_flow_cnt` | Per-queue RFS flow entry budget |
| `/sys/class/net/<iface>/queues/tx-N/xps_cpus` | XPS CPU bitmask for Tx queue N |
| `/sys/class/net/<iface>/queues/tx-N/xps_rxqs` | XPS Rx-queue-to-Tx-queue mapping (kernel ≥ 4.18) |

### Further Reading

| Resource | URL |
|---|---|
| "Monitoring and Tuning the Linux Networking Stack: Receiving Data" — Packagecloud blog (detailed walk-through of the entire Rx path) | https://blog.packagecloud.io/monitoring-tuning-linux-networking-stack-receiving-data/ |
| "Monitoring and Tuning the Linux Networking Stack: Sending Data" — Packagecloud blog | https://blog.packagecloud.io/monitoring-tuning-linux-networking-stack-sending-data/ |
| Red Hat Performance Tuning Guide — Network chapter | https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/monitoring_and_managing_system_status_and_performance/tuning-the-network-performance_monitoring-and-managing-system-status-and-performance |
| Cloudflare blog: "How to receive a million packets per second" | https://blog.cloudflare.com/how-to-receive-a-million-packets/ |
