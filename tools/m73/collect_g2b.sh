#!/bin/sh
# G2 repeat using the installed libhybris clients; no persistent setup changes.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() {
    printf '\nCMD:'; printf ' %s' "$@"; printf '\n'
    timeout 10 "$@" 2>&1
    printf 'RC=%s\n' "$?"
}
stats=/sys/devices/platform/148b0000.decon_f/g2b_stats
capture uname -r
capture cat /proc/uptime
capture cat /sys/module/mali_kbase/parameters/a50_g1_probe_only
capture ls -l /dev/mali0 /dev/fb0
capture sha256sum /usr/bin/test_egl /usr/bin/test_glesv2
capture cat "$stats"
capture /bin/sh -c 'grep -E "mali|decon" /proc/interrupts'
if [ "$(cat /sys/module/mali_kbase/parameters/a50_g1_probe_only 2>/dev/null)" != N ] ||
   [ ! -c /dev/mali0 ] || [ ! -r "$stats" ]; then
    echo 'G2b prerequisites unavailable; skipping GLES clients'
    capture dmesg
    exit 2
fi
printf '\nG2B_EGL_BEGIN '; date -Is
timeout -k 5 12 /bin/bash -lc '
    printf "GLIBC_TUNABLES=%s\n" "${GLIBC_TUNABLES-}"
    case ":${GLIBC_TUNABLES-}:" in
        *:glibc.rtld.optional_static_tls=4096:*) ;; *) exit 78;;
    esac
    exec /usr/bin/test_egl
'
printf 'G2B_EGL_RC=%s\n' "$?"
capture cat "$stats"
printf '\nG2B_GLES_BEGIN '; date -Is
timeout -k 5 30 /bin/bash -lc '
    printf "GLIBC_TUNABLES=%s\n" "${GLIBC_TUNABLES-}"
    case ":${GLIBC_TUNABLES-}:" in
        *:glibc.rtld.optional_static_tls=4096:*) ;; *) exit 78;;
    esac
    exec /usr/bin/test_glesv2
'
printf 'G2B_GLES_RC=%s\n' "$?"
printf 'G2B_POST_CANCEL '; date -Is
sleep 3
capture cat /proc/uptime
capture cat "$stats"
capture /bin/sh -c 'grep -E "mali|decon" /proc/interrupts'
capture ps -eo pid,stat,wchan:32,comm
capture systemctl show -p SystemState -p NFailedUnits -p NJobs
capture systemctl --failed --no-pager --plain
capture lxc-info -n android
capture findmnt -no TARGET,OPTIONS /userdata
capture dmesg
