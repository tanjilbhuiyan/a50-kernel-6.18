#!/bin/sh
# M8.4 H1: hall sensors (gpio-keys SW_LID / SW_MACHINE_COVER) and the vibrator LED (gpio-leds + transient trigger).
# The test itself runs phone-side (tools/m84/h1_phone_side.sh, detached, results to /dev/kmsg at ~395 s); this collector
# records the early state over SSH and, if SSH is still up, the phone-side files at ~290 s.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 15 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
D=/run/a50-k1
chmod 700 $D/phone_side.sh
setsid nohup sh $D/phone_side.sh > $D/phone_side.log 2>&1 < /dev/null &
echo "phone_side started pid $!"
capture uname -r
capture cat /proc/uptime
capture sh -c 'cat /proc/bus/input/devices | grep -E "^N:|^H:|^B: (EV|SW)"'
capture sh -c 'grep -i -E "Flip|Certified|gpa0|gpa1" /proc/interrupts'
capture sh -c 'ls -l /sys/class/leds/; cat /sys/class/leds/vibrator/trigger; ls /sys/class/leds/vibrator/'
capture sh -c 'grep -E -A0 "vibrator|Flip|Certified" /sys/kernel/debug/gpio'
capture sh -c 'cat /sys/kernel/debug/pinctrl/11850000.pinctrl*/pinmux-pins 2>/dev/null | grep -E "gpa0-[23]|gpa2-1"'
capture sh -c 'grep -h -E "^\s*#?\s*HandleLidSwitch" /etc/systemd/logind.conf /etc/systemd/logind.conf.d/*.conf 2>/dev/null'
while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge 290 ] && break; sleep 2; done
capture cat $D/vib.txt $D/hall.txt
capture sh -c 'journalctl -b --no-pager -o short-monotonic -u systemd-logind | tail -n 15'
