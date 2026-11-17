# ADR-0006 — Defer the GStreamer hybris codec plugin with a per-boot read-only placeholder

Status: **Accepted** (2026-11-18). Proposed with the owner's "continue with option A"; accepted on M7.5 I4, where the
telephony handler (42.8 s) and Lomiri (48.2 s) became ready and stayed active, and systemd reached `running` with no
failed units (`log/2026-11-18-M7.5-i3-handler-startup.md`, section "I4").

## Context
On 6.18 Android's OMX codec service crash-loops (`vendor.media.omx=[restarting]`, repeated failures to start
`android.hardware.media.omx@1.0::IOmxStore/default`), because the MFC video-codec driver is not ported. M7.5 I3
(`log/2026-11-18-M7.5-i3-handler-startup.md`) found the stalled session's chain:
1. `clean-gstreamer-cache.service` empties `~/.cache/gstreamer-1.0` at every session start, so the first GStreamer client
   rebuilds the registry through `gst-plugin-scanner` (on stock the registry file is dated from the current boot).
2. The telephony handler is such a client. Its scanner child loads `libgsthybris.so` (package `gst-hybris`), which calls
   `media_codec_list_count_codecs` → `MediaCodecList` → `IOmxStore::getServiceInternal` and waits indefinitely
   (stack return-site candidates, I3).
3. The handler never takes its D-Bus names; Lomiri's calls to it time out; Lomiri misses READY and is stopped.

ADR-0005 (audio) fixed PulseAudio but not this (M7.5 I2).

## Decision
For every 6.18 boot until the hardware codec path works or this ADR is replaced, a per-boot runtime hook, run before the
phablet user manager:
1. Checks the sha256 of `/usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgsthybris.so` (stock
   `26ffd94d8cc8b6efff993ae7fc8b6bbf1dbca2b2c2fc9487ef631d2fdcfba0a9`, gst-hybris
   `0.1-1~20260622130543.6~874e0cf+ubports26.04.1`) and refuses to continue if it differs.
2. Bind-mounts, read-only, a one-line text placeholder from `/run` over it. GStreamer fails to load it ("invalid ELF
   header") and records it as blacklisted; the other plugins are scanned normally (host check with GStreamer 1.28:
   scan of 266 plugins in 1.85 s, placeholder listed under "Blacklisted files").

The rootfs, vendor partition and stored registry are not changed; the session's own cache cleaner still runs, and the
registry is rebuilt each boot from the real plugins. No codec is faked or advertised.

## Consequences
- No hardware (OMX/MFC) video decode or encode through GStreamer on 6.18; software codecs remain. Nothing may describe
  hardware codecs as working.
- Removal: when the MFC/OMX path is ported (M13 lists MFC) and `vendor.media.omx` stays running, this overlay is removed
  and `libgsthybris.so` loads normally. This may stay in place for a long time.
- Any other rootfs file overlay needs its own ADR.
