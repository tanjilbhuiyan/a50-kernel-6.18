#!/bin/sh
# Read-only P3 USB control. Observer is already detached before collection starts.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 15 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
capture uname -r
capture cat /proc/uptime
capture sh -c 'cat /proc/bus/input/devices | grep -E "^N:|^H:"'
capture sh -c 'cat /sys/class/udc/*/state; ls /sys/kernel/config/usb_gadget/*/configs/*/; systemctl show usb-moded -p ActiveState -p SubState'
capture sh -c 'journalctl -b --no-pager -o short-monotonic -u usb-moded | tail -n 20'
while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge 150 ] && break; sleep 2; done
capture cat /run/a50-k8/window.txt
