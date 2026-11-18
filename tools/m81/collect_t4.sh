#!/bin/sh
# M8.1 T4: clean a50-input I2C patches (buses 0/1/3/4/6 on the ADR-0007 fixed clock) in the GPU-profile DTB, T1 BOOT.
# Lists every adapter, its DT node, pins and IRQ; repeats T2's read-only reads of 0x48 on the touch bus only (no traffic
# on the other buses, whose stock devices may have clear-on-read registers). Lockup detectors panic.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 15 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
capture uname -r
capture cat /proc/uptime
capture sh -c 'dmesg | grep -i -E "i2c|s3c|13870000|watchdog|lockup|hung_task" | head -n 40'
capture sh -c 'ls -l /sys/bus/i2c/devices/ /dev/i2c-* 2>&1'
capture sh -c 'for a in /sys/bus/i2c/devices/i2c-*; do echo "$a $(cat $a/name 2>/dev/null) of_node=$(readlink $a/of_node 2>/dev/null)"; done'
capture sh -c 'cat /sys/kernel/debug/pinctrl/139b0000.pinctrl*/pinmux-pins 2>/dev/null | grep -E "gpp0-[0-7]|gpp1-[0145]" ; cat /sys/kernel/debug/pinctrl/139b0000.pinctrl*/pinconf-groups 2>/dev/null | grep -A2 i2c4'
capture sh -c 'grep -E "13870000|i2c" /proc/interrupts'
capture sh -c 'for f in watchdog nmi_watchdog soft_watchdog watchdog_thresh softlockup_panic hardlockup_panic hung_task_timeout_secs; do printf "%s=%s\n" $f "$(cat /proc/sys/kernel/$f 2>/dev/null)"; done'
wait_up 75
printf '\nM81_T4_XFER uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
printf 'irq_before: %s\n' "$(grep 13870000 /proc/interrupts | tr -s ' ')"
tb=$(for a in /sys/bus/i2c/devices/i2c-*; do case "$(readlink $a/of_node)" in *i2c@13870000) echo ${a##*-};; esac; done)
printf 'touch_bus=%s\n' "$tb"
for n in 1 1 4; do timeout 10 /run/a50-r1/i2c_read "$tb" 0x48 $n; printf 'i2c_read_rc=%s\n' "$?"; sleep 1; done
printf 'irq_after: %s\n' "$(grep 13870000 /proc/interrupts | tr -s ' ')"
capture sh -c 'dmesg | grep -i -E "i2c|s3c|13870000" | tail -n 20'
capture sh -c 'cat /sys/kernel/debug/gpio 2>/dev/null | head -n 60'
for t in 120 200; do
    wait_up "$t"
    printf '\nM81_T4_READ target=%s uptime=%s\n' "$t" "$(cut -d' ' -f1 /proc/uptime)"
    timeout 15 /run/a50-r1/regread; printf 'regread_rc=%s\n' "$?"
    printf 'session: %s\n' "$(timeout 12 runuser -u phablet -- env XDG_RUNTIME_DIR=/run/user/32011 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/32011/bus systemctl --user show lomiri-full-greeter.service -p ActiveState -p NRestarts | paste -sd' ')"
    printf 'system: %s\n' "$(systemctl show -p SystemState -p NFailedUnits | paste -sd' ')"
done
capture sh -c 'dmesg | grep -c -E "Unable to handle|SError|Internal error|BUG:|Kernel panic|soft lockup|hard LOCKUP|blocked for more than"'
capture sh -c 'dmesg | grep -E "soft lockup|hard LOCKUP|blocked for more than|i2c" | tail -n 20'
