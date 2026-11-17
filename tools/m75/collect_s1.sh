#!/bin/sh
# M7.5 S1: ten-minute UI soak on the I4 runtime (ADR-0005/0006) with the timed dump at 900 s.
# 1. Regression block at ~70 s: kbase native/compat memory helpers (as I0), ION 64/32 replay as Android's system user
#    (as M6.4), allocator service state, userdata mount.
# 2. Soak samples every 30 s from 90 s to 720 s (more than ten minutes after Lomiri's READY at ~48 s in I4): unit PIDs
#    and states, systemd state, display/fence counters, GPU and display IRQs, memory, dma-buf totals, Lomiri fd/RSS,
#    kernel fault-signature count.
# 3. Final: renderer lines from Lomiri and the system compositor, failed units, journals.
# Observation only, except the helpers' own allocations (freed by them) and the user-manager log level (runtime only).
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
UENV="XDG_RUNTIME_DIR=/run/user/32011 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/32011/bus"
H=/run/a50-s1
capture() {
    printf '\nCMD:'; printf ' %s' "$@"; printf '\n'
    timeout 15 "$@" 2>&1
    printf 'RC=%s\n' "$?"
}
userctl() { timeout 12 runuser -u phablet -- env $UENV systemctl --user "$@"; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
faults() { dmesg | grep -c -E 'Unable to handle|SError|Internal error|BUG:|Kernel panic|WARNING: CPU|kbase.*(fault|error)|sysmmu.*fault|dma_fence.*timed out' ; }

capture uname -r
capture cat /proc/uptime
capture sha256sum $H/kbase-memory64 $H/kbase-memory32 $H/ion-smoke64 $H/ion-smoke32
printf '\nDEFERRALS\n'
capture findmnt -no TARGET,SOURCE,OPTIONS /etc/pulse/touch.pa
capture findmnt -no TARGET,SOURCE,OPTIONS /usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgsthybris.so
capture systemctl show a50-defer-audio.service a50-defer-gsthybris.service -p Id -p ActiveState -p Result
printf '\nOBSERVATION_ONLY: user-manager logging, runtime only; reset by rollback reboot\n'
userctl log-target journal; printf 'set_log_target_rc=%s\n' "$?"
userctl log-level info; printf 'set_log_level_rc=%s\n' "$?"

wait_up 70
printf '\nM75_S1_REGRESSION uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
for bits in 64 32; do
    printf '\nM75_S1_KBASE_MEMORY_%s_BEGIN\n' "$bits"
    timeout -k 5 60 "$H/kbase-memory$bits"
    printf 'M75_S1_KBASE_MEMORY_%s_RC=%s\n' "$bits" "$?"
done
pid=$(lxc-info -n android -p -H 2>/dev/null)
case "$pid" in ''|*[!0-9]*) printf 'M75_S1_ION: no container pid\n';; *)
    for bits in 64 32; do cp "$H/ion-smoke$bits" "/proc/$pid/root/dev/a50-ion-smoke$bits"; chmod 755 "/proc/$pid/root/dev/a50-ion-smoke$bits"; done
    for bits in 64 32; do
        printf '\nM75_S1_ION_%s_BEGIN (UID=1000 GID=1003)\n' "$bits"
        timeout -k 5 60 lxc-attach -n android --uid 1000 --gid 1003 -- "/dev/a50-ion-smoke$bits"
        printf 'M75_S1_ION_%s_RC=%s\n' "$bits" "$?"
    done
    rm -f "/proc/$pid/root/dev/a50-ion-smoke64" "/proc/$pid/root/dev/a50-ion-smoke32";;
esac
capture sh -c 'lxc-attach -n android -- /system/bin/getprop | grep -E "allocator|gralloc|composer|sys.boot_completed"'
capture findmnt -no TARGET,OPTIONS /userdata
printf 'faults_after_regression=%s\n' "$(faults)"

t=90
while [ "$t" -le 720 ]; do
    wait_up "$t"
    printf '\nM75_S1_SAMPLE target=%s uptime=%s\n' "$t" "$(cut -d' ' -f1 /proc/uptime)"
    userctl show lomiri-full-greeter.service lomiri-telephony-service-handler.service pulseaudio.service \
        ubuntu-touch-session-unencrypted.target -p Id -p ActiveState -p SubState -p MainPID -p NRestarts -p Result \
        -p ActiveEnterTimestampMonotonic | paste -sd' ' | sed 's/ Id=/\nId=/g'
    printf 'system: %s\n' "$(systemctl show -p SystemState -p NFailedUnits -p NJobs | paste -sd' ')"
    printf 'display: %s\n' "$(head -n 1 /sys/devices/platform/148b0000.decon_f/g2b_stats)"
    printf 'irqs: %s\n' "$(grep -E 'mali|decon' /proc/interrupts | tr -s ' ' | paste -sd'|')"
    printf 'mem: %s\n' "$(grep -E '^(MemAvailable|Slab|SUnreclaim|Shmem|CmaFree):' /proc/meminfo | tr -s ' ' | paste -sd' ')"
    printf 'dmabuf: %s\n' "$(awk '/^Total/ {print} END {}' /sys/kernel/debug/dma_buf/bufinfo 2>/dev/null | tail -n 1)"
    lp=$(userctl show lomiri-full-greeter.service -p MainPID --value)
    case "$lp" in ''|*[!0-9]*|0) printf 'lomiri: no pid\n';; *)
        printf 'lomiri: pid=%s fds=%s %s threads=%s\n' "$lp" "$(ls /proc/$lp/fd 2>/dev/null | wc -l)" \
            "$(grep -E '^VmRSS' /proc/$lp/status | tr -s ' ')" "$(ls /proc/$lp/task 2>/dev/null | wc -l)";;
    esac
    printf 'faults=%s\n' "$(faults)"
    t=$((t + 30))
done

printf '\nM75_S1_FINAL uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
capture sh -c 'journalctl -b --no-pager -o short-monotonic _SYSTEMD_USER_UNIT=lomiri-full-greeter.service | grep -E "GL (renderer|version)|GLSL|EGL|Selected driver" | head -n 20'
capture sh -c 'grep -E "GL (renderer|version)|GLSL|Selected driver" /var/log/lightdm/unity-system-compositor.log | tail -n 12'
capture systemctl --failed --no-pager --plain
userctl --failed --no-pager --plain
capture sh -c 'dmesg | grep -E "Unable to handle|SError|Internal error|BUG:|Kernel panic|WARNING: CPU|kbase.*(fault|error)|sysmmu.*fault|dma_fence.*timed out" | tail -n 40'
capture cat /sys/kernel/debug/dma_buf/bufinfo
