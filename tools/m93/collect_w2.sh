#!/bin/sh
# M9.3 W2 (phone side, root over USB SSH): SCSC Wi-Fi on 6.18 with the stock Ubuntu Touch userspace.
# Records interfaces, driver start, rfkill and NetworkManager state; waits for NM to join the saved network
# (no credentials handled here); if not joined by 150 s, scans and records only the BSS count. Writes the
# Wi-Fi IPv4 address to /run/a50-w2/ip for the host's SSH-over-Wi-Fi test. At >= 250 s: NM disconnect and
# reconnect of the Wi-Fi device, timed. Network names and MACs are not printed (redacted on the host too).
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
redact() { sed -E 's/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/<mac>/g'; }
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
D=/run/a50-w2; mkdir -p $D
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 40 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
wlbt() { dmesg | grep -i -E 'wlbt|scsc|slsi|cfg80211|wlan0|swlan0|p2p0|rfkill|firmware|Unable to handle|SError|Internal error|BUG:' | grep -v -i -E 'mali|wlbtd' | tail -n "${1:-150}" | redact; }
wifidev() { nmcli -t -f DEVICE,TYPE dev 2>/dev/null | awk -F: '$2=="wifi"{print $1}' | head -n 1; }
nmstate() { printf 'nm: %s\n' "$(nmcli -t -f DEVICE,TYPE,STATE dev 2>/dev/null | grep -E ':wifi' | paste -sd' ')"; }
capture uname -r
capture cat /proc/uptime
capture sh -c "ip -br link | sed -E 's/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/<mac>/g'"
capture sh -c 'ls -l /sys/class/net/ | grep -E "wlan|p2p|swlan"; for n in /sys/class/net/*; do t=$(readlink $n/device/driver 2>/dev/null); [ -n "$t" ] && case "$t" in *wlbt*) echo "$n -> $t";; esac; done'
capture sh -c 'iw dev 2>&1 | grep -E "phy|Interface|type" '
capture rfkill list
capture sh -c 'cat /proc/sys/kernel/tainted; grep -E "wlbt|scsc" /proc/interrupts | tr -s " "'
nmstate
printf '\nM93_W2_PROBE_LOG\n'; wlbt 150
# wait for NetworkManager to join the saved network. Stock-created profiles are bound to interface-name=swlan0
# (stock's station interface); after 30 s without a connection, drop that binding in NetworkManager's memory only
# (nmcli --temporary: nothing written to disk, reverts on reboot) so autoconnect can use wlan0.
i=0; ip4=; unbound=no
while [ $i -lt 150 ]; do
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
printf '\nM93_W2_JOIN uptime=%s dev=%s state=%s ip_present=%s waited=%ss unbound=%s\n' "$(cut -d' ' -f1 /proc/uptime)" "$dev" "$st" "$([ -n "$ip4" ] && echo yes || echo no)" "$i" "$unbound"
nmstate
if [ -n "$ip4" ]; then echo "$ip4" > $D/ip; else
    capture sh -c "iw dev ${dev:-wlan0} scan 2>&1 | grep -c '^BSS'"
fi
capture sh -c 'iw dev 2>&1 | grep -E "Interface|type|channel" '
printf '\nM93_W2_JOIN_LOG\n'; wlbt 120
wait_up 250
if [ -n "$dev" ] && [ -n "$ip4" ]; then
    printf '\nM93_W2_RECONNECT_BEGIN uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
    capture nmcli dev disconnect "$dev"
    sleep 5; nmstate
    t0=$(cut -d' ' -f1 /proc/uptime)
    capture nmcli dev connect "$dev"
    j=0; while [ $j -lt 60 ]; do ip -4 -o addr show dev "$dev" | grep -q inet && break; sleep 1; j=$((j + 1)); done
    printf 'reconnect_from=%s address_after_s=%s\n' "$t0" "$j"
    nmstate
fi
printf '\nM93_W2_FINAL uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
capture sh -c 'grep -E "wlbt|scsc" /proc/interrupts | tr -s " "; cat /proc/sys/kernel/tainted'
capture sh -c 'cat /proc/net/dev | grep -E "wlan|p2p|swlan"'
printf 'faults=%s\n' "$(dmesg | grep -c -E 'Unable to handle|SError|Internal error|BUG:|Kernel panic')"
printf '\nM93_W2_FINAL_LOG\n'; wlbt 80
