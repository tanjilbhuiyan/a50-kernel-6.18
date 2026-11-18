#!/bin/sh
# M8.3 K4 phone-side diagnostics (K3 + kernel log around the ~60 s USB drop) (runs detached; survives a USB-networking drop). Writes its findings to /dev/kmsg at
# ~395 s so the 420 s timed dump keeps them. Read-only except its own files in /run/a50-k1.
D=/run/a50-k1
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
k() { echo "<6>A50K4: $*" > /dev/kmsg; }
wait_up 40
timeout 310 $D/evcap "gpio-keys" 300 > $D/keys.txt 2>&1 &
wait_up 50
: > $D/window.txt
t=50
while [ "$t" -le 70 ]; do
    wait_up "$t"
    {
        printf 'T %s udc=%s jobs=%s state=%s\n' "$(cut -d' ' -f1 /proc/uptime)" "$(cat /sys/class/udc/*/state 2>/dev/null)" \
            "$(systemctl list-jobs --no-legend --no-pager 2>/dev/null | awk '{print $2"/"$3}' | tr '\n' ',' | cut -c1-200)" \
            "$(systemctl is-system-running 2>/dev/null)"
    } >> $D/window.txt
    t=$((t + 1))
done
wait_up 75
dmesg > $D/dmesg75.txt 2>&1
journalctl -b --no-pager -o short-monotonic -u systemd-logind 2>/dev/null | tail -n 12 > $D/logind.txt
journalctl -b --no-pager -o short-monotonic -u usb-moded 2>/dev/null | tail -n 8 > $D/usbmoded.txt
wait_up 395
k "keys $(grep 'type 1 code' $D/keys.txt | awk '{print $1":"$5"="$7}' | tr '\n' ' ' | cut -c1-900)"
k "keysummary $(grep summary $D/keys.txt)"
while read -r l; do k "win $l"; done < $D/window.txt
while read -r l; do k "logind $(echo "$l" | cut -c1-200)"; done < $D/logind.txt
while read -r l; do k "usbmoded $(echo "$l" | cut -c1-200)"; done < $D/usbmoded.txt
awk -F'[][]' '$2+0>=50 && $2+0<=75' $D/dmesg75.txt | grep -i -E 'usb|gadget|dwc|udc|rndis|PM:|suspend|wakeup|wake|freez|gpio-keys|keys|phy|vbus|otg|reset|disconnect' | grep -v -E 'usb_moded|init: ' | head -n 60 > $D/dmesg-usb.txt
k "dmesg50-75 lines=$(awk -F'[][]' '$2+0>=50 && $2+0<=75' $D/dmesg75.txt | wc -l) matched=$(wc -l < $D/dmesg-usb.txt)"
while read -r l; do k "dm $(echo "$l" | cut -c1-200)"; done < $D/dmesg-usb.txt
