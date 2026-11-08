#!/bin/bash
# Laptop side of M3.6: record whether the A50's test gadget (1d6b:0104) enumerates.   tools/m36/host_watch.sh OUT_FILE [SECONDS]
OUT=${1:?usage: host_watch.sh OUT [SECONDS]}; T=${2:-240}; s=$(date +%s); seen=0; : > "$OUT"
while [ $(( $(date +%s)-s )) -lt "$T" ]; do
  if [ $seen = 0 ] && lsusb | grep -q "1d6b:0104"; then seen=1
    { echo "[$(date +%T)] GADGET SEEN after $(( $(date +%s)-s )) s"; lsusb | grep "1d6b:0104"; lsusb -v -d 1d6b:0104 2>/dev/null | grep -E "bcdUSB|iManufacturer|iProduct|iSerial|bInterfaceClass|MaxPower"; ls -l /dev/ttyACM* 2>&1; } >> "$OUT"; fi
  sleep 1
done
{ echo "[$(date +%T)] watcher end; gadget seen: $seen"; journalctl -k --no-pager --since "-$((T+5))s" | grep -E "1d6b|idVendor=1d6b|cdc_acm|ttyACM|A50|device descriptor read|not accepting address|unable to enumerate|over-current" | cut -c1-120 | tail -20; } >> "$OUT"
