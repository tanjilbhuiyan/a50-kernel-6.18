#!/bin/sh
# Read-only M6.4 live collection, run through root SSH on the test kernel.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 LC_ALL=C
capture() {
    printf '\nCMD:'; printf ' %s' "$@"; printf '\n'
    timeout 8 "$@" 2>&1
    printf 'RC=%s\n' "$?"
}
capture uname -r
capture cat /proc/uptime
capture systemctl show -p SystemState -p NFailedUnits -p NJobs
capture systemctl show mount-android-partitions.service a50-container-prepare.service lxc-android-config.service -p Id -p ActiveState -p SubState -p Result -p ExecMainStatus
capture systemctl --failed --no-pager --plain
capture systemctl show display-manager.service android-set-boot-completion-property.service -p Id -p ActiveState -p SubState -p Result -p ExecMainStatus
capture lxc-info -n android
capture lxc-attach -n android -- /system/bin/getprop sys.boot_completed
capture lxc-attach -n android -- /system/bin/getprop init.svc.vendor.allocator-2-0
capture lxc-attach -n android -- /system/bin/ps -A
capture lxc-attach -n android -- /system/bin/cat /proc/mounts
capture lxc-attach -n android -- /system/bin/logcat -b all -d -t 160
capture /bin/sh -c 'cat /sys/fs/cgroup/cgroup.controllers; cat /sys/fs/cgroup/cgroup.subtree_control; cat /proc/self/cgroup'
capture findmnt -R /android -o TARGET,SOURCE,FSTYPE,OPTIONS
capture cat /run/a50-m64/mount.log
capture cat /var/lib/lxc/android/config
capture tail -n 130 /run/a50-m64/lxc.log
capture journalctl -b --no-pager -n 80 -u mount-android-partitions.service -u a50-container-prepare.service -u lxc-android-config.service
capture journalctl -b --no-pager -n 50 -u lightdm.service -u android-set-boot-completion-property.service
capture /bin/sh -c 'tail -n 60 /var/log/lightdm/lightdm.log'
capture /bin/sh -c 'dmesg | grep -E "A50_UFS_SAFE|EXT4-fs.*sda32|exynos-sysmmu|A50M64" | tail -n 90'
