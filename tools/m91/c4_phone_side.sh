#!/bin/sh
# M9.1 C4 (phone side, phablet, no root): restart the stock WLBT chip by an rfkill Wi-Fi block/unblock and stream the
# kernel log with the stock touch error lines filtered out, so the SCSC start-up sequence survives the 1 MB ring.
# Always unblocks Wi-Fi on exit. Output: /tmp/m91-c4/. Run detached (setsid) because SSH over Wi-Fi drops meanwhile.
O=/tmp/m91-c4; mkdir -p $O
snap() { { echo "## $1 $(cut -d' ' -f1 /proc/uptime)"; rfkill list; grep -E 'scsc|wlbt' /proc/interrupts | tr -s ' ';
           for n in wlan0 swlan0 p2p0; do echo "$n $(cat /sys/class/net/$n/operstate 2>&1)"; done;
           ls /sys/bus/platform/drivers/scsc_wlbt; } >> $O/state.txt 2>&1; }
trap 'rfkill unblock wlan' EXIT INT TERM
dmesg -w | grep --line-buffered -v 'mms_interrupt' > $O/follow.txt 2>&1 &
fp=$!
sleep 2; snap before
rfkill block wlan; echo "block_rc=$?" >> $O/state.txt
sleep 15; snap blocked
rfkill unblock wlan; echo "unblock_rc=$?" >> $O/state.txt
sleep 45; snap after
kill $fp 2>/dev/null; pkill -f 'dmesg -w' 2>/dev/null
echo done > $O/done
