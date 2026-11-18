#!/bin/sh
# M8.3 K2: K1 image; key capture made robust against a USB-networking drop (K1 lost SSH at ~59 s). The capture runs
# detached on the phone (setsid) and its summary is written to /dev/kmsg at ~400 s, so the 420 s timed dump keeps it.
# Also records logind's power-key handling and the USB gadget state around session start. No grab, no writes to devices.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 15 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
D=/run/a50-k1
cat > $D/phone_side.sh <<'PHONE'
#!/bin/sh
D=/run/a50-k1
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
k() { echo "<6>A50K2: $*" > /dev/kmsg; }
wait_up 55
k "usb@55 $(cat /sys/class/udc/*/state 2>/dev/null | tr '\n' ' ') rndis_carrier=$(cat /sys/class/net/rndis0/carrier /sys/class/net/usb0/carrier 2>/dev/null | tr '\n' ' ')"
wait_up 65
k "usb@65 $(cat /sys/class/udc/*/state 2>/dev/null | tr '\n' ' ') rndis_carrier=$(cat /sys/class/net/rndis0/carrier /sys/class/net/usb0/carrier 2>/dev/null | tr '\n' ' ')"
wait_up 80
k "key capture start"
timeout 75 $D/evcap "gpio-keys" 60 > $D/keys.txt 2>&1
k "key capture done rc=$?"
wait_up 395
k "summary $(grep summary $D/keys.txt)"
k "key events $(grep 'type 1 code 11[456] value' $D/keys.txt | awk '{print $5\"=\"$7}' | sort | uniq -c | tr -s ' ' | tr '\n' ';')"
k "first key lines $(grep 'type 1 ' $D/keys.txt | head -n 8 | awk '{print $5\"/\"$7}' | tr '\n' ' ')"
k "usb@395 $(cat /sys/class/udc/*/state 2>/dev/null | tr '\n' ' ')"
PHONE
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
capture cat $D/keys.txt
