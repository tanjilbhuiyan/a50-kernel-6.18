#!/bin/sh
# Read-only runtime observations; spawned before switch_root.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 LC_ALL=C
emit() { printf '<6>A50M64: %s\n' "$*" > /dev/kmsg; }
capture() {
    emit "CMD $*"
    timeout 5 "$@" > /run/a50-m64/status-output 2>&1
    result=$?
    while IFS= read -r line || [ -n "$line" ]; do emit "$line"; done < /run/a50-m64/status-output
    emit "RC $result"
}
emit 'runtime observer armed'
# Save before LXC/Android can fill the kernel ring with restart diagnostics.
dmesg > /run/a50-m64/kernel-early.txt 2>&1
dmesg --follow > /run/a50-m64/kernel-follow.txt 2>&1 &
for target in 60 120 200 340; do
    while :; do
        read -r uptime rest < /proc/uptime
        [ "${uptime%%.*}" -ge "$target" ] && break
        sleep 2
    done
    emit "BEGIN target=$target uptime=$uptime"
    capture systemctl show mount-android-partitions.service a50-container-prepare.service lxc-android-config.service -p Id -p ActiveState -p SubState -p Result -p ExecMainStatus
    capture systemctl show rild.service ofono.service bluebinder.service a50-audio-route.service -p Id -p ActiveState -p SubState -p Result -p ExecMainStatus -p Job
    capture lxc-info -n android
    capture lxc-attach -n android -- /system/bin/getprop sys.boot_completed
    capture lxc-attach -n android -- /system/bin/getprop init.svc.vendor.gralloc-2-0
    capture /bin/sh -c 'ps -eo pid,comm,args | grep -E "graphics.allocator|/system/bin/init|lxc-start|servicemanager" | grep -v grep'
    capture /bin/sh -c 'cat /sys/fs/cgroup/cgroup.controllers; cat /sys/fs/cgroup/cgroup.subtree_control; cat /proc/self/cgroup'
    capture findmnt -R /android -o TARGET,SOURCE,FSTYPE,OPTIONS
    capture tail -n 35 /run/a50-m64/mount.log
    capture /bin/sh -c 'tail -n 70 /run/a50-m64/lxc.log'
    capture journalctl -b --no-pager -n 35 -u mount-android-partitions.service -u a50-container-prepare.service -u lxc-android-config.service
    emit "END target=$target"
done
