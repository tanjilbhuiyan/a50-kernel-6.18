#!/bin/sh
# ADR-0006 per-boot hook (6.18 only): keep GStreamer's plugin scan out of the unavailable Android OMX codec service.
# Bind-mounts a text placeholder read-only over libgsthybris.so after checking both hashes; GStreamer then blacklists
# the file instead of stalling in OMX discovery. Refuses (exit 1, nothing mounted) on any mismatch or if something is
# already mounted there. The rootfs file is never written.
# ROOT is empty on the phone; host tests set it to a scratch root inside a private mount namespace.
set -eu
umask 022
ROOT=${ROOT:-}
target="$ROOT/usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgsthybris.so"
placeholder=${A50_GST_PLACEHOLDER:-/run/a50-m75/libgsthybris.placeholder}
stock_sha=26ffd94d8cc8b6efff993ae7fc8b6bbf1dbca2b2c2fc9487ef631d2fdcfba0a9
placeholder_sha=3ee135f94d447e41e35d228975c96d0f223455fc03184d99d6db74fd240c46a9
refuse() { echo "A50M75: REFUSE gst-hybris deferral: $*" >&2; exit 1; }
case "$(uname -r)" in 6.18*) ;; *) [ -n "${A50_GST_TEST:-}" ] || refuse "not a 6.18 kernel";; esac
[ -f "$target" ] || refuse "missing $target"
if grep -q " $target " /proc/self/mountinfo 2>/dev/null; then refuse "$target is already a mount point"; fi
actual=$(sha256sum "$target"); [ "${actual%% *}" = "$stock_sha" ] || refuse "unexpected stock libgsthybris.so"
actual=$(sha256sum "$placeholder"); [ "${actual%% *}" = "$placeholder_sha" ] || refuse "unexpected placeholder"
mount --bind "$placeholder" "$target"
mount -o remount,bind,ro "$target"
actual=$(sha256sum "$target"); [ "${actual%% *}" = "$placeholder_sha" ] || { umount "$target"; refuse "placeholder not visible after bind"; }
echo "A50M75: ADR-0006 gst-hybris deferral active: GStreamer will blacklist libgsthybris.so (no hardware codecs on 6.18)"
