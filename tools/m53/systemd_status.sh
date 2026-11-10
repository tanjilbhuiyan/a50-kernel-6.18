#!/bin/sh
# Runs inside the new root, started just before Halium switches to systemd.
# Output goes straight to kmsg; temporary files live only in /run (tmpfs).
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 LC_ALL=C

emit() {
    printf '<6>A50STATUS: %s\n' "$*" > /dev/kmsg
}

capture() {
    emit "CMD $*"
    timeout 4 "$@" > /run/a50-status-output 2>&1
    status=$?
    while IFS= read -r line || [ -n "$line" ]; do
        emit "$line"
    done < /run/a50-status-output
    emit "RC $status"
}

emit "observer armed in new root"
: > /run/a50-status-armed

for target in 60 120 200; do
    while :; do
        read -r uptime rest < /proc/uptime
        [ "${uptime%%.*}" -ge "$target" ] && break
        sleep 2
    done
    emit "BEGIN uptime=$uptime target=$target"
    capture uname -r
    capture systemctl is-system-running
    capture systemctl --failed --no-pager --plain --no-legend
    capture systemctl list-jobs --no-pager --plain --no-legend
    capture systemctl show multi-user.target graphical.target -p Id -p ActiveState -p SubState -p Job
    capture systemctl show -p SystemState -p NFailedUnits -p NJobs
    capture findmnt -no TARGET,OPTIONS /userdata
    emit "END target=$target"
done
