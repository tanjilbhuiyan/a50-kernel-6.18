#!/bin/sh
# P3 control: no keys expected. Detached observer; only /run files and diagnostic kmsg writes.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
D=/run/a50-k6
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
k() { printf '<6>A50K6: %s\n' "$*" > /dev/kmsg; }
# Keep the K4 50-70 s job/state samples and 75 s log snapshot for comparison,
# but observe UDC throughout the remaining boot, even after USB SSH disconnects.
(
    wait_up 50
    t=50
    while [ "$t" -le 70 ]; do
        wait_up "$t"
        printf 'T %s udc=%s jobs=%s state=%s\n' "$(cut -d' ' -f1 /proc/uptime)" \
            "$(cat /sys/class/udc/*/state 2>/dev/null)" \
            "$(systemctl list-jobs --no-legend --no-pager 2>/dev/null | awk '{print $2"/"$3}' | tr '\n' ',' | cut -c1-200)" \
            "$(systemctl is-system-running 2>/dev/null)"
        t=$((t + 1))
    done > "$D/window.txt"
    wait_up 75
    dmesg > "$D/dmesg75.txt" 2>&1
) &
window_pid=$!
: > "$D/udc.txt"
while read -r up rest < /proc/uptime; do
    [ "${up%%.*}" -lt 390 ] || break
    state=$(cat /sys/class/udc/*/state 2>/dev/null | tr '\n' ',')
    printf 'T %s udc=%s\n' "$up" "$state" >> "$D/udc.txt"
    sleep 1
done
wait "$window_pid"
dmesg > "$D/dmesg390.txt" 2>&1
journalctl -b --no-pager -o short-monotonic -u systemd-logind | tail -n 16 > "$D/logind.txt" 2>&1
journalctl -b --no-pager -o short-monotonic -u usb-moded -u usb-tethering | tail -n 30 > "$D/usbmoded.txt" 2>&1
awk -F'[][]' '$2+0>=40 && $2+0<=390' "$D/dmesg390.txt" |
    grep -i -E 'usb|gadget|dwc|udc|rndis|PM:|suspend|wakeup|freez|phy|vbus|otg|disconnect' |
    grep -v -E 'usb_moded|init: |A50STATUS:|A50K6:' | tail -n 60 > "$D/dmesg-usb.txt"
wait_up 395
k "observer complete samples=$(wc -l < "$D/udc.txt")"
# Retain every observed transition plus periodic anchors in the timed dump.
awk 'NR==1 || $3!=prev || NR%15==0 {print} {prev=$3;last=$0} END {print "last "last}' "$D/udc.txt" > "$D/udc-summary.txt"
for item in udc-summary window logind usbmoded dmesg-usb; do
    while IFS= read -r line; do k "$item $line"; done < "$D/$item.txt"
done
k 'observer end'
