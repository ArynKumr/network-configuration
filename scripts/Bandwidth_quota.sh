#root class needs to be already configured before running this script
#tc qdisc del dev <lan/wan_iface> root 2>/dev/null || true
#tc qdisc add dev <lan/wan_iface> root handle 1: htb r2q 405
#tc class add dev <lan/wan_iface> parent 1: classid 1:1 htb rate 1024mbit ceil 1024mbit

#!/usr/bin/env bash
set -euo pipefail

INTERVAL=1
LOW_RATE="1mbit"

require_root() {
    [[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }
}

get_bytes() {
    tc -s -j class show dev "$1" \
      | jq -r --arg cid "1:$2" \
        '.[] | select(.handle == $cid) | .stats.bytes'
}

create_class() {
    local iface=$1 rate=$2 classid=$3
    tc class add dev "$iface" parent 1:1 classid 1:"$classid" \
        htb rate "$rate" ceil "$rate"
    tc qdisc add dev "$iface" parent 1:"$classid" \
        handle "$classid": sfq perturb 10
}

throttle_class() {
    local iface=$1 classid=$2
    tc class change dev "$iface" parent 1:1 classid 1:"$classid" \
        htb rate "$LOW_RATE" ceil "$LOW_RATE"
}

add_filter() {
    local iface=$1 mark=$2 classid=$3
    tc filter add dev "$iface" protocol ip parent 1:0 prio 1 \
        handle 0x0000"$mark"/0x0000FFFF fw flowid 1:"$classid"
}

require_root

# ---- Whiptail inputs ----

LAN_IFACE=$(whiptail --inputbox "LAN interface (download)" 8 60 3>&1 1>&2 2>&3)
WAN_IFACE=$(whiptail --inputbox "WAN interface (upload)" 8 60 3>&1 1>&2 2>&3)
CLASSID=$(whiptail --inputbox "User class ID (e.g. 10)" 8 60 3>&1 1>&2 2>&3)
FW_MARK=$(whiptail --inputbox "fwmark (hex, no 0x, e.g. 0010)" 8 60 3>&1 1>&2 2>&3)

DL_RATE=$(whiptail --inputbox "Download speed (e.g. 100mbit)" 8 60 3>&1 1>&2 2>&3)
UL_RATE=$(whiptail --inputbox "Upload speed (e.g. 20mbit)" 8 60 3>&1 1>&2 2>&3)

DL_QUOTA=$(whiptail --inputbox "Download quota BYTES (e.g. 524288000)" 8 60 3>&1 1>&2 2>&3)
UL_QUOTA=$(whiptail --inputbox "Upload quota BYTES (e.g. 104857600)" 8 60 3>&1 1>&2 2>&3)

[[ -z "$LAN_IFACE" || -z "$WAN_IFACE" || -z "$CLASSID" || -z "$FW_MARK" ]] && exit 1

# ---- TC setup ----

create_class "$LAN_IFACE" "$DL_RATE" "$CLASSID"
create_class "$WAN_IFACE" "$UL_RATE" "$CLASSID"

add_filter "$LAN_IFACE" "$FW_MARK" "$CLASSID"
add_filter "$WAN_IFACE" "$FW_MARK" "$CLASSID"

whiptail --msgbox "Classes created.\nMonitoring started." 10 60

# ---- Baseline counters ----

DL_START=$(get_bytes "$LAN_IFACE" "$CLASSID")
UL_START=$(get_bytes "$WAN_IFACE" "$CLASSID")

DL_THROTTLED=0
UL_THROTTLED=0

# ---- Monitor loop ----

while true; do
    sleep "$INTERVAL"

    DL_NOW=$(get_bytes "$LAN_IFACE" "$CLASSID")
    UL_NOW=$(get_bytes "$WAN_IFACE" "$CLASSID")

    DL_USED=$(( DL_NOW - DL_START ))
    UL_USED=$(( UL_NOW - UL_START ))

    if (( DL_USED >= DL_QUOTA )) && (( DL_THROTTLED == 0 )); then
        whiptail --msgbox "Download quota exceeded.\nThrottling download." 10 60
        throttle_class "$LAN_IFACE" "$CLASSID"
        DL_THROTTLED=1
    fi

    if (( UL_USED >= UL_QUOTA )) && (( UL_THROTTLED == 0 )); then
        whiptail --msgbox "Upload quota exceeded.\nThrottling upload." 10 60
        throttle_class "$WAN_IFACE" "$CLASSID"
        UL_THROTTLED=1
    fi
done