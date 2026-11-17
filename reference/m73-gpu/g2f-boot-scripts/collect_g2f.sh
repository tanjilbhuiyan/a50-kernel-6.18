#!/bin/sh
# G2f: natural UI startup, metadata ABI checks; no competing graphics client.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() {
    printf '\nCMD:'; printf ' %s' "$@"; printf '\n'
    timeout 10 "$@" 2>&1
    printf 'RC=%s\n' "$?"
}
snapshot() {
    capture cat /proc/uptime
    capture cat /sys/devices/platform/148b0000.decon_f/g2b_stats
    capture systemctl show lightdm.service -p ActiveState -p SubState -p Result -p ExecMainStatus
    capture tail -n 90 /var/log/lightdm/unity-system-compositor.log
    capture tail -n 30 /var/log/lightdm/lightdm.log
    capture sh -c 'grep -E "mali|decon" /proc/interrupts'
    capture ps -eo pid,stat,wchan:32,comm
}
capture uname -r
capture sha256sum /run/a50-g2f/*
capture python3 /run/a50-g2f/read_display_info.py
echo G2F_METADATA_ABI_CHECKS
capture /run/a50-g2f/metadata64
capture /run/a50-g2f/metadata32
for target in 100 200 300; do
    while read -r up rest < /proc/uptime; do
        [ "${up%%.*}" -ge "$target" ] && break
        sleep 2
    done
    printf '\nG2F_NATURAL_STARTUP target=%s\n' "$target"
    snapshot
    capture systemctl show -p SystemState -p NFailedUnits -p NJobs
    capture systemctl --failed --no-pager --plain
    capture systemctl --user --machine=phablet@.host --failed --no-pager
    capture systemctl --user --machine=phablet@.host list-jobs --no-pager
    capture journalctl -b --no-pager -n 70 _UID=32011
    capture lxc-info -n android
    capture lxc-attach -n android -- /system/bin/getprop sys.boot_completed
    capture findmnt -no TARGET,OPTIONS /userdata
done
capture dmesg
