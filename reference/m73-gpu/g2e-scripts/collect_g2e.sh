#!/bin/sh
# Observe natural Mir startup before bounded clients. Only /run setup is changed.
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
export SYSTEMD_PAGER=cat SYSTEMD_COLORS=0 LC_ALL=C
case "$(uname -r)" in 6.18*) ;; *) exit 1;; esac
capture() {
    printf '\nCMD:'; printf ' %s' "$@"; printf '\n'
    timeout 10 "$@" 2>&1
    printf 'RC=%s\n' "$?"
}
stats=/sys/devices/platform/148b0000.decon_f/g2b_stats
snapshot() {
    capture cat /proc/uptime
    capture cat "$stats"
    capture systemctl show lightdm.service -p ActiveState -p SubState -p Result -p ExecMainStatus
    capture ps -eo pid,stat,wchan:32,comm
    capture tail -n 100 /var/log/lightdm/unity-system-compositor.log
    capture tail -n 60 /var/log/lightdm/lightdm.log
    capture sh -c 'grep -E "mali|decon" /proc/interrupts'
}
capture uname -r
capture cat /sys/module/mali_kbase/parameters/a50_g1_probe_only
capture sha256sum /usr/bin/test_egl /usr/bin/test_glesv2 /run/a50-g2e/*
if [ "$(cat /sys/module/mali_kbase/parameters/a50_g1_probe_only 2>/dev/null)" != N ] ||
   [ ! -c /dev/mali0 ] || [ ! -r "$stats" ]; then
    echo 'G2e prerequisites unavailable; no clients run'; exit 2
fi
echo G2E_NATURAL_STARTUP
while read -r up rest < /proc/uptime; do
    [ "${up%%.*}" -ge 100 ] && break
    sleep 2
done
snapshot
capture systemctl show -p SystemState -p NFailedUnits -p NJobs
capture lxc-info -n android
capture lxc-attach -n android -- /system/bin/getprop sys.boot_completed
capture lxc-attach -n android -- /system/bin/logcat -b crash -d
echo G2E_ION_HINT_REPLAY_BEGIN
echo 'The following helper deliberately attempts three unsupported requests per ABI.'
capture /run/a50-g2e/ion-flags64
capture /run/a50-g2e/ion-flags32
printf '\nG2E_GLES_BEGIN '; date -Is
timeout -k 5 30 /bin/bash -lc '
    printf "GLIBC_TUNABLES=%s\n" "${GLIBC_TUNABLES-}"
    case ":${GLIBC_TUNABLES-}:" in
        *:glibc.rtld.optional_static_tls=4096:*) ;; *) exit 78;;
    esac
    exec /usr/bin/test_glesv2
'
printf 'G2E_GLES_RC=%s\n' "$?"
printf '\nG2E_EGL_BEGIN '; date -Is
timeout -k 5 12 /bin/bash -lc '
    case ":${GLIBC_TUNABLES-}:" in
        *:glibc.rtld.optional_static_tls=4096:*) ;; *) exit 78;;
    esac
    exec /usr/bin/test_egl
'
printf 'G2E_EGL_RC=%s\n' "$?"
snapshot
# Avoid a direct-display producer racing a live compositor.
if ! systemctl is-active --quiet lightdm.service; then
    echo G2E_DIRECT_DISPLAY_CHECK_AFTER_FAILED_LIGHTDM
    capture /run/a50-g2e/winconfig-test /dev/fb0 /sys/kernel/debug/sync/sw_sync
else
    echo G2E_DIRECT_DISPLAY_SKIPPED_LIGHTDM_ACTIVE
fi
capture systemctl --failed --no-pager --plain
capture findmnt -no TARGET,OPTIONS /userdata
capture dmesg
