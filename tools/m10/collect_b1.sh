#!/bin/sh
# M10.3 B1 (normal boot; A2c plus the RT5665 codec on UAIF0 with the stock board widgets/routing) (phone side, root over
# USB SSH): the RT5665 probe on i2c6 and its supplies (regulator_1v8/3v3), the codec's DAPM state, then the A2 checks
# (ABOX boot, ALSA card, control names without values, ASoC components/DAIs, deferred probes, regressions).
# Read-only: no mixer writes or reads of control values, no PCM open, no PulseAudio or EFS access.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 40 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
A=$(readlink -f /sys/bus/platform/devices/14a50000.abox)
capture uname -r
capture cat /proc/uptime
wait_up 150
printf '\nB1_ABOX\n'
capture sh -c "dmesg | grep -i -E 'abox|calliope|14a50000|14920000|14af|sysmmu|iommu|Unable to handle|SError|Internal error|BUG:|WARNING:' | grep -v -i mali | tail -n 200"
capture sh -c "ls $A; cat $A/calliope_version $A/reset_count $A/power/runtime_status 2>&1"
capture sh -c "ls -l /sys/kernel/iommu_groups/*/devices/ 2>/dev/null | grep -E '14a50000|14820000'"
capture sh -c "grep -i -E 'aud|abox' /sys/kernel/debug/clk/clk_summary | head -60"
capture sh -c "cat /proc/asound/cards; ls -l /dev/snd 2>&1"
capture sh -c "ls -l /sys/kernel/debug/abox 2>&1; head -c 4000 /sys/kernel/debug/abox/log-00 2>&1 | strings | tail -n 60"
capture sh -c "grep -E 'abox|ABox|14920000|14af1000' /proc/interrupts"
printf '\nB1_CODEC\n'
capture sh -c 'for d in /sys/bus/i2c/devices/*-001b; do echo "$d $(cat $d/name) driver=$(basename "$(readlink $d/driver)")"; done'
capture sh -c "dmesg | grep -i -E 'rt5665|13890000|i2c.*6|audio-codec|regulator_1v8|regulator_3v3|LDO4[02]' | tail -n 60"
capture sh -c 'for r in /sys/class/regulator/regulator.*; do case "$(cat $r/name)" in regulator_1v8|regulator_3v3) echo "$(cat $r/name) state=$(cat $r/state) users=$(cat $r/num_users) uV=$(cat $r/microvolts)";; esac; done'
capture sh -c 'grep -E "rt5665|regulator_[13]v[38]" /sys/kernel/debug/regulator/supply_map 2>/dev/null; cat /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | grep -B1 -A3 -E "regulator_(1v8|3v3)"'
capture sh -c 'cd /sys/kernel/debug/asoc/Exynos9610-Audio 2>/dev/null && { cat dapm_pop_time 2>/dev/null; for c in */dapm/bias_level; do echo "$c $(cat $c)"; done; cat dapm/bias_level; }'
capture sh -c 'ls /sys/kernel/debug/asoc/Exynos9610-Audio/*1b*/dapm 2>/dev/null | wc -l'
printf '\nB1_CARD\n'
capture sh -c "cat /proc/asound/cards /proc/asound/pcm /proc/asound/devices; ls -l /dev/snd; ls /proc/asound/card0"
capture sh -c 'for f in /proc/asound/card0/pcm*/info; do echo "== $f"; grep -E "^(id|name|stream|subdevices_count):" $f; done'
capture sh -c 'amixer -c 0 controls | wc -l; amixer -c 0 controls'
capture sh -c "cat /sys/kernel/debug/asoc/components; cat /sys/kernel/debug/asoc/dais"
capture sh -c "cat /sys/kernel/debug/devices_deferred"
capture sh -c "dmesg | grep -i -E 'asoc|snd|soc-|sound|Exynos9610-Audio|a50-audio|rdma|wdma|uaif|dsif|spdy|sifs|effect|compr|iommu_map' | tail -n 200"
capture sh -c "systemctl show -p ActiveState -p ConditionResult alsa-restore.service alsa-state.service sound.target"
capture sh -c "fuser -v /dev/snd/* 2>&1; ls -l /proc/*/fd 2>/dev/null | grep -c /dev/snd"
printf '\nB1_REGRESSION\n'
capture sh -c 'grep -E "^N:" /proc/bus/input/devices'
capture sh -c 'findmnt -no TARGET,OPTIONS /userdata | cut -c1-80'
capture sh -c 'head -n 1 /sys/devices/platform/148b0000.decon_f/g2b_stats; pgrep -c -x lomiri; systemctl show -p SystemState -p NFailedUnits'
capture sh -c 'nmcli -t -f DEVICE,TYPE,STATE dev; ls /sys/class/bluetooth'
capture sh -c "dmesg | grep -c -E 'Unable to handle|SError|Internal error|BUG:'"
printf '\nB1_DONE\n'
