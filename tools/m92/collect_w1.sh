#!/bin/sh
# M9.2 W1 (phone side, root over USB SSH): WLBT core only. Records the probe state, then at uptime >= 90 s boots the
# chip with the NULL service (write 1 to /dev/mx_client_test_0), samples interrupts/logs, stops the service at
# >= 180 s and samples again. No Wi-Fi/Bluetooth driver exists in this kernel. Kernel log is also streamed separately.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 40 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
wlbt() { dmesg | grep -i -E 'wlbt|scsc|mx140|mxman|plat_mif|mif|mxlog|panicmon|srvman|firmware|Unable to handle|SError|Internal error|BUG:|WARNING: CPU' | grep -v -i 'mali' | tail -n "${1:-200}"; }
state() {
    printf '\nM92_W1_STATE %s uptime=%s\n' "$1" "$(cut -d' ' -f1 /proc/uptime)"
    grep -E 'wlbt|scsc' /proc/interrupts | tr -s ' '
    ls -d /proc/driver/mxman* /proc/driver/mif* 2>/dev/null
    for f in /proc/driver/mxman_info/*; do [ -f "$f" ] && printf '%s: %s\n' "$f" "$(timeout 5 head -c 300 "$f" | tr '\n' ' ')"; done
    printf 'faults=%s\n' "$(dmesg | grep -c -E 'Unable to handle|SError|Internal error|BUG:|Kernel panic|WARNING: CPU')"
}
capture uname -r
capture cat /proc/uptime
capture cat /sys/module/firmware_class/parameters/path
capture sh -c 'ls -l /vendor/etc/wifi/mx140.bin /vendor/etc/wifi/mx140_wlan.hcf; sha256sum /vendor/etc/wifi/mx140.bin'
capture sh -c 'ls -l /dev/mx_client_test_0 /sys/bus/platform/drivers/scsc_wlbt 2>&1'
capture sh -c 'cat /proc/device-tree/soc@0/wlbt@119c0000/status; echo'
state probe
capture cat /proc/sys/kernel/tainted
capture sh -c 'dmesg | grep -A12 "cut here" | head -n 60'
capture sh -c 'ls -l /sys/bus/platform/drivers/scsc_wlbt/'
printf '\nM92_W1_PROBE_LOG\n'; wlbt 120
wait_up 90
printf '\nM92_W1_START uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
timeout 60 sh -c 'echo 1 > /dev/mx_client_test_0'; printf 'start_rc=%s uptime=%s\n' "$?" "$(cut -d' ' -f1 /proc/uptime)"
sleep 5; state started_5s
printf '\nM92_W1_START_LOG\n'; wlbt 200
wait_up 170; state started_80s
wait_up 180
printf '\nM92_W1_STOP uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
timeout 60 sh -c 'echo 0 > /dev/mx_client_test_0'; printf 'stop_rc=%s uptime=%s\n' "$?" "$(cut -d' ' -f1 /proc/uptime)"
sleep 5; state stopped_5s
printf '\nM92_W1_STOP_LOG\n'; wlbt 80
