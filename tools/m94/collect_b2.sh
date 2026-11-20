#!/bin/sh
# M9.4 B2r (phone side, root over USB SSH): as B2, plus a btmon HCI capture of pairing/connect (raw kept private on
# the phone tmpfs, copied to the host raw dir; only a redacted protocol summary is published). S8 with the owner's Bluetooth speaker. Unblocks Bluetooth, scans up to 60 s
# (up to 180 s) for a device offering the A2DP Audio Sink service (owner puts the speaker in pairing mode; strongest RSSI wins),
# pairs (NoInputNoOutput agent), trusts, connects, plays a 3 s 440 Hz tone through PulseAudio (module-sine to the
# bluez sink), disconnects, reconnects, plays again, then removes the pairing. Addresses are redacted; names never
# printed (bluetoothctl output is filtered to status keywords).
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
R='s/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/<mac>/g'
capture() { printf '\nCMD:'; printf ' %s' "$@" | sed -E "$R"; printf '\n'; timeout 60 "$@" 2>&1 | sed -E "$R"; printf 'RC=%s\n' "$?"; }
status() { grep -a -E -i 'success|fail|error|Connected: |Paired: |Trusted: |Bonded: |not available|already|Changing|Attempting|Pairing|agent' | sed -E "$R" | sed -E 's/(Device <mac>) .*/\1/'; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
UENV="XDG_RUNTIME_DIR=/run/user/32011"
pa() { timeout 15 runuser -u phablet -- env $UENV "$@" 2>&1; }
btlog() { dmesg | grep -i -E 'scsc_bt|bluez|hci0|Bluetooth|Unable to handle|SError|Internal error|BUG:' | grep -v -i -E 'bluebinder|wlbtd' | sed -E "$R" | tail -n "${1:-60}"; }
capture uname -r
capture systemctl show bluetooth.service bluebinder.service -p Id -p LoadState -p ActiveState -p SubState -p NRestarts
capture rfkill list bluetooth
wait_up 85
printf '\nM94_B2_ON uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
rfkill block bluetooth; sleep 3   # urfkill may have restored 'on' already: start from a fresh hci0
mkdir -p /run/a50-b2; btmon -w /run/a50-b2/hci.btsnoop >/dev/null 2>&1 & BTMON=$!; sleep 1
capture rfkill unblock bluetooth
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
    printf '\nM94_B2_CLEANUP uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
    kill $BTMON 2>/dev/null; sleep 1
    printf 'btsnoop_bytes=%s\n' "$(wc -c < /run/a50-b2/hci.btsnoop 2>/dev/null)"
    printf '\nM94_B2_HCI_SUMMARY\n'
    btmon -r /run/a50-b2/hci.btsnoop 2>/dev/null | grep -a -E '^[<>@=] |L2CAP: |SDP: |Number of Completed|Status: |Reason: |Result: |MTU|Credits|ACL Data|Connect Request|Connect Response|Configure|Disconn|Command Status|Command Complete|ACL MTU|SCO MTU|ACL max|Num of|Count:|Handle:' \
        | grep -a -v -i -E 'name' | sed -E "$R" | cut -c1-140 | head -n 600

    timeout 20 bluetoothctl disconnect "$pick" 2>&1 | status
    timeout 20 bluetoothctl remove "$pick" 2>&1 | status
fi
printf '\nM94_B2_FINAL uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
capture systemctl show bluetooth.service bluebinder.service -p Id -p LoadState -p ActiveState -p SubState -p NRestarts
capture sh -c 'grep -E "wlbt|scsc" /proc/interrupts | tr -s " "'
printf 'faults=%s\n' "$(dmesg | grep -c -E 'Unable to handle|SError|Internal error|BUG:|Kernel panic')"
printf '\nM94_B2_LOG\n'; btlog 80
