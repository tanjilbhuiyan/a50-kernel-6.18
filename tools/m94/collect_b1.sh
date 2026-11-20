#!/bin/sh
# M9.4 B1 (phone side, root over USB SSH): SCSC Bluetooth as a native BlueZ hci_dev (ADR-0008). Records probe state;
# at >= 90 s unblocks Bluetooth rfkill (as the Settings toggle), expects hci0, records btmgmt info and a 15 s scan
# (device COUNT only), then block/unblock once more. Addresses and device names are redacted / not printed.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 40 "$@" 2>&1 | sed -E 's/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/<mac>/g'; printf 'RC=%s\n' "$?"; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
btlog() { dmesg | grep -i -E 'scsc_bt|BT_|bluez|bluetooth|hci0|h4|bsmhcp|bhcs|MXMAN|wlbt: \[|Unable to handle|SError|Internal error|BUG:' | grep -v -i -E 'bluebinder|wlbtd|mali' | sed -E 's/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/<mac>/g' | tail -n "${1:-120}"; }
hcis() { printf 'hci: %s\n' "$(ls /sys/class/bluetooth 2>/dev/null | paste -sd' ')"; }
capture uname -r
capture cat /proc/uptime
capture rfkill list
capture sh -c 'ls -l /dev | grep -E "scsc|vhci|uhid"; ls /sys/bus/platform/devices | grep -i -E "bluez|scsc"'
hcis
capture systemctl show bluetooth.service bluebinder.service -p Id -p ActiveState -p SubState -p NRestarts
printf '\nM94_B1_PROBE_LOG\n'; btlog 80
wait_up 90
printf '\nM94_B1_UNBLOCK uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
capture rfkill unblock bluetooth
i=0; while [ $i -lt 20 ]; do [ -e /sys/class/bluetooth/hci0 ] && break; sleep 1; i=$((i + 1)); done
printf 'hci0_after_s=%s\n' "$i"; hcis
sleep 3
capture rfkill list bluetooth
capture btmgmt info
capture sh -c 'bluetoothctl power on'
sleep 3
capture btmgmt info
printf '\nM94_B1_SCAN uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
capture sh -c 'bluetoothctl --timeout 15 scan on >/dev/null 2>&1; bluetoothctl devices | wc -l'
printf '\nM94_B1_UNBLOCK_LOG\n'; btlog 150
printf '\nM94_B1_BLOCK uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
capture rfkill block bluetooth
sleep 5; hcis
capture rfkill unblock bluetooth
i=0; while [ $i -lt 20 ]; do [ -e /sys/class/bluetooth/hci0 ] && break; sleep 1; i=$((i + 1)); done
printf 'hci0_again_after_s=%s\n' "$i"; hcis
sleep 3; capture btmgmt info
printf '\nM94_B1_FINAL uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
capture sh -c 'grep -E "wlbt|scsc" /proc/interrupts | tr -s " "; cat /proc/sys/kernel/tainted'
capture systemctl show bluetooth.service bluebinder.service -p Id -p ActiveState -p SubState -p NRestarts
printf 'faults=%s\n' "$(dmesg | grep -c -E 'Unable to handle|SError|Internal error|BUG:|Kernel panic')"
printf '\nM94_B1_FINAL_LOG\n'; btlog 80
