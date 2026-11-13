#!/bin/sh
# Run as host root on the test boot, with the static matrix helper staged.
set -eu
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
[ "$(lxc-info -n android -s -H)" = RUNNING ]
# This synthetic SCSI minor must have no backing device. No block I/O occurs.
[ ! -e /sys/dev/block/8:255 ]
pid=$(lxc-info -n android -p -H)
case "$pid" in ''|*[!0-9]*) exit 1;; esac
cp /run/a50-m64/block-policy-matrix "/proc/$pid/root/dev/a50-policy-matrix"
chmod 700 "/proc/$pid/root/dev/a50-policy-matrix"
nsenter -t "$pid" -m -r -- /system/bin/toybox mknod -m 600 /dev/a50-block-policy-probe b 8 255
trap 'nsenter -t "$pid" -m -r -- /system/bin/toybox rm -f /dev/a50-block-policy-probe /dev/a50-policy-matrix' EXIT
lxc-attach -n android -- /dev/a50-policy-matrix
