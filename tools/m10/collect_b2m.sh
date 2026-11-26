#!/bin/sh
# M10.3 B2m: headset and main-microphone paths, recorded the same way on stock (4.14, run over Wi-Fi by the owner-present
# session) and on 6.18 (started detached by run_b2m.sh). No headset is available and no voice is captured (owner: no
# headset, ambient only), so:
#   HEADSET: apply the stock HAL "media-headset" settings (vendor mixer_paths.xml defaults + path; make_b2h_mixer.py)
#     and record every write and read-back; no playback (jack detection is not ported; stock uses Samsung JD1/JD2).
#   MIC: apply "recording-mic" (defaults + path + gain-recording-mic; the XML's "Main Mic Switch" does not exist on
#     either kernel and stays untouched), then a 5 s ambient capture from WDMA1 (hw:0,9, S16_LE 2ch 48 kHz) with a
#     DAPM/codec-register snapshot during it. Only statistics are printed (RMS/peak dBFS, DC, HF ratio); the
#     recording is deleted on the phone and never copied.
# The mixer is saved before and restored after each part. No TFA/amplifier control, no EFS, no calibration write.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) M=618; W=/run/b2m;; 4.14*) M=stock; W=/run/b2m-stock;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 40 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
kmsg() { echo "B2M: $*" > /dev/kmsg; printf '%s uptime=%s\n' "$*" "$(cut -d' ' -f1 /proc/uptime)"; }
C=/sys/kernel/debug/asoc/Exynos9610-Audio
R=$(ls -d /sys/kernel/debug/regmap/*-001b 2>/dev/null | head -n 1)
mkdir -p "$W"; chmod 700 "$W"
# Stock autosuspends seconds after screen-off (M0.4); hold a wakelock for the stock run only.
[ "$M" = stock ] && [ -w /sys/power/wake_lock ] && echo b2m > /sys/power/wake_lock
printf 'B2M_MODE %s\n' "$M"
capture uname -r
[ "$M" = 618 ] && wait_up 120
capture cat /proc/uptime
printf '\nB2M_PRE\n'
capture sh -c 'cat /proc/asound/cards; amixer -c 0 controls | wc -l; ls -l /proc/*/fd 2>/dev/null | grep /dev/snd | sed "s/.*-> //" | sort | uniq -c'
capture sh -c "for n in 'MAINMIC Switch' 'SUBMIC Switch' 'HEADSETMIC Switch' 'HEADPHONE Switch' 'Main Mic Switch'; do printf '%s: ' \"\$n\"; amixer -c 0 cget \"name=\$n\" 2>&1 | sed -n 's/^ *: values=//p;/Cannot find/p' | head -n 1; done"
gate=ok
grep -q Exynos9610-Audio /proc/asound/cards || gate="no card"
for t in arecord amixer alsactl python3; do command -v $t >/dev/null || gate="no $t"; done
[ "$(ls -l /proc/*/fd 2>/dev/null | grep -c '/dev/snd/pcm')" = 0 ] || gate="a PCM is in use"
[ "$M" = 618 ] && dmesg | grep -q -E 'Unable to handle|SError|Internal error|BUG:' && gate="kernel fault before test"
if [ "$M" = 618 ]; then
    cal_match() { v=$(amixer -c 0 cget "name=TFA Calibration" 2>/dev/null | sed -n 's/^ *: values=//p')
        [ -n "$v" ] && [ -s /run/b2m-expect ] && [ "$v" = "$(cat /run/b2m-expect)" ]; }
    cal_match && echo "B2M_CALIBRATION matches the stock record (value not printed)" || gate="calibration differs from the stock record or unreadable"
fi
printf '\nB2M_GATE %s\n' "$gate"
apply() {  # $1 = label; stdin = NAME<TAB>VALUE lines
    fail=0; n=0
    while IFS='	' read -r name want; do
        [ -n "$name" ] || continue
        n=$((n + 1))
        info=$(amixer -c 0 cget "name=$name" 2>&1) || { echo "MISSING name=$name"; fail=$((fail + 1)); continue; }
        count=$(printf '%s\n' "$info" | sed -n 's/.*values=\([0-9]*\).*/\1/p' | head -n 1)
        val=$want; i=1; while [ "$i" -lt "${count:-1}" ]; do val="$val,$want"; i=$((i + 1)); done
        before=$(printf '%s\n' "$info" | sed -n 's/^ *: values=//p')
        amixer -c 0 -q cset "name=$name" "$val" > "$W/err" 2>&1; rc=$?
        after=$(amixer -c 0 cget "name=$name" 2>/dev/null | sed -n 's/^ *: values=//p')
        [ "$rc" = 0 ] || fail=$((fail + 1))
        echo "SET rc=$rc name=$name want=$want before=$before after=$after $(tr '\n' ' ' < "$W/err")"
    done
    printf 'B2M_%s_SUMMARY controls=%s failed=%s\n' "$1" "$n" "$fail"
}
dapm_on() { for d in $C/*/dapm $C/dapm; do for f in "$d"/*; do
    l=$(head -n 1 "$f" 2>/dev/null); case "$l" in *": On"*) echo "ON ${d#$C/} $l";; esac; done; done; }
if [ "$gate" = ok ]; then
alsactl -f "$W/before.state" store 0; printf 'B2M_SAVED rc=%s\n' "$?"
printf '\nB2M_HEADSET\n'
apply HEADSET <<'EOF_HEADSET'
ABOX Sampling Rate Mixer Min	48000
ABOX Sampling Rate Out1 Min	8000
ABOX Sampling Rate Out2 Min	8000
ABOX Sampling Rate Recp Min	8000
ABOX Sampling Rate Inmux0 Min	8000
ABOX Sampling Rate Inmux1 Min	8000
ABOX Sampling Rate Inmux2 Min	8000
ABOX Sampling Rate Inmux3 Min	8000
ABOX Sampling Rate Inmux4 Min	8000
ABOX UAIF0 width	16
ABOX UAIF0 channel	2
ABOX UAIF0 rate	48000
ABOX UAIF1 width	16
ABOX UAIF1 channel	2
ABOX UAIF1 rate	48000
ABOX UAIF2 width	16
ABOX UAIF2 channel	2
ABOX UAIF2 rate	48000
ABOX UAIF4 width	16
ABOX UAIF4 channel	2
ABOX UAIF4 rate	48000
ABOX SPDY width	16
ABOX SPDY channel	2
ABOX SPDY rate	40000
ABOX SPUS ASRC0	On
ABOX SPUS ASRC1	On
ABOX SPUS ASRC2	On
ABOX SPUS ASRC3	On
ABOX SPUS ASRC4	On
ABOX SPUS ASRC5	On
ABOX SPUS ASRC6	On
ABOX SPUS ASRC7	On
ABOX SPUS OUT0	SIFS0
ABOX SPUS OUT1	SIFS0
ABOX SPUS OUT2	SIFS0
ABOX SPUS OUT3	SIFS0
ABOX SPUS OUT4	SIFS0
ABOX SPUS OUT5	SIFS0
ABOX SPUS OUT6	SIFS2
ABOX SPUS OUT7	SIFS1
ABOX UAIF0 SPK	RESERVED
ABOX UAIF1 SPK	RESERVED
ABOX UAIF2 SPK	RESERVED
ABOX SPUM ASRC0	On
ABOX SPUM ASRC1	On
ABOX SPUM ASRC2	On
ABOX SPUM ASRC3	On
ABOX RECP PIFS0	0
ABOX RECP PIFS1	0
ABOX SIFM0	WDMA
ABOX SIFM1	WDMA
ABOX SIFM2	WDMA
ABOX SIFM3	WDMA
ABOX NSRC0	RESERVED
ABOX NSRC1	RESERVED
ABOX NSRC2	RESERVED
ABOX NSRC3	RESERVED
ABOX ERAP info DSM On	0
ABOX ERAP info Bypass On	0
ABOX ERAP info USB Rx On	0
ABOX ERAP info USB Tx On	0
ABOX Audio Mode	NORMAL
DAC L1 Source	Stereo1 DAC Mixer
DAC R1 Source	Stereo1 DAC Mixer
DAC L2 Source	Mono DAC Mixer
DAC R2 Source	Mono DAC Mixer
Stereo1 DAC MIXL DAC L1 Switch	0
Stereo1 DAC MIXL DAC R1 Switch	0
Stereo1 DAC MIXL DAC L2 Switch	0
Stereo1 DAC MIXL DAC R2 Switch	0
Stereo1 DAC MIXR DAC R1 Switch	0
Stereo1 DAC MIXR DAC L1 Switch	0
Stereo1 DAC MIXR DAC L2 Switch	0
Stereo1 DAC MIXR DAC R2 Switch	0
Mono DAC MIXL DAC L1 Switch	0
Mono DAC MIXL DAC R1 Switch	0
Mono DAC MIXL DAC L2 Switch	0
Mono DAC MIXL DAC R2 Switch	0
Mono DAC MIXR DAC L1 Switch	0
Mono DAC MIXR DAC R1 Switch	0
Mono DAC MIXR DAC L2 Switch	0
Mono DAC MIXR DAC R2 Switch	0
RECMIX1L BST1 Switch	0
RECMIX1R BST1 Switch	0
RECMIX1L BST3 Switch	0
RECMIX1R BST3 Switch	0
RECMIX1L BST4 Switch	0
RECMIX1R BST4 Switch	0
HEADPHONE Switch	0
RECEIVER Switch	0
Mono Playback Switch	0
HPO Playback Switch	0
Mono MIX DAC L2 Switch	0
DAC L1 Mux	IF1 DAC1
DAC R1 Mux	IF1 DAC1
DAC1 MIXL DAC1 Switch	1
DAC1 MIXR DAC1 Switch	1
DAC L2 Mux	IF1 DAC2
Stereo1 ADC L Mux	ADC1 L
Stereo1 ADC R Mux	ADC1 R
Stereo1 ADC L1 Mux	ADC
Stereo1 ADC R1 Mux	ADC
Stereo1 ADC MIXL ADC1 Switch	1
Stereo1 ADC MIXR ADC1 Switch	1
ABOX Wakelock	0
ABOX UAIF0 SPK	SIFS0
Stereo1 DAC MIXL DAC L1 Switch	1
Stereo1 DAC MIXR DAC R1 Switch	1
HEADPHONE Switch	1
DAC1 Playback Volume	174
Headphone Playback Volume	28
HPO Playback Switch	1
EOF_HEADSET
printf 'B2M_HEADSET_DAPM (no stream)\n'; dapm_on | grep -i -E 'hp|headphone|dac|uaif0' | head -n 40
alsactl -f "$W/before.state" restore 0; printf 'B2M_HEADSET_RESTORED rc=%s\n' "$?"
printf '\nB2M_MIC\n'
apply MIC <<'EOF_MIC'
ABOX Sampling Rate Mixer Min	48000
ABOX Sampling Rate Out1 Min	8000
ABOX Sampling Rate Out2 Min	8000
ABOX Sampling Rate Recp Min	8000
ABOX Sampling Rate Inmux0 Min	8000
ABOX Sampling Rate Inmux1 Min	8000
ABOX Sampling Rate Inmux2 Min	8000
ABOX Sampling Rate Inmux3 Min	8000
ABOX Sampling Rate Inmux4 Min	8000
ABOX UAIF0 width	16
ABOX UAIF0 channel	2
ABOX UAIF0 rate	48000
ABOX UAIF1 width	16
ABOX UAIF1 channel	2
ABOX UAIF1 rate	48000
ABOX UAIF2 width	16
ABOX UAIF2 channel	2
ABOX UAIF2 rate	48000
ABOX UAIF4 width	16
ABOX UAIF4 channel	2
ABOX UAIF4 rate	48000
ABOX SPDY width	16
ABOX SPDY channel	2
ABOX SPDY rate	40000
ABOX SPUS ASRC0	On
ABOX SPUS ASRC1	On
ABOX SPUS ASRC2	On
ABOX SPUS ASRC3	On
ABOX SPUS ASRC4	On
ABOX SPUS ASRC5	On
ABOX SPUS ASRC6	On
ABOX SPUS ASRC7	On
ABOX SPUS OUT0	SIFS0
ABOX SPUS OUT1	SIFS0
ABOX SPUS OUT2	SIFS0
ABOX SPUS OUT3	SIFS0
ABOX SPUS OUT4	SIFS0
ABOX SPUS OUT5	SIFS0
ABOX SPUS OUT6	SIFS2
ABOX SPUS OUT7	SIFS1
ABOX UAIF0 SPK	RESERVED
ABOX UAIF1 SPK	RESERVED
ABOX UAIF2 SPK	RESERVED
ABOX SPUM ASRC0	On
ABOX SPUM ASRC1	On
ABOX SPUM ASRC2	On
ABOX SPUM ASRC3	On
ABOX RECP PIFS0	0
ABOX RECP PIFS1	0
ABOX SIFM0	WDMA
ABOX SIFM1	WDMA
ABOX SIFM2	WDMA
ABOX SIFM3	WDMA
ABOX NSRC0	RESERVED
ABOX NSRC1	RESERVED
ABOX NSRC2	RESERVED
ABOX NSRC3	RESERVED
ABOX ERAP info DSM On	0
ABOX ERAP info Bypass On	0
ABOX ERAP info USB Rx On	0
ABOX ERAP info USB Tx On	0
ABOX Audio Mode	NORMAL
DAC L1 Source	Stereo1 DAC Mixer
DAC R1 Source	Stereo1 DAC Mixer
DAC L2 Source	Mono DAC Mixer
DAC R2 Source	Mono DAC Mixer
Stereo1 DAC MIXL DAC L1 Switch	0
Stereo1 DAC MIXL DAC R1 Switch	0
Stereo1 DAC MIXL DAC L2 Switch	0
Stereo1 DAC MIXL DAC R2 Switch	0
Stereo1 DAC MIXR DAC R1 Switch	0
Stereo1 DAC MIXR DAC L1 Switch	0
Stereo1 DAC MIXR DAC L2 Switch	0
Stereo1 DAC MIXR DAC R2 Switch	0
Mono DAC MIXL DAC L1 Switch	0
Mono DAC MIXL DAC R1 Switch	0
Mono DAC MIXL DAC L2 Switch	0
Mono DAC MIXL DAC R2 Switch	0
Mono DAC MIXR DAC L1 Switch	0
Mono DAC MIXR DAC R1 Switch	0
Mono DAC MIXR DAC L2 Switch	0
Mono DAC MIXR DAC R2 Switch	0
RECMIX1L BST1 Switch	0
RECMIX1R BST1 Switch	0
RECMIX1L BST3 Switch	0
RECMIX1R BST3 Switch	0
RECMIX1L BST4 Switch	0
RECMIX1R BST4 Switch	0
HEADPHONE Switch	0
RECEIVER Switch	0
Mono Playback Switch	0
HPO Playback Switch	0
Mono MIX DAC L2 Switch	0
DAC L1 Mux	IF1 DAC1
DAC R1 Mux	IF1 DAC1
DAC1 MIXL DAC1 Switch	1
DAC1 MIXR DAC1 Switch	1
DAC L2 Mux	IF1 DAC2
Stereo1 ADC L Mux	ADC1 L
Stereo1 ADC R Mux	ADC1 R
Stereo1 ADC L1 Mux	ADC
Stereo1 ADC R1 Mux	ADC
Stereo1 ADC MIXL ADC1 Switch	1
Stereo1 ADC MIXR ADC1 Switch	1
ABOX Wakelock	0
ABOX NSRC0	UAIF0
ABOX SIFM0	WDMA
RECMIX1L BST3 Switch	1
RECMIX1R BST3 Switch	1
Stereo1 ADC L Mux	ADC1 L
Stereo1 ADC R Mux	ADC1 R
Stereo1 ADC L1 Mux	ADC
Stereo1 ADC R1 Mux	ADC
Stereo1 ADC MIXL ADC1 Switch	1
Stereo1 ADC MIXR ADC1 Switch	1
IN3 Boost Volume	37
STO1 ADC Capture Volume	38
EOF_MIC
[ "$M" = 618 ] && wait_up 180
kmsg "mic capture start"
( sleep 2
  printf '\nB2M_MIC_SNAPSHOT uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
  dapm_on
  head -n 8 /proc/asound/card0/pcm9c/sub0/status 2>&1
  printf 'B2M_CODEC_REGS\n'; cat "$R/registers" 2>&1
  printf 'B2M_SNAPSHOT_END\n' ) > "$W/snap.txt" 2>&1 &
timeout 15 arecord -D hw:0,9 -f S16_LE -c 2 -r 48000 -d 5 -t wav "$W/mic.wav" > "$W/arecord.txt" 2>&1; rc=$?
wait
kmsg "mic capture end rc=$rc"
cat "$W/arecord.txt"
python3 - "$W/mic.wav" <<'EOF_STATS'
import math, struct, sys, wave
w = wave.open(sys.argv[1], 'rb'); n = w.getnframes(); ch = w.getnchannels(); raw = w.readframes(n)
s = struct.unpack('<%dh' % (len(raw) // 2), raw)
print('B2M_MIC_FRAMES %d rate %d channels %d' % (n, w.getframerate(), ch))
for c in range(ch):
    x = s[c::ch][4800:]                                  # skip the first 0.1 s (start-up transient)
    m = sum(x) / len(x); e = sum((v - m) ** 2 for v in x) / len(x)
    d = sum((x[i] - x[i - 1]) ** 2 for i in range(1, len(x))) / (len(x) - 1)
    pk = max(abs(v) for v in x); z = sum(1 for v in x if v == 0) / len(x)
    db = lambda p: 10 * math.log10(p / 32768.0 ** 2) if p > 0 else float('-inf')
    print('B2M_MIC_CH%d rms_dbfs=%.1f peak_dbfs=%.1f dc=%.1f hf_ratio=%.2f zero_frac=%.3f' % (
        c, db(e), 20 * math.log10(pk / 32768.0) if pk else float('-inf'), m, d / e if e else 0, z))
print('(hf_ratio = mean squared first difference / variance: ~2 for white hiss, ~0.02 for a 1 kHz tone, lower for room/voice)')
EOF_STATS
rm -f "$W/mic.wav"
cat "$W/snap.txt"
alsactl -f "$W/before.state" restore 0; printf 'B2M_MIC_RESTORED rc=%s\n' "$?"
[ "$M" = 618 ] && { cal_match && echo "B2M_CALIBRATION_AFTER matches the stock record" || echo "B2M_CALIBRATION_AFTER DIFFERS or unreadable"; }
fi
printf '\nB2M_AFTER\n'
capture sh -c 'ls -l /proc/*/fd 2>/dev/null | grep -c /dev/snd/pcm'
capture sh -c "dmesg | grep -c -E 'Unable to handle|SError|Internal error|BUG:'"
[ "$M" = 618 ] && capture sh -c "dmesg | grep -i -E 'B2M|abox|uaif|wdma|rt5665|asoc|fault|Unable to handle|SError|BUG:|WARNING:' | grep -v -i mali | tail -n 120"
rm -f /run/b2m-expect
[ "$M" = stock ] && [ -w /sys/power/wake_unlock ] && echo b2m > /sys/power/wake_unlock
printf '\nB2M_DONE\n'
