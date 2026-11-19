#!/bin/sh
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
D=/run/a50-m85-s1
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
wait_up 50
(
    for round in 1 2 3; do
        echo "ROUND $round uptime=$(cut -d' ' -f1 /proc/uptime)"
        { timeout 270 "$D/evcap" MELFAS 260; echo "producer_rc=$?"; } | awk '!/ type / { sub(/ x_range=.*/, ""); print; fflush() }'
    done
) > "$D/touch.txt" 2>&1 &
(
    for round in 1 2 3; do
        echo "ROUND $round uptime=$(cut -d' ' -f1 /proc/uptime)"
        timeout 270 "$D/evcap" gpio-keys 260
        echo "capture_rc=$?"
    done
) > "$D/keys.txt" 2>&1 &
wait
wait_up 885
while IFS= read -r line; do printf '<6>A50M85_INPUT: touch %s\n' "$line" > /dev/kmsg; done < "$D/touch.txt"
grep 'type 1 code' "$D/keys.txt" | head -n 45 | while IFS= read -r line; do printf '<6>A50M85_INPUT: keys %s\n' "$line" > /dev/kmsg; done
printf '<6>A50M85_INPUT: END (hall events not exercised: no magnet available)\n' > /dev/kmsg
