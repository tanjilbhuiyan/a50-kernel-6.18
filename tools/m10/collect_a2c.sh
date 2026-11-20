#!/bin/sh
# M10.2 A2c (normal boot; A2b plus the IOMMU fault-worker and ABOX GIC-supplier fixes) (phone side, root over USB SSH):
# first Wi-Fi joins the saved network exactly as the M9 integration test did (stock profiles unbound from swlan0 in
# NetworkManager memory only, --temporary, nothing on disk) and pings the router over wlan0, with the Bluetooth
# controller state; then the A2b checks (ABOX boot, ALSA card, control names without values, regressions).
# No mixer, PCM, PulseAudio or EFS access.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 40 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
A=$(readlink -f /sys/bus/platform/devices/14a50000.abox)
capture uname -r
capture cat /proc/uptime
wifidev() { nmcli -t -f DEVICE,TYPE dev 2>/dev/null | awk -F: '$2=="wifi"{print $1}' | head -n 1; }
nmstate() { printf 'nm: %s\n' "$(nmcli -t -f DEVICE,TYPE,STATE dev 2>/dev/null | grep -E ':wifi' | paste -sd' ')"; }
printf '\nA2C_WIFI\n'
i=0; ip4=; unbound=no
while [ $i -lt 120 ]; do
    if [ $i -eq 30 ] && [ "$unbound" = no ]; then
        unbound=yes
        nmcli -t -f UUID,TYPE con show | awk -F: '$2=="802-11-wireless"{print $1}' | while read -r u; do
            b=$(nmcli -g connection.interface-name con show "$u")
            printf 'profile %s interface-name=%s -> temporary unbind rc=' "${u%%-*}" "${b:-none}"
            nmcli con modify --temporary uuid "$u" connection.interface-name "" ; echo "$?"
        done
        nmcli dev wifi rescan >/dev/null 2>&1
    fi
    dev=$(wifidev)
    if [ -n "$dev" ]; then
        st=$(nmcli -t -f DEVICE,STATE dev | awk -F: -v d="$dev" '$1==d{print $2}')
        ip4=$(ip -4 -o addr show dev "$dev" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n 1)
        [ "$st" = connected ] && [ -n "$ip4" ] && break
    fi
    sleep 1; i=$((i + 1))
done
printf 'A2C_WIFI_JOIN uptime=%s dev=%s state=%s ip_present=%s waited=%ss unbound=%s\n' "$(cut -d' ' -f1 /proc/uptime)" "$dev" "$st" "$([ -n "$ip4" ] && echo yes || echo no)" "$i" "$unbound"
nmstate
gw=$(ip -4 route show default dev "${dev:-wlan0}" 2>/dev/null | awk '{print $3; exit}')
if [ -n "$ip4" ] && [ -n "$gw" ]; then
    capture ping -c 20 -i 0.5 -W 2 -I "$dev" "$gw"
else
    printf 'A2C_WIFI_NO_PING ip=%s gw=%s\n' "$([ -n "$ip4" ] && echo yes || echo no)" "$([ -n "$gw" ] && echo yes || echo no)"
fi
capture sh -c "iw dev ${dev:-wlan0} link | grep -E 'freq|signal|tx bitrate'"
capture sh -c "bluetoothctl show 2>&1 | grep -E 'Powered|PowerState|Discoverable'; ls /sys/class/bluetooth"
capture sh -c "dmesg | grep -i -E 'scsc|slsi|wlbt' | grep -i -E 'error|fail|panic|timeout' | tail -n 20"
wait_up 150
printf '\nA2C_ABOX\n'
capture sh -c "dmesg | grep -i -E 'abox|calliope|14a50000|14920000|14af|sysmmu|iommu|Unable to handle|SError|Internal error|BUG:|WARNING:' | grep -v -i mali | tail -n 200"
capture sh -c "ls $A; cat $A/calliope_version $A/reset_count $A/power/runtime_status 2>&1"
capture sh -c "ls -l /sys/kernel/iommu_groups/*/devices/ 2>/dev/null | grep -E '14a50000|14820000'"
capture sh -c "grep -i -E 'aud|abox' /sys/kernel/debug/clk/clk_summary | head -60"
capture sh -c "cat /proc/asound/cards; ls -l /dev/snd 2>&1"
capture sh -c "ls -l /sys/kernel/debug/abox 2>&1; head -c 4000 /sys/kernel/debug/abox/log-00 2>&1 | strings | tail -n 60"
capture sh -c "grep -E 'abox|ABox|14920000|14af1000' /proc/interrupts"
printf '\nA2C_CARD\n'
capture sh -c "cat /proc/asound/cards /proc/asound/pcm /proc/asound/devices; ls -l /dev/snd; ls /proc/asound/card0"
capture sh -c 'for f in /proc/asound/card0/pcm*/info; do echo "== $f"; grep -E "^(id|name|stream|subdevices_count):" $f; done'
capture sh -c 'amixer -c 0 controls | wc -l; amixer -c 0 controls'
capture sh -c "cat /sys/kernel/debug/asoc/components; cat /sys/kernel/debug/asoc/dais"
capture sh -c "cat /sys/kernel/debug/devices_deferred"
capture sh -c "dmesg | grep -i -E 'asoc|snd|soc-|sound|Exynos9610-Audio|a50-audio|rdma|wdma|uaif|dsif|spdy|sifs|effect|compr|iommu_map' | tail -n 200"
capture sh -c "systemctl show -p ActiveState -p ConditionResult alsa-restore.service alsa-state.service sound.target"
capture sh -c "fuser -v /dev/snd/* 2>&1; ls -l /proc/*/fd 2>/dev/null | grep -c /dev/snd"
printf '\nA2C_REGRESSION\n'
capture sh -c 'grep -E "^N:" /proc/bus/input/devices'
capture sh -c 'findmnt -no TARGET,OPTIONS /userdata | cut -c1-80'
capture sh -c 'head -n 1 /sys/devices/platform/148b0000.decon_f/g2b_stats; pgrep -c -x lomiri; systemctl show -p SystemState -p NFailedUnits'
capture sh -c 'nmcli -t -f DEVICE,TYPE,STATE dev; ls /sys/class/bluetooth'
capture sh -c "dmesg | grep -c -E 'Unable to handle|SError|Internal error|BUG:'"
printf '\nA2C_DONE\n'
