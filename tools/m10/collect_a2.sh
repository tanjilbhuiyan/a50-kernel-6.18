#!/bin/sh
# M10.2 A2 (normal boot; A1l plus the ABOX DMA/interface children and the A50 sound card with dummy codecs) (phone side,
# root over USB SSH): records the ABOX boot as in A1l, then the ALSA card: cards, PCM/compress devices, control names
# (names only, no values), ASoC components/DAIs, deferred probes, and a regression snapshot. Read-only: no mixer
# writes or reads of control values, no PCM open, no PulseAudio or EFS access.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 40 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
A=$(readlink -f /sys/bus/platform/devices/14a50000.abox)
capture uname -r
capture cat /proc/uptime
wait_up 150
printf '\nA2_ABOX\n'
capture sh -c "dmesg | grep -i -E 'abox|calliope|14a50000|14920000|14af|sysmmu|iommu|Unable to handle|SError|Internal error|BUG:|WARNING:' | grep -v -i mali | tail -n 200"
capture sh -c "ls $A; cat $A/calliope_version $A/reset_count $A/power/runtime_status 2>&1"
capture sh -c "ls -l /sys/kernel/iommu_groups/*/devices/ 2>/dev/null | grep -E '14a50000|14820000'"
capture sh -c "grep -i -E 'aud|abox' /sys/kernel/debug/clk/clk_summary | head -60"
capture sh -c "cat /proc/asound/cards; ls -l /dev/snd 2>&1"
capture sh -c "ls -l /sys/kernel/debug/abox 2>&1; head -c 4000 /sys/kernel/debug/abox/log-00 2>&1 | strings | tail -n 60"
capture sh -c "grep -E 'abox|ABox|14920000|14af1000' /proc/interrupts"
printf '\nA2_CARD\n'
capture sh -c "cat /proc/asound/cards /proc/asound/pcm /proc/asound/devices; ls -l /dev/snd; ls /proc/asound/card0"
capture sh -c 'for f in /proc/asound/card0/pcm*/info; do echo "== $f"; grep -E "^(id|name|stream|subdevices_count):" $f; done'
capture sh -c 'amixer -c 0 controls | wc -l; amixer -c 0 controls'
capture sh -c "cat /sys/kernel/debug/asoc/components; cat /sys/kernel/debug/asoc/dais"
capture sh -c "cat /sys/kernel/debug/devices_deferred"
capture sh -c "dmesg | grep -i -E 'asoc|snd|soc-|sound|Exynos9610-Audio|a50-audio|rdma|wdma|uaif|dsif|spdy|sifs|effect|compr|iommu_map' | tail -n 200"
capture sh -c "systemctl show -p ActiveState -p ConditionResult alsa-restore.service alsa-state.service sound.target"
capture sh -c "fuser -v /dev/snd/* 2>&1; ls -l /proc/*/fd 2>/dev/null | grep -c /dev/snd"
printf '\nA2_REGRESSION\n'
capture sh -c 'grep -E "^N:" /proc/bus/input/devices'
capture sh -c 'findmnt -no TARGET,OPTIONS /userdata | cut -c1-80'
capture sh -c 'head -n 1 /sys/devices/platform/148b0000.decon_f/g2b_stats; pgrep -c -x lomiri; systemctl show -p SystemState -p NFailedUnits'
capture sh -c 'nmcli -t -f DEVICE,TYPE,STATE dev; ls /sys/class/bluetooth'
capture sh -c "dmesg | grep -c -E 'Unable to handle|SError|Internal error|BUG:'"
printf '\nA2_DONE\n'
