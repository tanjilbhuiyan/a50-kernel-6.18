#!/bin/sh
# Execute the captured ION replay as Android's system user / graphics group.
set -eu
[ "$(lxc-info -n android -s -H)" = RUNNING ]
pid=$(lxc-info -n android -p -H)
case "$pid" in ''|*[!0-9]*) exit 1;; esac
for bits in 64 32; do
    cp "/run/a50-m64/ion-smoke$bits" "/proc/$pid/root/dev/a50-ion-smoke$bits"
    chmod 755 "/proc/$pid/root/dev/a50-ion-smoke$bits"
done
trap 'rm -f "/proc/$pid/root/dev/a50-ion-smoke64" "/proc/$pid/root/dev/a50-ion-smoke32"' EXIT
lxc-attach -n android -- /system/bin/ls -l /dev/ion /dev/binder /dev/hwbinder /dev/vndbinder
for bits in 64 32; do
    echo "Replay $bits bits, UID=1000 GID=1003"
    lxc-attach -n android --uid 1000 --gid 1003 -- "/dev/a50-ion-smoke$bits"
done
cat /sys/kernel/debug/dma_buf/bufinfo
