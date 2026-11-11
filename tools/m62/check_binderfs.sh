#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Run over the test boot's USB root SSH session.
set -eu

mode=${1:?usage: check_binderfs.sh control or candidate SMOKE_BINARY}
case "$mode" in
    control) ;;
    candidate) smoke=${2:?candidate requires the Binder smoke binary} ;;
    *) echo "Unknown test mode $mode" >&2; exit 2 ;;
esac

release=$(uname -r)
echo "kernel=$release"
case "$release" in
    6.18.*-a50-diag*) ;;
    *) echo "Expected the 6.18 diagnostic boot" >&2; exit 1 ;;
esac

load_state=$(systemctl show -p LoadState --value mount-android-partitions.service)
android_state=$(lxc-info -n android -sH)
userdata_options=$(findmnt -n -o OPTIONS --mountpoint /userdata)
printf 'mount-android-partitions=%s\nandroid=%s\nuserdata=%s\n' \
    "$load_state" "$android_state" "$userdata_options"
test "$load_state" = masked
test "$android_state" = STOPPED
case ",$userdata_options," in
    *,rw,*) ;;
    *) echo "Expected read-write userdata" >&2; exit 1 ;;
esac

mount_dir=$(mktemp -d /run/a50-m62-binderfs.XXXXXX)
mounted=0
cleanup() {
    if [ "$mounted" = 1 ]; then
        umount "$mount_dir"
    fi
    rmdir "$mount_dir"
}
trap cleanup EXIT

if mount -t binder -o stats=global binder "$mount_dir"; then
    mounted=1
else
    mount_status=$?
    printf 'BinderFS mount exited %d\n' "$mount_status"
    if [ "$mode" = control ] && ! grep -qw binder /proc/filesystems; then
        echo 'PASS control: binder filesystem absent'
        exit 0
    fi
    exit "$mount_status"
fi

if [ "$mode" = control ]; then
    echo 'Unexpected BinderFS mount on the control' >&2
    exit 1
fi

findmnt -n -o TARGET,SOURCE,FSTYPE,OPTIONS --mountpoint "$mount_dir"
test -c "$mount_dir/binder-control"
stat -c '%n %F %t:%T' "$mount_dir/binder-control" \
    "$mount_dir/binder" "$mount_dir/hwbinder" "$mount_dir/vndbinder"
"$smoke" "$mount_dir/binder" "$mount_dir/hwbinder" "$mount_dir/vndbinder"
cleanup
trap - EXIT
echo 'PASS candidate: BinderFS and three Binder contexts'
