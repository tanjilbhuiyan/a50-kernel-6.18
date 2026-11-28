#!/bin/sh
# M10.4 C2: where the 6.18 vendor HAL crash loop faults (stock: same collector, service states and ELF classes only).
# C1 found six Android services crash-looping on 6.18 (vendor.audio-hal, cas-hal, drm-widevine, media.omx,
# sec-camera-provider, camera_service), each SIGSEGV/SEGV_MAPERR in its main thread ~0.5 s after start; no tombstone
# or debuggerd backtrace is produced. On 6.18 only: set debug.exception-trace=1 (runtime sysctl, restored at the end)
# so the kernel prints the unhandled re-fault after bionic's handler gives up: PC, mapping (library + offset), regs.
# Both kernels: every init.svc.* state and, for each service, the ELF class (32/64-bit) of its binary. Read-only
# otherwise; no mixer, PulseAudio or HAL change.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) M=618;; 4.14*) M=stock;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 60 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
printf 'M104C2_MODE %s\n' "$M"
capture uname -r
if [ "$M" = 618 ]; then
    wait_up 100
    old=$(cat /proc/sys/debug/exception-trace); echo 1 > /proc/sys/debug/exception-trace
    printf 'M104C2_TRACE old=%s now=%s uptime=%s\n' "$old" "$(cat /proc/sys/debug/exception-trace)" "$(cut -d' ' -f1 /proc/uptime)"
    wait_up 140
fi
capture cat /proc/uptime
printf '\nM104C2_SERVICES\n'
# name=state, then the binary path from the rc files and its ELF class byte (01 = 32-bit, 02 = 64-bit).
capture lxc-attach -n android -- /system/bin/sh -c '
for kv in $(getprop | sed -n "s/^\[init\.svc\.\([^]]*\)\]: \[\([^]]*\)\]$/\1=\2/p"); do
  n=${kv%%=*}; s=${kv#*=}
  p=$(grep -h "^service $n " /system/etc/init/*.rc /vendor/etc/init/*.rc /odm/etc/init/*.rc /system_ext/etc/init/*.rc 2>/dev/null | head -n 1 | cut -d" " -f3)
  c=$( [ -n "$p" ] && [ -r "$p" ] && od -An -tx1 -j4 -N1 "$p" | tr -d " ")
  echo "SVC $n state=$s class=${c:-?} bin=${p:-?}"
done'
if [ "$M" = 618 ]; then
    printf '\nM104C2_FAULTS\n'
    dmesg | grep -a -c 'unhandled exception'
    dmesg | grep -a 'unhandled exception' | sed -E 's/^\[ *[0-9.]+\] //; s/\[[0-9]+\]/[pid]/' | sort | uniq -c | sort -rn | head -n 40
    printf '\nM104C2_FAULT_DETAIL\n'
    # The first four full reports per process name (header + register dump); four HALs share "android.hardwar".
    dmesg | awk '/unhandled exception/ { n = $0; sub(/\[[0-9]+\]: unhandled.*/, "", n); sub(/.*\] /, "", n)
                                         seen[n]++; show = (seen[n] <= 4); c = 0 }
                 show && c < 22 { print; c++ }' | head -n 420
    echo "$old" > /proc/sys/debug/exception-trace; printf 'M104C2_TRACE_RESTORED %s\n' "$(cat /proc/sys/debug/exception-trace)"
fi
rm -f /run/m104c2-expect
printf '\nM104C2_DONE\n'
