#!/bin/sh
# Read only. Clock register allow-list; no I2C-controller MMIO or mixer access.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
for point in 80 150; do
    wait_up "$point"
    echo "B2C_CLOCKS uptime=$(cut -d ' ' -f 1 /proc/uptime)"
    timeout 10 /run/a50-b2-clock/read
    echo "clock_read=$?"
done
uname -r
findmnt -no TARGET,OPTIONS /userdata
head -n 1 /sys/devices/platform/148b0000.decon_f/g2b_stats
systemctl show -p SystemState -p NFailedUnits
printf 'B2C_DONE\n'
