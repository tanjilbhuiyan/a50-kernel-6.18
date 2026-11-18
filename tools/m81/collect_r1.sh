#!/bin/sh
# M8.1 R1: read-only register observation for the I2C freeze (I4 image; no I2C driver or CMU_PERI driver in the kernel).
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 15 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
capture uname -r
capture sha256sum /run/a50-r1/regread
capture sh -c 'grep -i -E "1003|1230|1383|1384|1386|1387|1389" /proc/iomem'
capture sh -c 'dmesg | grep -i -E "i2c|s3c|cmu.?peri" | head -n 30'
for t in 70 200; do
    wait_up "$t"
    printf '\nM81_R1_READ target=%s uptime=%s\n' "$t" "$(cut -d' ' -f1 /proc/uptime)"
    timeout 15 /run/a50-r1/regread; printf 'regread_rc=%s\n' "$?"
done
capture sh -c 'dmesg | grep -c -E "Unable to handle|SError|Internal error|BUG:|Kernel panic"'
