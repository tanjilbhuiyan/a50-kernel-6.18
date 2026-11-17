#!/bin/sh
# I0: consolidated-path regressions and session lifecycle diagnosis.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() {
    printf '\nCMD:'; printf ' %s' "$@"; printf '\n'
    timeout 12 "$@" 2>&1
    printf 'RC=%s\n' "$?"
}
userctl() {
    timeout 12 runuser -u phablet -- env XDG_RUNTIME_DIR=/run/user/32011 \
        DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/32011/bus systemctl --user "$@"
}
capture uname -r
capture cat /proc/uptime
capture sha256sum /run/a50-m75-i0/kbase-memory32 /run/a50-m75-i0/kbase-memory64
for bits in 64 32; do
    printf '\nM75_I0_MEMORY_%s_BEGIN\n' "$bits"
    timeout -k 5 60 "/run/a50-m75-i0/kbase-memory$bits"
    printf 'M75_I0_MEMORY_%s_RC=%s\n' "$bits" "$?"
done
printf '\nOBSERVATION_ONLY: user-manager logging, runtime only; reset by rollback reboot\n'
userctl log-target; printf 'old_log_target_rc=%s\n' "$?"
userctl log-level; printf 'old_log_level_rc=%s\n' "$?"
userctl log-target journal; printf 'set_log_target_rc=%s\n' "$?"
userctl log-level info; printf 'set_log_level_rc=%s\n' "$?"
for target in 80 110 140 170 200 230 260 290 320 350 380; do
    while read -r up rest < /proc/uptime; do
        [ "${up%%.*}" -ge "$target" ] && break
        sleep 2
    done
    printf '\nM75_I0_SNAPSHOT target=%s\n' "$target"
    capture cat /proc/uptime
    capture cat /sys/devices/platform/148b0000.decon_f/g2b_stats
    capture systemctl show -p SystemState -p NFailedUnits -p NJobs
    printf '\nUSER_UNIT_PROPERTIES\n'
    userctl show lomiri-full-greeter.service ubuntu-touch-session-unencrypted.target \
        -p Id -p Type -p NotifyAccess -p ActiveState -p SubState -p Result -p MainPID \
        -p ExecMainStatus -p StatusText -p TimeoutStartUSec -p TimeoutStopUSec \
        -p NRestarts -p ExecMainStartTimestampMonotonic -p ExecMainExitTimestampMonotonic \
        -p ActiveEnterTimestampMonotonic -p InactiveEnterTimestampMonotonic
    printf 'user_show_rc=%s\n' "$?"
    userctl list-jobs --no-pager
    userctl --failed --no-pager --plain
    capture findmnt -no TARGET,OPTIONS /userdata
    if [ "$target" = 110 ] || [ "$target" = 230 ] || [ "$target" = 320 ] || [ "$target" = 380 ]; then
        capture systemctl --failed --no-pager --plain
        capture systemctl show lightdm.service -p ActiveState -p SubState -p Result -p MainPID
        capture lxc-info -n android
        capture lxc-attach -n android -- /system/bin/getprop sys.boot_completed
        capture tail -n 70 /var/log/lightdm/lightdm.log
        capture cat /home/phablet/.xsession-errors
        capture journalctl -b --no-pager -o short-monotonic _UID=32011 SYSLOG_IDENTIFIER=systemd -n 100
        capture journalctl -b --no-pager -o short-monotonic _SYSTEMD_USER_UNIT=lomiri-full-greeter.service -n 100
        capture sh -c 'grep -E "^(MemTotal|MemFree|MemAvailable|Slab|SUnreclaim):" /proc/meminfo'
        pid=$(userctl show lomiri-full-greeter.service -p MainPID --value)
        case "$pid" in ''|*[!0-9]*|0) ;; *)
            capture readlink "/proc/$pid/exe"
            capture sh -c 'ls "/proc/$1/fd" | wc -l' sh "$pid"
            capture sh -c 'tr "\000" "\n" < "/proc/$1/environ" | grep -E "^(NOTIFY_SOCKET|XDG_RUNTIME_DIR|MIR_SOCKET|WAYLAND_DISPLAY|GLIBC_TUNABLES)="' sh "$pid"
        esac
    fi
done
capture dmesg
