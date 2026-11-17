#!/bin/sh
# Focused memory ABI checks, then natural UI/runtime regression observation.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() {
    printf '\nCMD:'; printf ' %s' "$@"; printf '\n'
    timeout 10 "$@" 2>&1
    printf 'RC=%s\n' "$?"
}
capture uname -r
capture cat /proc/uptime
capture cat /sys/module/mali_kbase/parameters/a50_g1_probe_only
capture sha256sum /run/a50-g2h/*
for bits in 64 32; do
    printf '\nG2H_MEMORY_%s_BEGIN\n' "$bits"
    timeout -k 5 60 "/run/a50-g2h/kbase-memory$bits"
    printf 'G2H_MEMORY_%s_RC=%s\n' "$bits" "$?"
done
for target in 160 300; do
    while read -r up rest < /proc/uptime; do
        [ "${up%%.*}" -ge "$target" ] && break
        sleep 2
    done
    printf '\nG2H_SNAPSHOT target=%s\n' "$target"
    capture cat /proc/uptime
    capture cat /sys/devices/platform/148b0000.decon_f/g2b_stats
    capture systemctl show -p SystemState -p NFailedUnits -p NJobs
    capture systemctl list-jobs --no-pager
    capture systemctl --failed --no-pager --plain
    capture systemctl show lightdm.service -p ActiveState -p SubState -p Result -p ExecMainStatus
    capture tail -n 70 /var/log/lightdm/unity-system-compositor.log
    capture tail -n 45 /var/log/lightdm/lightdm.log
    capture journalctl -b --no-pager -n 50 _UID=32011
    capture lxc-info -n android
    capture lxc-attach -n android -- /system/bin/getprop sys.boot_completed
    capture findmnt -no TARGET,OPTIONS /userdata
    capture sh -c 'grep -E "mali|decon" /proc/interrupts'
done
capture dmesg
