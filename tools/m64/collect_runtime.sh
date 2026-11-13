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
capture cat /run/a50-m64/kernel-early.txt
capture cat /run/a50-m64/kernel-follow.txt
capture systemctl show -p SystemState -p NFailedUnits -p NJobs
capture systemctl show mount-android-partitions.service a50-container-prepare.service lxc-android-config.service -p Id -p ActiveState -p SubState -p Result -p ExecMainStatus
capture systemctl show rild.service ofono.service bluebinder.service a50-audio-route.service repowerd.service a50-enable-autosuspend.service sleep.target -p Id -p LoadState -p ActiveState -p SubState -p Result -p ExecMainStatus -p Job
capture systemctl --failed --no-pager --plain
capture systemctl show display-manager.service android-set-boot-completion-property.service -p Id -p ActiveState -p SubState -p Result -p ExecMainStatus
capture lxc-info -n android
capture lxc-attach -n android -- /system/bin/getprop sys.boot_completed
capture lxc-attach -n android -- /system/bin/getprop init.svc.vendor.gralloc-2-0
capture lxc-attach -n android -- /system/bin/sh -c 'getprop | grep -E "allocator|gralloc|boot_completed|apexd.status|ro.crypto|vold.decrypt|sys.runsf"'
capture lxc-attach -n android -- /system/bin/sh -c 'cat /vendor/etc/init/android.hardware.graphics.allocator@2.0-service.rc'
capture lxc-attach -n android -- /system/bin/ps -A
capture lxc-attach -n android -- /system/bin/sh -c 'grep -E "^Cap|^NoNewPrivs" /proc/1/status'
capture lxc-attach -n android -- /system/bin/sh -c 'ls -l /dev/ion /dev/mali0; cat /proc/self/cgroup; cat /sys/fs/cgroup/cgroup.controllers'
capture lxc-attach -n android -- /system/bin/sh -c 'lshal | grep -E "allocator|mapper|composer"'
capture lxc-attach -n android -- /system/bin/cat /proc/mounts
capture lxc-attach -n android -- /system/bin/logcat -b all -d -t 160
capture lxc-attach -n android -- /system/bin/logcat -b crash -d
capture /bin/sh -c 'cat /sys/fs/cgroup/cgroup.controllers; cat /sys/fs/cgroup/cgroup.subtree_control; cat /proc/self/cgroup'
capture findmnt -R /android -o TARGET,SOURCE,FSTYPE,OPTIONS
capture cat /run/a50-m64/mount.log
capture cat /var/lib/lxc/android/config
capture tail -n 130 /run/a50-m64/lxc.log
capture journalctl -b --no-pager -n 80 -u mount-android-partitions.service -u a50-container-prepare.service -u lxc-android-config.service
capture journalctl -b --no-pager -n 50 -u lightdm.service -u android-set-boot-completion-property.service
capture /bin/sh -c 'tail -n 60 /var/log/lightdm/lightdm.log'
capture /bin/sh -c 'stat -c "%y %n" /var/log/lightdm/lightdm.log /var/log/lightdm/unity-system-compositor.log; tail -n 60 /var/log/lightdm/unity-system-compositor.log'
capture /bin/sh -c 'dmesg | grep -E "A50_UFS_SAFE|EXT4-fs.*sda32|exynos-sysmmu|A50M64" | tail -n 90'
capture /bin/sh -c 'dmesg | grep -F "lxc[" | tail -n 90'
