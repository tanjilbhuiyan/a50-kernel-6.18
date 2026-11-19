#!/bin/sh
# M9.1 C3: after an owner-initiated stock reboot (nothing flashed), wait for phablet SSH over Wi-Fi and save the kernel
# ring (dmesg_restrict=0 on stock) before the stock touch error stream overwrites the boot-time SCSC lines.
# Read-only on the phone. Usage: capture_boot_dmesg.sh <phone-ip> <out-dir>
ip=$1; out=$2; mkdir -p "$out"
o="-o BatchMode=yes -o ConnectTimeout=2 -o ServerAliveInterval=5"
date -Is > "$out/c3-host-start.txt"
while :; do
    up=$(timeout 5 ssh $o phablet@$ip 'cut -d. -f1 /proc/uptime' 2>/dev/null)
    case "$up" in ''|*[!0-9]*) sleep 1; continue;; esac
    [ "$up" -lt 600 ] && break   # new boot only
    sleep 1
done
printf 'first_ssh %s uptime=%s\n' "$(date -Is)" "$up" >> "$out/c3-host-start.txt"
timeout 30 ssh $o phablet@$ip 'dmesg' > "$out/c3-dmesg-first.txt" 2>&1
timeout 90 ssh $o phablet@$ip 'timeout 80 dmesg -w | grep --line-buffered -v "mms_interrupt"' > "$out/c3-dmesg-follow.txt" 2>&1
timeout 30 ssh $o phablet@$ip 'dmesg' > "$out/c3-dmesg-late.txt" 2>&1
date -Is >> "$out/c3-host-start.txt"
