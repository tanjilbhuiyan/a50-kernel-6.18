#!/bin/sh
# M10.3 B2h3 owner-requested replay in the same boot (uptime ~350 s): re-apply the collect_b2h3.sh mixer list, play
# /run/b2h3/tone.wav three times 2 s apart, restore the saved mixer state. Started detached by hand (setsid nohup).
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C; W=/run/b2h3; echo "replay start $(cut -d" " -f1 /proc/uptime)"
while IFS="	" read -r name want; do [ -n "$name" ] || continue; c=$(amixer -c 0 cget "name=$name" 2>/dev/null | sed -n "s/.*values=\([0-9]*\).*/\1/p" | head -n1); v=$want; i=1; while [ "$i" -lt "${c:-1}" ]; do v="$v,$want"; i=$((i+1)); done; amixer -c 0 -q cset "name=$name" "$v" || echo "FAIL $name"; done <<'EOF_MIXER'
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
DAC L2 Mux	IF1 DAC2
Mono DAC MIXL DAC L2 Switch	1
Mono MIX DAC L2 Switch	1
Mono Playback Switch	1
RECEIVER Switch	1
ABOX UAIF0 SPK	SIFS0
DAC2 Playback Volume	152
Mono Playback Volume	15
EOF_MIXER
for t in 1 2 3; do echo "replay tone $t $(cut -d" " -f1 /proc/uptime)"; echo "B2H3: replay tone $t" > /dev/kmsg; timeout 15 aplay -q -D hw:0,0 $W/tone.wav; echo "rc=$?"; sleep 2; done
alsactl -f $W/before.state restore 0; echo "replay restored rc=$? $(cut -d" " -f1 /proc/uptime)"
