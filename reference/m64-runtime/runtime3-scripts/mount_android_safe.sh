#!/bin/sh
# M6.4 replacement for mount-android-partitions, staged only in /run.
set -eu
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
log() { echo "A50M64: $*"; }
fail() { log "REFUSE: $*"; exit 1; }
has_option() { case ",$1," in *",$2,"*) return 0;; *) return 1;; esac; }

[ "$(findmnt -n -o FSTYPE -M /android)" = ext4 ] || fail 'Android image not mounted as ext4'
has_option "$(findmnt -n -o OPTIONS -M /android)" ro || fail 'Android image is writable'
# Resolve from sysfs as this stage precedes completion of udev coldplug.
. /usr/lib/lxc-android-config/common.sh
vendor=$(find_partition_path vendor)
[ "$(readlink -f "$vendor")" = /dev/sda26 ] || fail 'vendor partition differs from audited baseline'
[ -b "$vendor" ] || fail 'vendor block device missing'
[ ! -L /android/vendor ] || fail 'unexpected vendor symlink'
[ -d /android/vendor ] || fail 'vendor mountpoint missing'
! mountpoint -q /android/vendor || fail 'unexpected pre-existing vendor mount'
log "mount vendor $vendor ro,noload,nodev,nosuid"
mount -t ext4 -o ro,noload,nodev,nosuid "$vendor" /android/vendor
has_option "$(findmnt -n -o OPTIONS -M /android/vendor)" ro || fail 'vendor mount is writable'

# All guest-writable filesystem storage is existing userdata or tmpfs.
userdata_device=$(findmnt -n -o MAJ:MIN -M /userdata)
[ -n "$userdata_device" ] || fail 'userdata mount missing'
[ "$(findmnt -n -o MAJ:MIN -T /var/lib/android-data)" = "$userdata_device" ] || fail 'Android data is outside userdata'
has_option "$(findmnt -n -o OPTIONS -M /userdata)" rw || fail 'userdata is not writable'
mkdir -p /var/lib/android-data/cache
mount --bind /var/lib/android-data /android/data
mount --bind /var/lib/android-data/cache /android/cache
mount -t tmpfs -o mode=0755,nosuid,nodev,size=16m a50-android-mnt /android/mnt
log 'EFS, SEC_EFS, CPEFS and physical cache mounts skipped'

mkdir -p /dev/binderfs
if ! mountpoint -q /dev/binderfs; then
    mount -t binder -o stats=global binder /dev/binderfs
fi
for name in binder hwbinder vndbinder; do
    [ -c "/dev/binderfs/$name" ] || fail "missing Binder context $name"
    if [ ! -e "/dev/$name" ]; then
        ln -s "/dev/binderfs/$name" "/dev/$name"
    fi
    [ "/dev/$name" -ef "/dev/binderfs/$name" ] || fail "unexpected /dev/$name"
done
mkdir -p /dev/__properties__ /dev/socket
if mountpoint -q /var/lib/lxc/android/rootfs; then
    # Halium already binds the image here before systemd. It predates the
    # vendor/data submounts above; validate and replace that single root bind.
    [ "$(findmnt -n -o MAJ:MIN -M /var/lib/lxc/android/rootfs)" = "$(findmnt -n -o MAJ:MIN -M /android)" ] || fail 'existing rootfs is not the Android image'
    [ "$(findmnt -n -o FSROOT -M /var/lib/lxc/android/rootfs)" = / ] || fail 'existing rootfs is not the image root'
    has_option "$(findmnt -n -o OPTIONS -M /var/lib/lxc/android/rootfs)" ro || fail 'existing rootfs is writable'
    [ "$(findmnt -R -r -n -o TARGET /var/lib/lxc/android/rootfs | wc -l)" -eq 1 ] || fail 'existing rootfs has unexpected submounts'
    [ "$(timeout 3 lxc-info -n android -s -H)" = STOPPED ] || fail 'Android is already running'
    umount /var/lib/lxc/android/rootfs
fi
mount --rbind /android /var/lib/lxc/android/rootfs
findmnt -R /android -o TARGET,SOURCE,FSTYPE,OPTIONS
log 'safe Android mounts ready'
