#!/bin/sh
# M8.3 K1: do the volume and power keys (gpio-keys on gpa1-5/6/7) produce input events on 6.18? Passive capture (no
# grab: Lomiri still receives the keys). Also confirms the touchscreen is still registered. Lockup detectors panic.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 15 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
capture uname -r
capture sh -c 'dmesg | grep -i -E "gpio-keys|gpio_keys|keys|input:" | head -n 30'
capture cat /proc/bus/input/devices
capture sh -c 'grep -i -E "gpa1|gpio-keys|Volume|Power|mip4" /proc/interrupts'
capture sh -c 'cat /sys/kernel/debug/gpio | grep -i -E -A1 "gpa1" | head -n 12'
capture sh -c 'cat /sys/kernel/debug/pinctrl/11850000.pinctrl*/pinmux-pins 2>/dev/null | grep -E "gpa1-[567]"'
wait_up 80
printf '\nM83_K1_KEY_CAPTURE uptime=%s (owner presses volume up, volume down, power)\n' "$(cut -d' ' -f1 /proc/uptime)"
printf 'irq_before: %s\n' "$(grep -i -E 'gpa1|Volume|Power' /proc/interrupts | tr -s ' ' | paste -sd'|')"
timeout 75 /run/a50-k1/evcap "gpio-keys" 60; printf 'evcap_rc=%s\n' "$?"
printf 'irq_after: %s\n' "$(grep -i -E 'gpa1|Volume|Power' /proc/interrupts | tr -s ' ' | paste -sd'|')"
capture sh -c 'dmesg | grep -i -E "a50-decon.*(blank|power|dcs)|gpio-keys" | tail -n 20'
for t in 160 200; do
    wait_up "$t"
    printf '\nM83_K1_READ target=%s uptime=%s\n' "$t" "$(cut -d' ' -f1 /proc/uptime)"
    printf 'session: %s\n' "$(timeout 12 runuser -u phablet -- env XDG_RUNTIME_DIR=/run/user/32011 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/32011/bus systemctl --user show lomiri-full-greeter.service -p ActiveState -p NRestarts | paste -sd' ')"
    printf 'system: %s\n' "$(systemctl show -p SystemState -p NFailedUnits | paste -sd' ')"
done
capture sh -c 'dmesg | grep -c -E "Unable to handle|SError|Internal error|BUG:|Kernel panic|soft lockup|hard LOCKUP"'
