#!/bin/sh
# M9.4 M9I (phone side, root over USB SSH): final M9 integration on one boot with the B2t kernel. Wi-Fi joins the
# saved network (stock profiles unbound from swlan0 in NetworkManager memory only) and writes its address for the
# host's SSH/ping/transfer; regression snapshot; then the B2t Bluetooth sequence (owner speaker: pair, connect, A2DP
# tone, reconnect, tone, unpair) while Wi-Fi stays connected; Wi-Fi state re-checked after Bluetooth audio.
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

printf '\nM9I_WIFI_JOINED\n'; nmstate
printf '\nM9E_BANDS\n'
iw reg get 2>/dev/null | grep -E '^(global|country|phy)' | head -4
iw phy phy0 channels 2>/dev/null | awk '/MHz/{f=$2+0; d=($0 ~ /disabled/); if (f>5000) {n5++; if (d) x5++} else {n2++; if (d) x2++}} END{printf "channels_2g=%d disabled_2g=%d channels_5g=%d disabled_5g=%d\n", n2, x2, n5, x5}'
iw dev wlan0 scan 2>/dev/null | awk '/^BSS /{b++} /freq:/{f=$2+0; if (f>5000) c5++; else c2++} END{printf "scan_bss=%d bss_2g=%d bss_5g=%d\n", b, c2, c5}'
iw dev wlan0 link 2>/dev/null | grep -E 'freq' | sed 's/^\s*/connected_/'
printf '\nM9E_ADDRESSES\n'
journalctl -b --no-pager -o cat -u a50-efs-addresses.service 2>/dev/null | grep -E 'a50-efs-addresses:' | tail -n 8
systemctl show a50-efs-addresses.service -p ActiveState -p Result -p ExecMainStatus | paste -sd' '
dmesg | grep -E 'MAC address from sysfs|using random local address|stack supplied Bluetooth address' | sed -E 's/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/<mac>/g' | tail -n 4
# locally administered (random) vs universal (factory) bit only; the address itself is not printed
m=$(cat /sys/class/net/wlan0/address 2>/dev/null); b=$(printf '%d' "0x${m%%:*}" 2>/dev/null)
printf 'wlan0_mac_locally_administered=%s\n' "$([ $((b & 2)) -ne 0 ] && echo yes || echo no)"
grep -c ' /dev/sda3 ' /proc/mounts | sed 's/^/efs_mounted_now=/'
printf '\nM93_W3_REGRESSION uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
capture sh -c 'grep -E "^N:" /proc/bus/input/devices'
capture sh -c 'findmnt -no TARGET,OPTIONS /userdata | cut -c1-80'
capture sh -c 'head -n 1 /sys/devices/platform/148b0000.decon_f/g2b_stats; pgrep -c -x lomiri; systemctl show -p SystemState -p NFailedUnits'

# ---- Bluetooth (B2t sequence) ----
R='s/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/<mac>/g'
capture() { printf '\nCMD:'; printf ' %s' "$@" | sed -E "$R"; printf '\n'; timeout 60 "$@" 2>&1 | sed -E "$R"; printf 'RC=%s\n' "$?"; }
status() { grep -a -E -i 'success|fail|error|Connected: |Paired: |Trusted: |Bonded: |not available|already|Changing|Attempting|Pairing|agent' | sed -E "$R" | sed -E 's/(Device <mac>) .*/\1/'; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
UENV="XDG_RUNTIME_DIR=/run/user/32011"
pa() { timeout 15 runuser -u phablet -- env $UENV "$@" 2>&1; }
btlog() { dmesg | grep -i -E 'scsc_bt|bluez|hci0|Bluetooth|Unable to handle|SError|Internal error|BUG:' | grep -v -i -E 'bluebinder|wlbtd' | sed -E "$R" | tail -n "${1:-60}"; }
wait_up 100
printf '\nM94_B2_ON uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
# Bluetooth on/off through urfkill (as the Settings indicator): raw rfkill is overridden by urfkill's saved state
# (M9E: 'Setting device 3 (BLUETOOTH) to blocked' 1 ms after a raw unblock).
urf() { gdbus call --system --dest org.freedesktop.URfkill --object-path /org/freedesktop/URfkill --method org.freedesktop.URfkill.Block 2 "$1" 2>&1; }
printf 'urfkill_block=%s\n' "$(urf true)"; sleep 3   # start from a fresh hci0
mkdir -p /run/a50-b2; btmon -w /run/a50-b2/hci.btsnoop >/dev/null 2>&1 & BTMON=$!; sleep 1
printf 'urfkill_unblock=%s\n' "$(urf false)"
i=0; while [ $i -lt 20 ]; do [ -e /sys/class/bluetooth/hci0 ] && break; sleep 1; i=$((i + 1)); done
printf 'hci0_after_s=%s\n' "$i"; sleep 3
bluetoothctl power on 2>&1 | status
printf '\nM94_B2_SCAN uptime=%s (owner: speaker in pairing mode)\n' "$(cut -d' ' -f1 /proc/uptime)"
pick=; t=0
while [ $t -lt 180 ] && [ -z "$pick" ]; do
    timeout 12 bluetoothctl --timeout 10 scan on >/dev/null 2>&1
    best=-999
    for a in $(bluetoothctl devices | awk '{print $2}'); do
        info=$(bluetoothctl info "$a" 2>/dev/null)
        echo "$info" | grep -q -E 'UUID: Audio Sink|0000110b-' || continue
        rssi=$(echo "$info" | awk '/RSSI:/{print $2; exit}' | tr -d '()' ); rssi=${rssi:--100}
        case "$rssi" in 0x*) rssi=$(printf '%d' "$rssi" 2>/dev/null || echo -100);; esac
        [ "$rssi" -gt "$best" ] 2>/dev/null && { best=$rssi; pick=$a; }
    done
    t=$((t + 12))
done
printf 'devices_seen=%s audio_sink_found=%s rssi=%s after_s=%s\n' "$(bluetoothctl devices | wc -l)" "$([ -n "$pick" ] && echo yes || echo no)" "$best" "$t"
if [ -n "$pick" ]; then
    printf '\nM94_B2_PAIR uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
    timeout 40 bluetoothctl --agent NoInputNoOutput pair "$pick" 2>&1 | status
    bluetoothctl trust "$pick" 2>&1 | status
    printf '\nM94_B2_CONNECT uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
    timeout 30 bluetoothctl connect "$pick" 2>&1 | status
    sleep 6
    bluetoothctl info "$pick" | status
    sink=$(pa pactl list short sinks | awk '/bluez/{print $2; exit}')
    printf 'bluez_sink_present=%s\n' "$([ -n "$sink" ] && echo yes || echo no)"
    pa pactl list short cards | awk '/bluez/{print "card:", $2, $3}' | sed -E "$R"
    if [ -n "$sink" ]; then
        printf '\nM94_B2_TONE1 uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
        m=$(pa pactl load-module module-sine sink="$sink" frequency=440); echo "sine_module=$m"; sleep 3
        pa pactl unload-module "$m"; echo "tone1_done"
        pa pactl list sinks | grep -A3 -E "Name: $sink" | grep -E 'State|Sample' | sed -E "$R"
    fi
    printf '\nM94_B2_RECONNECT uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
    timeout 20 bluetoothctl disconnect "$pick" 2>&1 | status; sleep 4
    timeout 30 bluetoothctl connect "$pick" 2>&1 | status; sleep 6
    sink=$(pa pactl list short sinks | awk '/bluez/{print $2; exit}')
    printf 'bluez_sink_after_reconnect=%s\n' "$([ -n "$sink" ] && echo yes || echo no)"
    if [ -n "$sink" ]; then
        printf '\nM94_B2_TONE2 uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
        m=$(pa pactl load-module module-sine sink="$sink" frequency=660); echo "sine_module=$m"; sleep 3
        pa pactl unload-module "$m"; echo "tone2_done"
    fi
    a=$(btmgmt info 2>/dev/null | awk '/addr/{print $2; exit}'); c=$(printf '%d' "0x${a%%:*}" 2>/dev/null)
    printf 'bt_addr_random_static_bits=%s\n' "$([ $((c & 192)) -eq 192 ] && echo yes || echo no)"
    printf '\nM94_B2_CLEANUP uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
    kill $BTMON 2>/dev/null; sleep 1
    printf 'btsnoop_bytes=%s\n' "$(wc -c < /run/a50-b2/hci.btsnoop 2>/dev/null)"
    printf '\nM94_B2_HCI_SUMMARY\n'
    btmon -r /run/a50-b2/hci.btsnoop 2>/dev/null | grep -a -E '^[<>@=] |L2CAP: |SDP: |Number of Completed|Status: |Reason: |Result: |MTU|Credits|ACL Data|Connect Request|Connect Response|Configure|Disconn|Command Status|Command Complete|ACL MTU|SCO MTU|ACL max|Num of|Count:|Handle:' \
        | grep -a -v -i -E 'name' | sed -E "$R" | cut -c1-140 | head -n 600

    timeout 20 bluetoothctl disconnect "$pick" 2>&1 | status
    timeout 20 bluetoothctl remove "$pick" 2>&1 | status
fi
printf 'urfkill_block_at_end=%s (keep the saved state off, as the owner had it)\n' "$(urf true)"
printf '\nM9I_WIFI_AFTER_BT\n'; nmstate; ip -4 -o addr show dev wlan0 | grep -q inet && echo wifi_address_present=yes || echo wifi_address_present=no
printf '\nM94_B2_FINAL uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
capture systemctl show bluetooth.service bluebinder.service -p Id -p LoadState -p ActiveState -p SubState -p NRestarts
capture sh -c 'grep -E "wlbt|scsc" /proc/interrupts | tr -s " "'
printf 'faults=%s\n' "$(dmesg | grep -c -E 'Unable to handle|SError|Internal error|BUG:|Kernel panic')"
printf '\nM94_B2_LOG\n'; btlog 80
