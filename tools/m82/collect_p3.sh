#!/bin/sh
# M8.2 P3: clean event-format fallback (melfas,event-format/size from DT) + TEST ONLY empty-packet READY_STATUS probe.
# Expect decoded touches in the passive capture; samples of the gpa0-0 line idle and while the owner touches. Observation only: never writes the controller's firmware (the driver's
# root-only update_fw sysfs file is not touched) and never grabs the input device. Lockup detectors panic.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 15 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
capture uname -r
capture cat /proc/uptime
capture sh -c 'dmesg | grep -i -E "mip4|melfas|0048|touchscreen|input:" | head -n 60'
printf '\nM82_P3_EINT_IDLE\n'; timeout 10 /run/a50-p1/eintread; printf 'eintread_rc=%s\n' "$?"
capture sh -c 'for d in /sys/bus/i2c/devices/*-0048; do echo "$d driver=$(readlink $d/driver)"; for a in product_id ic_name fw_version hw_version; do printf "  %s=" $a; cat $d/$a 2>&1; done; done'
capture cat /proc/bus/input/devices
capture sh -c 'grep -i -E "mip4|melfas|gpa0|i2c" /proc/interrupts'
capture sh -c 'grep -i -E "gpg3|gpa0|ce|mip4" /sys/kernel/debug/gpio | head -n 20'
capture sh -c 'cat /sys/kernel/debug/pinctrl/11850000.pinctrl*/pinmux-pins 2>/dev/null | grep -E "gpa0-0"'
wait_up 80
printf '\nM82_P3_TOUCH_CAPTURE uptime=%s (owner drags a finger on the screen)\n' "$(cut -d' ' -f1 /proc/uptime)"
printf 'irq_before: %s\n' "$(grep -i -E 'mip4|melfas' /proc/interrupts | tr -s ' ')"
( sleep 15; printf '\nM82_P3_EINT_TOUCH_A\n'; timeout 10 /run/a50-p1/eintread; sleep 15; printf '\nM82_P3_EINT_TOUCH_B\n'; timeout 10 /run/a50-p1/eintread ) > /run/a50-p1/eint-touch.txt 2>&1 &
timeout 75 /run/a50-p1/evcap "MELFAS" 60; printf 'evcap_rc=%s\n' "$?"
wait; cat /run/a50-p1/eint-touch.txt
printf 'irq_after: %s\n' "$(grep -i -E 'mip4|melfas' /proc/interrupts | tr -s ' ')"
capture sh -c 'dmesg | grep -E "P3 " | head -n 60'
capture sh -c 'dmesg | grep -i -E "mip4|melfas" | tail -n 20'
for t in 160 200; do
    wait_up "$t"
    printf '\nM82_P3_READ target=%s uptime=%s\n' "$t" "$(cut -d' ' -f1 /proc/uptime)"
    printf 'session: %s\n' "$(timeout 12 runuser -u phablet -- env XDG_RUNTIME_DIR=/run/user/32011 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/32011/bus systemctl --user show lomiri-full-greeter.service -p ActiveState -p NRestarts | paste -sd' ')"
    printf 'system: %s\n' "$(systemctl show -p SystemState -p NFailedUnits | paste -sd' ')"
done
capture sh -c 'dmesg | grep -c -E "Unable to handle|SError|Internal error|BUG:|Kernel panic|soft lockup|hard LOCKUP"'
