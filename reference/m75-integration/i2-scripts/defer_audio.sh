#!/bin/sh
# ADR-0005 per-boot hook (6.18 only): start PulseAudio without the unported Android audio HAL module.
# Bind-mounts the prepared overlay read-only over /etc/pulse/touch.pa after checking both hashes. Refuses (exit 1,
# nothing mounted) on any mismatch or if something is already mounted there. The rootfs file is never written.
# ROOT is empty on the phone; host tests set it to a scratch root inside a private mount namespace.
set -eu
umask 022
ROOT=${ROOT:-}
target="$ROOT/etc/pulse/touch.pa"
overlay=${A50_AUDIO_OVERLAY:-/run/a50-m75/touch.pa}
stock_sha=04046fa3fa4ff1247705034f42fe03457d57414cdb7a9336e74246419666ccd0
overlay_sha=275b1ea6a3b8800f938a706a1ba81cda68b65a33a9edfae75f5d480b5e70175a
refuse() { echo "A50M75: REFUSE audio deferral: $*" >&2; exit 1; }
case "$(uname -r)" in 6.18*) ;; *) [ -n "${A50_AUDIO_TEST:-}" ] || refuse "not a 6.18 kernel";; esac
[ -f "$target" ] || refuse "missing $target"
if grep -q " $target " /proc/self/mountinfo 2>/dev/null; then refuse "$target is already a mount point"; fi
actual=$(sha256sum "$target"); [ "${actual%% *}" = "$stock_sha" ] || refuse "unexpected stock touch.pa"
actual=$(sha256sum "$overlay"); [ "${actual%% *}" = "$overlay_sha" ] || refuse "unexpected overlay"
mount --bind "$overlay" "$target"
mount -o remount,bind,ro "$target"
actual=$(sha256sum "$target"); [ "${actual%% *}" = "$overlay_sha" ] || { umount "$target"; refuse "overlay not visible after bind"; }
echo "A50M75: ADR-0005 audio deferral active: PulseAudio starts without module-droid-discover (no audio on 6.18)"
