#!/bin/sh
# M10.4 C3: which mapping the 32-bit HIDL services fault in on 6.18 (started detached by run_m104c3.sh).
# C2: all six crash-looping services are the 32-bit hwbinder ones (the 32-bit plain-binder drmserver runs); the kernel
# exception trace stays silent because bionic's handler kills the process. Here the audio HAL and the CAS HAL are
# each started once by hand under the container's /bin/strace (-f -i -tt, 6 s, output in the container's /dev
# tmpfs, deleted after printing): every mmap/open/ioctl with its result and the SIGSEGV si_addr/pc, so the fault
# address can be placed in a mapping. Also the top of drmserver's maps (a running 32-bit process) for reference.
# Init keeps restarting its own instances meanwhile. No mixer, PulseAudio or HAL configuration change.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 60 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
la() { capture lxc-attach -n android -- /system/bin/sh -c "$1"; }
capture uname -r
wait_up 110
capture cat /proc/uptime
la 'ls -l /bin/strace /system/bin/strace 2>&1; getprop init.svc.vendor.audio-hal; getprop init.svc.vendor.cas-hal-1-2'
for s in audio:/vendor/bin/hw/android.hardware.audio.service cas:/vendor/bin/hw/android.hardware.cas@1.2-service; do
    n=${s%%:*}; b=${s#*:}
    printf '\nM104C3_TRACE %s %s\n' "$n" "$b"
    la "rm -f /dev/m104c3-$n.txt; timeout 6 /bin/strace -f -i -tt -s 80 -o /dev/m104c3-$n.txt $b; echo strace_rc=\$?"
    la "wc -l < /dev/m104c3-$n.txt; grep -n -E 'SIGSEGV|killed|exited|\+\+\+' /dev/m104c3-$n.txt | head -n 20"
    printf 'M104C3_MAPS %s\n' "$n"
    la "grep -E 'mmap|mremap|munmap|openat|execve' /dev/m104c3-$n.txt | head -n 600"
    printf 'M104C3_TAIL %s\n' "$n"
    la "tail -n 120 /dev/m104c3-$n.txt; rm -f /dev/m104c3-$n.txt"
done
printf '\nM104C3_DRMSERVER_MAPS\n'
la 'p=$(pidof drmserver); echo pid=$p; tail -n 60 /proc/$p/maps'
capture sh -c "dmesg | grep -c -E 'Unable to handle|SError|Internal error|BUG:'"
rm -f /run/m104c3-expect
printf '\nM104C3_DONE\n'
