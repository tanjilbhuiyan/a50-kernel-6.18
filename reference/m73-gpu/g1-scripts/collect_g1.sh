#!/bin/sh
# G1 metadata probe and read-only live observations. Payloads are already in tmpfs.
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
capture ls -l /dev/mali0
capture /run/a50-g1-exec/gpuprops64
capture /run/a50-g1-exec/gpuprops32
capture /bin/sh -c 'grep -iE "mali|gpu|mmu|job" /proc/interrupts'
capture /bin/sh -c 'cat /sys/devices/platform/11500000.mali/uevent; readlink /sys/devices/platform/11500000.mali/driver'
capture systemctl show -p SystemState -p NFailedUnits -p NJobs
capture systemctl --failed --no-pager --plain
capture lxc-info -n android
capture findmnt -no TARGET,OPTIONS /userdata
capture /bin/sh -c 'dmesg | grep -E "mali|Mali|A50 G1|A50_UFS_SAFE|EXT4-fs.*sda32|[Ss]ys[Mm][Mm][Uu]|fault|SError|BUG:"'
capture cat /run/a50-m64/kernel-early.txt
capture dmesg
