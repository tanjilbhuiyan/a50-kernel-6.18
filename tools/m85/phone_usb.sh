#!/bin/sh
# M8.5 USB observer: H1 source with 900 s timer; calibrated private trace through 860 s. Detached observer; /run, private tracefs instance and diagnostic kmsg writes.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
D=/run/a50-m85-s1
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
k() { printf '<6>A50M85USB: %s\n' "$*" > /dev/kmsg; }
# Restrict tracing to device-level DWC3 events and explicit UDC state/control calls.
# No endpoint traffic, USB data payloads, global tracing changes or rootfs writes.
T=/sys/kernel/tracing/instances/a50_m85_s1
trace_begin() {
    [ -d /sys/kernel/tracing/events ] || mount -t tracefs tracefs /sys/kernel/tracing || return 1
    mkdir "$T" || return 1
    echo 0 > "$T/tracing_on" || return 1
    echo 64 > "$T/buffer_size_kb" || return 1
    if grep -qw boot "$T/trace_clock"; then echo boot > "$T/trace_clock" || return 1; fi
    echo 'event & 1' > "$T/events/dwc3/dwc3_event/filter" || return 1
    cat "$T/events/dwc3/dwc3_event/filter" || return 1
    for event in dwc3/dwc3_event gadget/usb_gadget_set_state gadget/usb_gadget_connect \
        gadget/usb_gadget_disconnect gadget/usb_gadget_activate gadget/usb_gadget_deactivate \
        gadget/usb_gadget_vbus_connect gadget/usb_gadget_vbus_disconnect; do
        echo 1 > "$T/events/$event/enable" || return 1
        enabled=$(cat "$T/events/$event/enable") || return 1
        [ "$enabled" = 1 ] || return 1
        echo "enabled $event readback=$enabled"
    done
    cat "$T/trace_clock"; cat /proc/uptime
    echo 1 > "$T/tracing_on" || return 1
    [ "$(cat "$T/tracing_on")" = 1 ] || return 1
    echo "A50M85USB_START uptime=$(cut -d' ' -f1 /proc/uptime)" > "$T/trace_marker" || return 1
    grep A50M85USB_START "$T/trace" || return 1
    echo 'private trace marker read-back passed'
}
if trace_begin > "$D/trace-setup.txt" 2>&1; then
    trace_ready=1
    k 'USB trace enabled in private a50_m85_s1 instance'
else
    trace_ready=0
    [ ! -e "$T/tracing_on" ] || echo 0 > "$T/tracing_on"
    k 'USB trace setup FAILED; run is diagnostic-incomplete; preserving normal observer/restore'
fi
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
    [ "${up%%.*}" -lt 860 ] || break
    state=$(cat /sys/class/udc/*/state 2>/dev/null | tr '\n' ',')
    printf 'T %s udc=%s\n' "$up" "$state" >> "$D/udc.txt"
    sleep 1
done
wait "$window_pid"
if [ "$trace_ready" -eq 1 ]; then
    {
        printf 'tracing_on='; cat "$T/tracing_on"
        for event in dwc3/dwc3_event gadget/usb_gadget_set_state gadget/usb_gadget_connect \
            gadget/usb_gadget_disconnect gadget/usb_gadget_activate gadget/usb_gadget_deactivate \
            gadget/usb_gadget_vbus_connect gadget/usb_gadget_vbus_disconnect; do
            printf '%s enable=' "$event"; cat "$T/events/$event/enable"
        done
        cat "$T/events/dwc3/dwc3_event/filter"
        echo "A50M85USB_END uptime=$(cut -d' ' -f1 /proc/uptime)" > "$T/trace_marker"
        echo "end_marker_write=$?"
    } > "$D/trace-final.txt" 2>&1
    echo 0 > "$T/tracing_on"
    cat "$T/trace" > "$D/usb-trace.txt"
    for f in "$T"/per_cpu/cpu*/stats; do echo "$f"; cat "$f"; done > "$D/trace-stats.txt"
    echo 0 > "$T/events/enable"
fi
dmesg > "$D/dmesg860.txt" 2>&1
journalctl -b --no-pager -o short-monotonic -u systemd-logind | tail -n 16 > "$D/logind.txt" 2>&1
journalctl -b --no-pager -o short-monotonic -u usb-moded -u usb-tethering | tail -n 30 > "$D/usbmoded.txt" 2>&1
awk -F'[][]' '$2+0>=40 && $2+0<=860' "$D/dmesg860.txt" |
    grep -i -E 'usb|gadget|dwc|udc|rndis|PM:|suspend|wakeup|freez|phy|vbus|otg|disconnect' |
    grep -v -E 'usb_moded|init: |A50STATUS:|A50M85USB:' | tail -n 60 > "$D/dmesg-usb.txt"
wait_up 885
k "observer complete samples=$(wc -l < "$D/udc.txt")"
# Retain every observed transition plus periodic anchors in the timed dump.
awk 'NR==1 || $3!=prev || NR%15==0 {print} {prev=$3;last=$0} END {print "last "last}' "$D/udc.txt" > "$D/udc-summary.txt"
for item in udc-summary window logind usbmoded dmesg-usb; do
    while IFS= read -r line; do k "$item $line"; done < "$D/$item.txt"
done
trace_lines=0
[ ! -f "$D/usb-trace.txt" ] || trace_lines=$(wc -l < "$D/usb-trace.txt")
k "trace ready=$trace_ready lines=$trace_lines"
if [ "$trace_ready" -eq 1 ]; then
    while IFS= read -r line; do k "usbtrace $line"; done <<EOF
$(grep -v '^#' "$D/usb-trace.txt" | tail -n 120)
EOF
    while IFS= read -r line; do k "trace_setup $line"; done < "$D/trace-setup.txt"
fi
k 'observer end'
