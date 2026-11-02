#!/bin/bash
# Phone-side ioctl capture (M1.3). Run as root on the baseline phone:
#   cap_ioctl.sh NAME SECONDS PATTERN [PATTERN...]
# PATTERN = pgrep -f pattern. Every matching process is traced with strace for SECONDS:
#  - host-side processes with a host strace copied to /tmp/strace-host (not installed),
#  - Android-container processes with the container's own /bin/strace via lxc-attach.
# Output: /tmp/cap-NAME-<where>-<pid>-<comm>.txt (raw strace lines). Holds a wakelock.
# The kernel has no CONFIG_FTRACE_SYSCALLS, so strace is the only ioctl tracer.
# WARNING: attach-mode strace stops every syscall of the target. Tracing the Lomiri shell / maliit-server
# makes the UI unusable (login and input fail) until it detaches; keep UI-process captures short.
set -u
NAME=$1; SECS=$2; shift 2
echo m13 > /sys/power/wake_lock
HOSTNS=$(readlink /proc/1/ns/pid)
pids=()
for pat in "$@"; do
  for p in $(pgrep -f "$pat"); do
    [ "$p" = "$$" ] && continue
    comm=$(tr -d '\n' < /proc/$p/comm | tr -c 'A-Za-z0-9._@-' '_')
    case "$comm" in bash|sh|dash|pgrep|ssh*|sshd*) continue;; esac
    if [ "$(readlink /proc/$p/ns/pid)" = "$HOSTNS" ]; then
      /tmp/strace-host -f -y -s 0 -e trace=ioctl -p "$p" -o "/tmp/cap-$NAME-host-$p-$comm.txt" 2>/dev/null &
      pids+=($!)
    else
      inner=$(awk '/^NSpid/{print $NF}' /proc/$p/status)
      ( timeout "$SECS" lxc-attach -n android -- /bin/strace -f -y -s 0 -e trace=ioctl -p "$inner" > "/tmp/cap-$NAME-cont-$p-$comm.txt" 2>&1 ) &
    fi
  done
done
echo "capture $NAME started $(date +%T) for ${SECS}s, host tracers: ${#pids[@]}"
sleep "$SECS"
for t in "${pids[@]}"; do kill -INT "$t" 2>/dev/null; done
sleep 1; wait 2>/dev/null
echo "capture $NAME done $(date +%T)"; ls -l /tmp/cap-$NAME-* 2>/dev/null | awk '{print $5, $NF}'
