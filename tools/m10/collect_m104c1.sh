#!/bin/sh
# M10.4 C1: why vendor.audio-hal crash-loops on 6.18 (read-only capture; started detached by run_m104c1.sh).
# Unchanged B2b5 images (ported ABOX/RT5665/TFA9872; the ADR-0005 PulseAudio overlay is still active, as on every 6.18
# boot). Reads, at ~150 s: ALSA device nodes (stock has comprC0D5, hwC0D3, hwC0D9 besides the PCMs), the HAL's init
# state, its crash buffer and newest tombstone, and audio-related logcat lines. No mixer, PulseAudio or HAL change.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 40 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
la() { capture lxc-attach -n android -- /system/bin/sh -c "$1"; }
capture uname -r
wait_up 150
capture cat /proc/uptime
printf '\nM104C1_NODES\n'
capture sh -c 'ls -l /dev/snd; cat /proc/asound/devices; cat /proc/asound/pcm'
capture sh -c 'ls /proc/asound/card0; ls -d /proc/asound/card0/pcm* /proc/asound/card0/compr* 2>/dev/null'
printf '\nM104C1_HAL\n'
la 'getprop init.svc.vendor.audio-hal; getprop init.svc_debug_pid.vendor.audio-hal; getprop | grep -i -E "audio|vendor.audio" | head -n 40'
la 'ps -A -o PID,PPID,USER,NAME | grep -i -E "audio|media" '
la 'ls -l /dev/snd 2>&1 | head -n 40'
la 'cat /vendor/etc/init/*audio*.rc 2>/dev/null | head -n 40'
printf '\nM104C1_CRASH\n'
la 'logcat -b crash -d | tail -n 300'
printf '\nM104C1_TOMBSTONE\n'
la 'ls -lt /data/tombstones 2>&1 | head -n 12; t=$(ls -t /data/tombstones/tombstone_* 2>/dev/null | grep -v "\.pb$" | head -n 1); echo "newest=$t"; [ -n "$t" ] && head -n 160 "$t"'
printf '\nM104C1_LOGCAT\n'
la 'logcat -d -b main,system -v threadtime | grep -i -E "audio|primary|tinyalsa|mixer|abox|AudioHAL|DEBUG  |libc    " | head -n 400'
printf '\nM104C1_KERNEL\n'
capture sh -c "dmesg | grep -a -E 'audio-hal|vendor.audio|signal 11|abox|rt5665|tfa98xx' | grep -v -i mali | tail -n 80"
capture sh -c "dmesg | grep -c -E 'Unable to handle|SError|Internal error|BUG:'"
rm -f /run/m104c1-expect
printf '\nM104C1_DONE\n'
