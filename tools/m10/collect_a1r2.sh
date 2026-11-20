#!/bin/sh
# M10.2 A1r2 (phone side, root over USB SSH): A1r images again; the A1r /dev/mem read() returned nothing (MMIO needs
# mmap on arm64), so this reads the CMU_DISPAUD and PMU registers with busybox devmem (mmap). Read-only. Never touches
# the ABOX core, its GIC or its SysMMU (their clocks may be stopped).
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() { printf '\nCMD:'; printf ' %s' "$@"; printf '\n'; timeout 40 "$@" 2>&1; printf 'RC=%s\n' "$?"; }
wait_up() { while read -r up rest < /proc/uptime; do [ "${up%%.*}" -ge "$1" ] && break; sleep 1; done; }
rd() { printf '%s 0x%08x %s\n' "$1" "$2" "$(busybox devmem "$2" 32 2>&1)"; }
capture uname -r
capture cat /proc/uptime
wait_up 60
printf '\nA1R2_CMU_DISPAUD\n'
C=$((0x14980000)); P=$((0x11860000))
rd PLL_LOCKTIME_PLL_AUD $((C+0x0000)); rd PLL_CON0_MUX_DISPAUD_AUD_USER $((C+0x0100)); rd PLL_CON0_MUX_DISPAUD_CPU_USER $((C+0x0120))
rd PLL_CON0_MUX_DISPAUD_DISP_USER $((C+0x0140)); rd PLL_CON0_PLL_AUD $((C+0x0160)); rd PLL_CON3_PLL_AUD $((C+0x016c))
rd MUX_CLK_AUD_BUS $((C+0x1000)); rd MUX_CLK_AUD_CPU $((C+0x1004)); rd MUX_CLK_AUD_CPU_HCH $((C+0x1008))
rd DIV_CLK_AUD_BUS $((C+0x1808)); rd DIV_CLK_AUD_CPU $((C+0x180c))
rd GAT_ABOX_ACLK $((C+0x2020)); rd GAT_ABOX_CCLK_CA7 $((C+0x2030)); rd GAT_SMMU_ABOX $((C+0x20b0)); rd GAT_SMMU_DPU $((C+0x20b4))
rd PMU_ABOX_CPU_CONFIGURATION $((P+0x2520)); rd PMU_ABOX_CPU_STATUS $((P+0x2524)); rd PMU_ABOX_CPU_OPTION $((P+0x2528))
rd PMU_PAD_RETENTION_ABOX_OPTION $((P+0x3048)); rd PMU_ABOX_MAGIC $((P+0x0814))
printf '\nA1R2_CCF\n'
capture sh -c "grep -i -E 'aud|abox|dispaud' /sys/kernel/debug/clk/clk_summary"
capture sh -c "dmesg | grep -i -E 'abox|14a50000|14920000|snd|asoc|alsa|sound' | head -40"
capture sh -c "cat /proc/asound/cards"
printf '\nA1R2_REGRESSION\n'
capture sh -c 'grep -E "^N:" /proc/bus/input/devices'
capture sh -c 'findmnt -no TARGET,OPTIONS /userdata | cut -c1-80'
capture sh -c 'head -n 1 /sys/devices/platform/148b0000.decon_f/g2b_stats; pgrep -c -x lomiri; systemctl show -p SystemState -p NFailedUnits'
capture sh -c 'nmcli -t -f DEVICE,TYPE,STATE dev; ls /sys/class/bluetooth'
capture sh -c "dmesg | grep -c -E 'Unable to handle|SError|Internal error|BUG:'"
printf '\nA1R2_DONE\n'
