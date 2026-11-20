#!/bin/sh
# M10.1 read-only stock audio snapshot. Runs as root on the phone (stock 4.14). Reads only: no mixer writes,
# no PulseAudio or HAL changes (ADR-0005, M0.5 rule), no EFS access.
s() { echo "### $*"; sh -c "$*" 2>&1; echo; }
s 'uname -r; cut -d" " -f1 /proc/uptime'
s 'cat /proc/asound/cards; cat /proc/asound/pcm; ls -l /dev/snd'
s 'for f in /proc/asound/card0/pcm*/info; do echo "== $f"; grep -E "^(id|name|stream|subdevices_count):" $f; done'
s 'amixer -c 0 controls | wc -l; amixer -c 0 controls'
s 'amixer -c 0 contents'
V=/vendor; [ -d $V/etc ] || V=/android/vendor
s "ls -l $V/etc | grep -i -E 'mixer|audio|tfa|abox'"
s "sha256sum $V/firmware/calliope_* $V/firmware/tfadsp.bin $V/firmware/Tfa9872.cnt $V/firmware/*AUDIO_SLSI.bin"
s 'ls /sys/devices/platform/14a50000.abox/ /sys/devices/platform/14a50000.abox/0.abox_debug 2>&1 | head -60'
s 'ls -l /dev/seiren /sys/class/nxp /sys/class/nxp/tfa_cal /sys/class/audio /sys/class/audio/earjack 2>&1'
s 'ls -l /sys/kernel/debug/abox 2>&1 | head'
s 'dmesg | grep -i -E "abox|calliope|tfa|rt5665|vogue|exynos9610-audio|asoc|snd" | head -150'
s 'for p in $(pgrep -f -x "/vendor/bin/hw/android.hardware.audio.service" ; pgrep -f audio.service); do echo "pid $p"; ls -l /proc/$p/fd 2>/dev/null | grep -E "snd|seiren|abox"; file -L /proc/$p/exe 2>/dev/null; done'
s 'systemctl list-units --all --no-legend | grep -i -E "audio|pulse|droid"'
s 'su - phablet -c "XDG_RUNTIME_DIR=/run/user/32011 pactl list short modules; XDG_RUNTIME_DIR=/run/user/32011 pactl list short sinks; XDG_RUNTIME_DIR=/run/user/32011 pactl list short sources"'
