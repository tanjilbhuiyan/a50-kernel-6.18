#!/bin/sh
# M7.5 I4: with ADR-0005 (audio) and ADR-0006 (gst-hybris placeholder), do the telephony handler and Lomiri become ready?
# Same observations as I2 plus the ADR-0006 state, gst-plugin-scanner processes and the registry's blacklist.
# Observation only: reads /proc, journals, unit properties and D-Bus names; one timed `pactl info` (read-only query,
# no mixer/PulseAudio state change); a gdb backtrace only if gdb exists on the rootfs (ptrace pauses the process for
# the duration of the dump, nothing is changed). The user-manager log target/level change is runtime only (as in I0).
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
UENV="XDG_RUNTIME_DIR=/run/user/32011 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/32011/bus"
capture() {
    printf '\nCMD:'; printf ' %s' "$@"; printf '\n'
    timeout 12 "$@" 2>&1
    printf 'RC=%s\n' "$?"
}
asuser() { timeout 12 runuser -u phablet -- env $UENV "$@"; }
userctl() { asuser systemctl --user "$@"; }
threads() { # $1 label, $2 pid
    pid=$2
    case "$pid" in ''|*[!0-9]*|0) printf '\nTHREADS %s: no pid\n' "$1"; return;; esac
    [ -d "/proc/$pid" ] || { printf '\nTHREADS %s pid=%s: gone\n' "$1" "$pid"; return; }
    printf '\nTHREADS %s pid=%s exe=%s\n' "$1" "$pid" "$(readlink "/proc/$pid/exe")"
    tr '\000' ' ' < "/proc/$pid/cmdline"; echo
    for t in /proc/"$pid"/task/*; do
        tid=${t##*/}
        printf -- '-- tid=%s comm=%s state=%s wchan=%s\n' "$tid" "$(cat "$t/comm")" \
            "$(sed -n 's/^State:[[:space:]]*//p' "$t/status")" "$(cat "$t/wchan" 2>/dev/null)"
        printf '   syscall: %s\n' "$(cat "$t/syscall" 2>/dev/null)"
        sed 's/^/   /' "$t/stack" 2>/dev/null
    done
    printf -- '-- fds: %s\n' "$(ls "/proc/$pid/fd" | wc -l)"
    ls -l "/proc/$pid/fd" 2>/dev/null | sed -n 's/.* \([0-9]*\) -> \(.*\)$/   fd \1 -> \2/p' | grep -v -E '/dev/null|anon_inode:\[(eventfd|eventpoll)\]' | head -60
}
backtrace() { # $1 label, $2 pid
    case "$2" in ''|*[!0-9]*|0) return;; esac
    command -v gdb >/dev/null 2>&1 || { printf '\nBACKTRACE %s: gdb not installed\n' "$1"; return; }
    printf '\nBACKTRACE %s pid=%s\n' "$1" "$2"
    timeout -k 3 25 gdb -nx -batch -p "$2" -ex 'set pagination off' -ex 'thread apply all bt 25' 2>&1 | \
        grep -E '^(Thread|#)' | head -200
    printf 'gdb_rc=%s\n' "$?"
}
pid_of() { pgrep -o -u phablet -f "^$1( |$)" 2>/dev/null; }

capture uname -r
capture cat /proc/uptime
printf '\nTOOLS\n'
for c in gdb pactl busctl gdbus pgrep runuser; do printf '%s=%s\n' "$c" "$(command -v "$c" || echo missing)"; done
printf '\nADR0005_STATE\n'
capture findmnt -no TARGET,SOURCE,OPTIONS /etc/pulse/touch.pa
capture sha256sum /etc/pulse/touch.pa
capture systemctl show a50-defer-audio.service -p ActiveState -p SubState -p Result -p ExecMainStatus -p ActiveEnterTimestampMonotonic
capture journalctl -b --no-pager -o short-monotonic -u a50-defer-audio.service
printf '\nADR0006_STATE\n'
capture findmnt -no TARGET,SOURCE,OPTIONS /usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgsthybris.so
capture sha256sum /usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgsthybris.so
capture systemctl show a50-defer-gsthybris.service -p ActiveState -p SubState -p Result -p ExecMainStatus -p ActiveEnterTimestampMonotonic
capture journalctl -b --no-pager -o short-monotonic -u a50-defer-gsthybris.service
printf '\nOBSERVATION_ONLY: user-manager logging, runtime only; reset by rollback reboot\n'
userctl log-target journal; printf 'set_log_target_rc=%s\n' "$?"
userctl log-level info; printf 'set_log_level_rc=%s\n' "$?"
for target in 70 95 120 150 200 260 330; do
    while read -r up rest < /proc/uptime; do
        [ "${up%%.*}" -ge "$target" ] && break
        sleep 1
    done
    printf '\nM75_I4_SNAPSHOT target=%s\n' "$target"
    capture cat /proc/uptime
    capture cat /sys/devices/platform/148b0000.decon_f/g2b_stats
    capture systemctl show -p SystemState -p NFailedUnits -p NJobs
    capture systemctl --failed --no-pager --plain
    printf '\nUSER_UNIT_PROPERTIES\n'
    userctl show pulseaudio.service pulseaudio.socket lomiri-telephony-service-handler.service \
        lomiri-full-greeter.service lomiri-url-dispatcher.service telepathy-mission-control-5.service \
        ubuntu-touch-session-unencrypted.target ubuntu-touch-session.target graphical-session.target \
        -p Id -p Type -p ActiveState -p SubState -p Result -p MainPID -p StatusText -p NRestarts \
        -p ExecMainStartTimestampMonotonic -p ActiveEnterTimestampMonotonic -p TimeoutStartUSec
    printf 'user_show_rc=%s\n' "$?"
    userctl list-jobs --no-pager
    printf '\nGST_SCANNERS\n'; ps -eo pid,ppid,etimes,stat,args | grep -E '[g]st-plugin-scanner' || echo none
    capture ls -la /home/phablet/.cache/gstreamer-1.0
    handler=$(pid_of /usr/bin/lomiri-telephony-service-handler)
    pulse=$(pgrep -o -u phablet -x pulseaudio 2>/dev/null)
    lomiri=$(userctl show lomiri-full-greeter.service -p MainPID --value)
    threads handler "$handler"
    threads pulseaudio "$pulse"
    if [ "$target" -le 150 ]; then
        threads lomiri "$lomiri"
        printf '\nPACTL_INFO (timeout 10 s)\n'
        s=$(cut -d' ' -f1 /proc/uptime)
        out=$(timeout 10 runuser -u phablet -- env $UENV pactl info 2>&1); rc=$?
        printf '%s\n' "$out" | head -20
        printf 'pactl_rc=%s start=%s end=%s\n' "$rc" "$s" "$(cut -d' ' -f1 /proc/uptime)"
        out=$(timeout 10 runuser -u phablet -- env $UENV pactl list short sinks 2>&1); rc=$?
        printf 'PACTL_SINKS rc=%s\n%s\n' "$rc" "$out"
        printf '\nDBUS_SESSION_NAMES\n'
        out=$(asuser busctl --user --no-pager list 2>&1); rc=$?
        printf '%s\n' "$out" | grep -i -E 'NAME|telep|telephony|pulse|lomiri|URLDispatcher|ofono|history' | head -40
        printf 'busctl_rc=%s\n' "$rc"
    fi
    if [ "$target" = 95 ] || [ "$target" = 120 ]; then
        backtrace handler "$handler"
        backtrace pulseaudio "$pulse"
    fi
    if [ "$target" = 150 ]; then
        printf '\nGST_BLACKLIST (registry as built by the session)\n'
        out=$(timeout 30 runuser -u phablet -- env $UENV gst-inspect-1.0 -b 2>&1); rc=$?
        printf '%s\ngst_inspect_b_rc=%s\n' "$out" "$rc"
        out=$(timeout 30 runuser -u phablet -- env $UENV gst-inspect-1.0 2>/dev/null | tail -n 1); printf 'gst_total: %s\n' "$out"
    fi
    if [ "$target" = 120 ] || [ "$target" = 200 ] || [ "$target" = 330 ]; then
        capture journalctl -b --no-pager -o short-monotonic _SYSTEMD_USER_UNIT=lomiri-telephony-service-handler.service -n 80
        capture journalctl -b --no-pager -o short-monotonic _SYSTEMD_USER_UNIT=pulseaudio.service -n 120
        capture journalctl -b --no-pager -o short-monotonic _UID=32011 SYSLOG_IDENTIFIER=systemd -n 120
        capture journalctl -b --no-pager -o short-monotonic _SYSTEMD_USER_UNIT=lomiri-full-greeter.service -n 60
        capture sh -c 'journalctl -b --no-pager -o short-monotonic | grep -i -E "pulse|telephony|audio.*hal|audioflinger|droid" | tail -n 120'
        capture lxc-attach -n android -- /system/bin/getprop init.svc.vendor.audio-hal-2-0
        capture sh -c 'lxc-attach -n android -- /system/bin/getprop | grep -i -E "audio|media" | head -40'
    fi
done
capture dmesg
