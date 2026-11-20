#!/bin/sh
# M10.2 A1d2 (same images as A1d; GIC device glob fixed: the device is named after its first reg, 14af1000) (phone side, root over USB SSH): the ABOX SysMMU, GIC and core carry test-only compatibles, so nothing bound
# at boot. Bind them by hand in order (driver_override) while the runner streams the kernel log to the host; the
# driver prints a breadcrumb before each probe/power-on step. Then the A1 checks, a regression snapshot and, LAST, the
# isolation step: re-apply the former ABOX CPU clock raise (a1d_raise + "CPU GEAR 1"). No mixer/PulseAudio/EFS access.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 60 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
bind() { # device-glob driver
    d=$(ls /sys/bus/platform/devices | grep -E "$1" | head -n 1)
    printf '\nA1D_BIND %s -> %s at %s\n' "${d:-none}" "$2" "$(cut -d' ' -f1 /proc/uptime)"
    [ -n "$d" ] || return 1
    echo "$2" > /sys/bus/platform/devices/$d/driver_override
    echo "$d" > /sys/bus/platform/drivers/$2/bind; echo "bind_rc=$?"
    sleep 3; ls -l /sys/bus/platform/devices/$d/driver 2>&1 | sed 's/.*-> //'
}
A=/sys/devices/platform/14a50000.abox
capture uname -r
capture cat /proc/uptime
wait_up 90
bind '^14920000\.' exynos-sysmmu
bind '\.abox-gic$' samsung-abox-gic
bind '^14a50000\.abox$' samsung-abox
sleep 20
printf '\nA1D_ABOX\n'
capture sh -c "dmesg | grep -i -E 'abox|calliope|14a50000|14920000|14af|sysmmu|iommu|Unable to handle|SError|Internal error|BUG:|WARNING:' | grep -v -i mali | tail -n 200"
capture sh -c "ls $A; cat $A/calliope_version $A/reset_count $A/power/runtime_status 2>&1"
capture sh -c "grep -i -E 'aud|abox' /sys/kernel/debug/clk/clk_summary | head -40"
capture sh -c "cat /proc/asound/cards; ls -l /dev/snd 2>&1"
capture sh -c "ls -l /sys/kernel/debug/abox 2>&1; head -c 4000 /sys/kernel/debug/abox/log-00 2>&1 | strings | tail -n 60"
capture sh -c "grep -E 'abox|ABox|14af|14920000' /proc/interrupts"
printf '\nA1D_REGRESSION\n'
capture sh -c 'grep -E "^N:" /proc/bus/input/devices'
capture sh -c 'findmnt -no TARGET,OPTIONS /userdata | cut -c1-80'
capture sh -c 'head -n 1 /sys/devices/platform/148b0000.decon_f/g2b_stats; pgrep -c -x lomiri; systemctl show -p SystemState -p NFailedUnits'
capture sh -c 'nmcli -t -f DEVICE,TYPE,STATE dev; ls /sys/class/bluetooth'
capture sh -c "dmesg | grep -c -E 'Unable to handle|SError|Internal error|BUG:'"
printf '\nA1D_RAISE at %s\n' "$(cut -d' ' -f1 /proc/uptime)"
if [ -e "$A/calliope_cmd" ] && [ -e /sys/module/abox/parameters/a1d_raise ]; then
    echo 1 > /sys/module/abox/parameters/a1d_raise
    echo "CPU GEAR 1" > $A/calliope_cmd; echo "raise_cmd_rc=$?"
    sleep 15
    printf 'A1D_SURVIVED_RAISE at %s\n' "$(cut -d' ' -f1 /proc/uptime)"
    capture sh -c "dmesg | grep -E 'abox-a1d: raise|cpu clock' | tail -5"
else
    echo "raise skipped: calliope_cmd or a1d_raise missing"
fi
printf '\nA1D_DONE\n'
