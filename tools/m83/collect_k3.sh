#!/bin/sh
# M8.3 K3: K1 image; tools/m83/k3_phone_side.sh runs detached on the phone: key capture from 40 s, per-second USB/jobs/
# state samples 50-70 s, logind/usb-moded journals, all written to /dev/kmsg at ~395 s (kept by the 420 s dump).
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 15 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
D=/run/a50-k1
chmod 700 $D/phone_side.sh
setsid nohup sh $D/phone_side.sh > $D/phone_side.log 2>&1 < /dev/null &
echo "phone_side started pid $!"
capture uname -r
capture cat /proc/uptime
capture sh -c 'cat /proc/bus/input/devices | grep -E "^N:|^H:"'
capture sh -c 'grep -i -E "gpa1|Volume|Power" /proc/interrupts'
capture sh -c 'grep -h -E "^\s*#?\s*HandlePowerKey" /etc/systemd/logind.conf /etc/systemd/logind.conf.d/*.conf /usr/lib/systemd/logind.conf.d/*.conf 2>/dev/null; systemd-inhibit --list --no-pager 2>&1 | head -n 15'
capture sh -c 'cat /sys/class/udc/*/state; ls /sys/kernel/config/usb_gadget/*/configs/*/ 2>/dev/null | head; systemctl show usb-moded -p ActiveState -p SubState'
capture sh -c 'journalctl -b --no-pager -o short-monotonic -u usb-moded | tail -n 20'
while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge 150 ] && break; sleep 2; done
capture cat $D/keys.txt $D/window.txt $D/logind.txt $D/usbmoded.txt
