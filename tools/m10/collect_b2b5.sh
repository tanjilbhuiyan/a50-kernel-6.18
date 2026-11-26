#!/bin/sh
# M10.3 B2b5: capture-only rerun of the unchanged B2b images (B2b crashed the ABOX firmware on the first TFA DSP message).
# Same gates, calibration check and stock media-speaker sequence as collect_b2br.sh, but ONE tone, and the ABOX firmware
# log (/sys/kernel/debug/abox/log-00) read before the tone and after it. Numbers on impedance/calibration lines masked.
# M10.3 B2b: first supervised loudspeaker tone (B2h3 image + TFA9872 calibration gate; phone side, root; started
# detached by run_b2b.sh, log in /run/b2b5-live.txt). Gates first; if any fails, no sound:
#   card/tools/DSP/SysMMU/no fault/no /dev/snd user (as B2h), TFA bring-up status probe_only=0 playback_gate=1
#   mtpex=1 rdc_present=1, and the TFA Calibration reading equal to the private stock record in /run/b2b5-expect
#   (compared here, never printed).
# Then the stock HAL settings for "media-speaker" (top-level defaults of the vendor mixer_paths.xml + path
# media-speaker; gain-media-speaker is empty; tools/m10/make_b2h_mixer.py media-speaker), each read back. Per tone,
# as the stock HAL: start RDMA7 playback and WDMA3/WDMA4 capture (S16_LE 2ch 48 kHz, period 480, buffer 1920), then
# RDMA0 plays a 4 s 1 kHz tone at -36 dBFS from rtplay.py, with RDMA7/WDMA3/WDMA4 started like the stock HAL (no I/O).
# The ABOX firmware runs the speaker protection (ERAP DSM) and feeds RDMA7 -> SIFS1 -> UAIF2 -> TFA9872.
# Afterwards: calibration re-read (must still match), mixer restored. No EFS, no calibration, no MTP write.
R=$(ls -d /sys/kernel/debug/regmap/*-001b 2>/dev/null | head -n 1)
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 40 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
kmsg() { echo "B2B5: $*" > /dev/kmsg; printf '%s uptime=%s\n' "$*" "$(cut -d' ' -f1 /proc/uptime)"; }
A=$(readlink -f /sys/bus/platform/devices/14a50000.abox)
C=/sys/kernel/debug/asoc/Exynos9610-Audio
W=/run/b2b5
mkdir -p "$W"; chmod 700 "$W"
capture uname -r
capture cat /proc/uptime
wait_up 120
printf '\nB2B5_PRE\n'
capture sh -c "cat $A/calliope_version $A/reset_count $A/power/runtime_status 2>&1"
capture sh -c "grep -E 'abox|ABox|14920000|14af1000' /proc/interrupts"
capture sh -c 'cat /sys/module/snd_soc_tfa98xx/parameters/probe_only'
capture sh -c 'cat /proc/asound/cards; amixer -c 0 controls | wc -l; ls -l /proc/*/fd 2>/dev/null | grep -c /dev/snd'
capture sh -c 'command -v aplay amixer alsactl python3; aplay --version'
capture sh -c "ls $C; for b in $C/*/dapm/bias_level; do echo \"\$b \$(cat \$b)\"; done"
capture sh -c "echo regmap=$R; command grep -E '^0*7d:' $R/registers"
capture sh -c "dmesg | grep -a -E 'audif clock|bclk=|Set AUD_PLL'"
capture sh -c "grep -i -E 'aud_pll|aud_audif|aud_uaif|aud_dsif' /sys/kernel/debug/clk/clk_summary"
T=$(ls -d /sys/bus/i2c/devices/*-0034 2>/dev/null | head -n 1)
capture sh -c "cat $T/bringup_status; dmesg | grep -a -E 'calibration gate|probe-only|TFA9872 detected|TFA external DSP'"
gate=ok
grep -q Exynos9610-Audio /proc/asound/cards || gate="no card"
for t in aplay amixer alsactl python3; do command -v $t >/dev/null || gate="no $t"; done
cat "$A/calliope_version" >/dev/null 2>&1 || gate="dsp version unreadable"
[ "$(ls -l /proc/*/fd 2>/dev/null | grep -c /dev/snd)" = 0 ] || gate="/dev/snd in use"
sysmmu=$(awk '/14920000/ {for (i=2;i<=9;i++) s+=$i} END {print s+0}' /proc/interrupts)
[ "${sysmmu:-0}" = 0 ] || gate="abox sysmmu irqs $sysmmu"
dmesg | grep -q -E 'Unable to handle|SError|Internal error|BUG:' && gate="kernel fault before tone"
if [ -r "$R/registers" ]; then
    grep -q '^0*7d: 0101$' "$R/registers" || gate="codec 0x7d not 0101"
else
    echo "B2B5_NOTE codec regmap debugfs unavailable; 0x7d not checked"
fi
st=$(cat "$T/bringup_status" 2>/dev/null)
for w in probe_only=0 playback_gate=1 mtpex=1 rdc_present=1; do
    case " $st " in *" $w "*) ;; *) gate="tfa status lacks $w";; esac
done
cal_match() { v=$(amixer -c 0 cget "name=TFA Calibration" 2>/dev/null | sed -n 's/^ *: values=//p')
    [ -n "$v" ] && [ -s /run/b2b5-expect ] && [ "$v" = "$(cat /run/b2b5-expect)" ]; }
cal_match && echo "B2B5_CALIBRATION matches the stock record (value not printed)" || gate="calibration differs from the stock record or unreadable"
fwlog() { printf '\nB2B5_FWLOG %s uptime=%s\n' "$1" "$(cut -d' ' -f1 /proc/uptime)"
    timeout 5 cat /sys/kernel/debug/abox/log-00 2>&1 | tr -cd '\11\12\40-\176' |
        awk '{ if (tolower($0) ~ /re25|imped|ohm|calib/) gsub(/[0-9][0-9][0-9]+/, "<N>"); print }' | tail -n "$2"; }
printf '\nB2B5_GATE %s\n' "$gate"
if [ "$gate" = ok ]; then
fwlog before-tone 120
printf 'B2B5_TIMER_RES %s\n' "$(grep -m1 -E '^ *\.resolution|resolution:' /proc/timer_list 2>&1)"
printf 'B2B5_EXTBIN %s\n' "$(dmesg | grep -a -E 'tfadsp\.bin' | tail -n 3 | tr '\n' ';')"
alsactl -f "$W/before.state" store 0; printf 'B2B5_SAVED rc=%s\n' "$?"
printf '\nB2B5_MIXER\n'
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
done <<'EOF_MIXER'
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
ABOX ERAP info DSM On	1
ABOX UAIF0 SPK	SIFS0
ABOX NSRC2	UAIF4
ABOX SIFM2	WDMA
ABOX NSRC3	UAIF2
ABOX SIFM3	WDMA
ABOX SPUS OUT7	SIFS1
ABOX SIFS1	SPUS OUT7
ABOX UAIF2 SPK	SIFS1
EOF_MIXER
printf 'B2B5_MIXER_SUMMARY controls=%s failed=%s\n' "$n" "$fail"
printf '\nB2B5_TONE\n'
python3 - "$W/tone.wav" <<'EOF_TONE'
import math, struct, sys, wave
rate, secs, freq, amp, fade = 48000, 4.0, 1000.0, 10 ** (-36 / 20), 0.02
n = int(rate * secs); f = int(rate * fade); frames = bytearray()
for i in range(n):
    g = 1.0
    if i < f: g = 0.5 - 0.5 * math.cos(math.pi * i / f)
    elif i >= n - f: g = 0.5 - 0.5 * math.cos(math.pi * (n - 1 - i) / f)
    s = int(round(32767 * amp * g * math.sin(2 * math.pi * freq * i / rate)))
    frames += struct.pack('<hh', s, s)
w = wave.open(sys.argv[1], 'wb'); w.setnchannels(2); w.setsampwidth(2); w.setframerate(rate); w.writeframes(bytes(frames)); w.close()
print('tone', sys.argv[1], n, 'frames peak', int(32767 * amp))
EOF_TONE
printf 'B2B5_WAV rc=%s size=%s\n' "$?" "$(wc -c < "$W/tone.wav")"
for t in 1; do
    wait_up $((160 + t * 20))
    kmsg "tone $t start"
    if [ "$t" = 1 ]; then
        ( sleep 1
          printf '\nB2B5_SNAPSHOT uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
          for d in $C/tfa98xx*/dapm $C/rt5665*/dapm $C/dapm; do for f in "$d"/*; do
              l=$(head -n 1 "$f" 2>/dev/null); case "$l" in *": On"*) echo "ON ${d#$C/} $l";; esac
          done; done
          printf 'B2B5_DAPM_DONE uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
          for p in pcm0p pcm7p pcm11c pcm12c; do echo "== $p"; head -n 8 /proc/asound/card0/$p/sub0/status 2>&1; done
          cat "$T/bringup_status"
          dmesg | grep -a -i -E 'tfa|erap|dsm|uaif2|14a50520' | grep -v -i -E 'calib.*[0-9]{4}' | tail -n 60
          cat "$R/registers" > "$W/regs-tone.txt" 2>&1
          printf 'B2B5_REGS_DONE uptime=%s\n' "$(cut -d' ' -f1 /proc/uptime)"
          grep -i -E 'uaif0|aud_pll|fout_aud|aud_audif' /sys/kernel/debug/clk/clk_summary
          printf 'B2B5_SNAPSHOT_END\n' ) > "$W/snap.txt" 2>&1 &
    fi
    # B2b4: aplay/arecord on the realtime streams waited for pointer progress that never comes (ABOX consumes them
    # internally; stock hw_ptr/appl_ptr stay 0) and 6.18 ALSA returns EIO after 100 ms, which stopped the speaker path.
    # Like the stock HAL: start RDMA7/WDMA3/WDMA4 with stop_threshold = boundary and never read/write them, then play
    # the tone on RDMA0 at once (stock order, all in one process).
    cat > "$W/rtplay.py" <<'EOF_RT'
import ctypes as C, sys, time, wave
a = C.CDLL('libasound.so.2')
a.snd_pcm_open.argtypes = [C.POINTER(C.c_void_p), C.c_char_p, C.c_int, C.c_int]
a.snd_pcm_set_params.argtypes = [C.c_void_p, C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_int, C.c_uint]
for f in ('snd_pcm_start', 'snd_pcm_drain', 'snd_pcm_drop', 'snd_pcm_close', 'snd_pcm_state', 'snd_pcm_prepare'):
    getattr(a, f).argtypes = [C.c_void_p]
a.snd_pcm_writei.argtypes = [C.c_void_p, C.c_void_p, C.c_ulong]; a.snd_pcm_writei.restype = C.c_long
a.snd_pcm_recover.argtypes = [C.c_void_p, C.c_int, C.c_int]
a.snd_pcm_sw_params_sizeof.restype = C.c_size_t
a.snd_pcm_sw_params_current.argtypes = [C.c_void_p, C.c_void_p]
a.snd_pcm_sw_params_get_boundary.argtypes = [C.c_void_p, C.POINTER(C.c_ulong)]
a.snd_pcm_sw_params_set_stop_threshold.argtypes = [C.c_void_p, C.c_void_p, C.c_ulong]
a.snd_pcm_sw_params_set_start_threshold.argtypes = [C.c_void_p, C.c_void_p, C.c_ulong]
a.snd_pcm_sw_params.argtypes = [C.c_void_p, C.c_void_p]
def chk(r, what):
    if r < 0: raise SystemExit('%s failed: %d' % (what, r))
    return r
def pcm(dev, stream, latency_us):
    h = C.c_void_p(); chk(a.snd_pcm_open(C.byref(h), dev.encode(), stream, 0), 'open ' + dev)
    chk(a.snd_pcm_set_params(h, 2, 3, 2, 48000, 0, latency_us), 'set_params ' + dev)   # S16_LE, RW_INTERLEAVED
    return h
def realtime(dev, stream):
    h = pcm(dev, stream, 40000)                       # 1920-frame buffer, 480-frame periods (stock)
    sw = C.create_string_buffer(a.snd_pcm_sw_params_sizeof())
    chk(a.snd_pcm_sw_params_current(h, sw), 'sw_current ' + dev)
    b = C.c_ulong(); chk(a.snd_pcm_sw_params_get_boundary(sw, C.byref(b)), 'boundary ' + dev)
    chk(a.snd_pcm_sw_params_set_stop_threshold(h, sw, b.value), 'stop_threshold ' + dev)
    chk(a.snd_pcm_sw_params_set_start_threshold(h, sw, b.value), 'start_threshold ' + dev)
    chk(a.snd_pcm_sw_params(h, sw), 'sw_params ' + dev)
    chk(a.snd_pcm_start(h), 'start ' + dev)
    return h
t0 = time.monotonic()
side = [realtime('hw:0,7', 0), realtime('hw:0,11', 1), realtime('hw:0,12', 1)]
print('realtime streams started in %.1f ms' % ((time.monotonic() - t0) * 1000), flush=True)
w = wave.open(sys.argv[1], 'rb'); h0 = pcm('hw:0,0', 0, 80000)   # 3840-frame buffer, 960-frame periods (stock)
print('RDMA0 opened at %.1f ms' % ((time.monotonic() - t0) * 1000), flush=True)
total = 0
while True:
    d = w.readframes(960)
    if not d: break
    n = len(d) // 4; off = 0
    while off < n:
        r = a.snd_pcm_writei(h0, C.c_char_p(d[off * 4:]), n - off)
        if r < 0:
            print('writei error %d at frame %d' % (r, total + off), flush=True); chk(a.snd_pcm_recover(h0, int(r), 0), 'recover')
            continue
        off += r
    total += n
a.snd_pcm_drain(h0)
states = [a.snd_pcm_state(h) for h in side]
print('tone frames=%d; realtime states at end=%s (3=RUNNING); %.1f s' % (total, states, time.monotonic() - t0), flush=True)
a.snd_pcm_close(h0)
for h in side: a.snd_pcm_drop(h); a.snd_pcm_close(h)
sys.exit(0 if states == [3, 3, 3] else 2)
EOF_RT
    timeout 20 python3 "$W/rtplay.py" "$W/tone.wav" > "$W/aplay.txt" 2>&1; rc=$?
    kmsg "tone $t end rc=$rc"
    [ "$t" = 1 ] && tail -n 20 "$W/aplay.txt"
    if [ "$t" = 1 ]; then
        printf 'B2B5_CLOCKS\n'; dmesg | grep -a -E 'abox-uaif: (audif clock|rate=)' | tail -n 6
    fi
    wait
done
sleep 1
fwlog after-tone 600
cat "$W/snap.txt"
printf '\nB2B5_CODEC_REGS_DURING_TONE\n'
cat "$W/regs-tone.txt"
cal_match && echo "B2B5_CALIBRATION_AFTER matches the stock record" || echo "B2B5_CALIBRATION_AFTER DIFFERS or unreadable"
printf '\nB2B5_RESTORE\n'
alsactl -f "$W/before.state" restore 0; printf 'B2B5_RESTORED rc=%s\n' "$?"
fi
printf '\nB2B5_AFTER\n'
capture sh -c "dmesg | grep -i -E 'B2B5|abox|uaif|rdma|sifs|rt5665|pll|asoc|snd|iommu|sysmmu|fault|Unable to handle|SError|Internal error|BUG:|WARNING:' | grep -v -i mali | tail -n 250"
capture sh -c "cat $A/calliope_version $A/reset_count $A/power/runtime_status 2>&1"
capture sh -c "grep -E 'abox|ABox|14920000|14af1000' /proc/interrupts"
capture sh -c 'ls -l /proc/*/fd 2>/dev/null | grep -c /dev/snd'
printf '\nB2B5_REGRESSION\n'
capture sh -c 'grep -E "^N:" /proc/bus/input/devices'
capture sh -c 'findmnt -no TARGET,OPTIONS /userdata | cut -c1-80'
capture sh -c 'head -n 1 /sys/devices/platform/148b0000.decon_f/g2b_stats; pgrep -c -x lomiri; systemctl show -p SystemState -p NFailedUnits'
capture sh -c 'nmcli -t -f DEVICE,TYPE,STATE dev; ls /sys/class/bluetooth'
capture sh -c "dmesg | grep -c -E 'Unable to handle|SError|Internal error|BUG:'"
rm -f /run/b2b5-expect
printf '\nB2B5_DONE\n'
