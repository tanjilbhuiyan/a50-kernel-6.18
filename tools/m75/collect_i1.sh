#!/bin/sh
# M7.5 I1: where do lomiri-telephony-service-handler, PulseAudio and Lomiri block during session startup?
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
printf '\nOBSERVATION_ONLY: user-manager logging, runtime only; reset by rollback reboot\n'
userctl log-target journal; printf 'set_log_target_rc=%s\n' "$?"
userctl log-level info; printf 'set_log_level_rc=%s\n' "$?"
for target in 70 95 120 150 200 260 330; do
    while read -r up rest < /proc/uptime; do
        [ "${up%%.*}" -ge "$target" ] && break
        sleep 1
    done
    printf '\nM75_I1_SNAPSHOT target=%s\n' "$target"
    capture cat /proc/uptime
    capture cat /sys/devices/platform/148b0000.decon_f/g2b_stats
    printf '\nUSER_UNIT_PROPERTIES\n'
    userctl show pulseaudio.service pulseaudio.socket lomiri-telephony-service-handler.service \
        lomiri-full-greeter.service lomiri-url-dispatcher.service telepathy-mission-control-5.service \
        -p Id -p Type -p ActiveState -p SubState -p Result -p MainPID -p StatusText -p NRestarts \
        -p ExecMainStartTimestampMonotonic -p ActiveEnterTimestampMonotonic -p TimeoutStartUSec
    printf 'user_show_rc=%s\n' "$?"
    userctl list-jobs --no-pager
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
        printf '\nDBUS_SESSION_NAMES\n'
        out=$(asuser busctl --user --no-pager list 2>&1); rc=$?
        printf '%s\n' "$out" | grep -i -E 'NAME|telep|telephony|pulse|lomiri|URLDispatcher|ofono|history' | head -40
        printf 'busctl_rc=%s\n' "$rc"
    fi
    if [ "$target" = 95 ] || [ "$target" = 120 ]; then
        backtrace handler "$handler"
        backtrace pulseaudio "$pulse"
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
