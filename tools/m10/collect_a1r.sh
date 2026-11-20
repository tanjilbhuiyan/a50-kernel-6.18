#!/bin/sh
# M10.2 A1r (phone side, root over USB SSH): A1 kernel with the ABOX nodes disabled. Read-only: dumps the CMU_DISPAUD
# register banks (AUD PLL, muxes, dividers, gates) through /dev/mem and the clock framework's AUD tree. Never touches
# the ABOX core, its GIC or its SysMMU (their clocks may be stopped).
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 40 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
bank() { dd if=/dev/mem bs=4 skip=$(( (0x14980000 + $1) / 4 )) count=$(( $2 / 4 )) 2>/dev/null | od -An -tx4 -w16 -v |
    awk -v base=$(( $1 )) '{printf "0x%04x:", base + (NR-1)*16; for (i=1;i<=NF;i++) printf " %s", $i; printf "\n"}'; }
capture uname -r
capture cat /proc/uptime
wait_up 60
printf '\nA1R_CMU_DISPAUD\n'
for r in 0x0000:0x200 0x1000:0x40 0x1800:0x80 0x2000:0x180; do echo "== bank ${r%%:*} (${r##*:} bytes)"; bank ${r%%:*} ${r##*:}; done
printf '\nA1R_CCF\n'
capture sh -c "grep -i -E 'aud|abox|dispaud' /sys/kernel/debug/clk/clk_summary"
capture sh -c "dmesg | grep -i -E 'abox|14a50000|14920000|snd|asoc|alsa|sound' | head -40"
capture sh -c "cat /proc/asound/cards"
printf '\nA1R_REGRESSION\n'
capture sh -c 'grep -E "^N:" /proc/bus/input/devices'
capture sh -c 'findmnt -no TARGET,OPTIONS /userdata | cut -c1-80'
capture sh -c 'head -n 1 /sys/devices/platform/148b0000.decon_f/g2b_stats; pgrep -c -x lomiri; systemctl show -p SystemState -p NFailedUnits'
capture sh -c 'nmcli -t -f DEVICE,TYPE,STATE dev; ls /sys/class/bluetooth'
capture sh -c "dmesg | grep -c -E 'Unable to handle|SError|Internal error|BUG:'"
printf '\nA1R_DONE\n'
