# ADR-0005 — Defer the Android audio HAL in PulseAudio with a per-boot read-only overlay

Status: **Accepted** (2026-11-18, owner: "yes, approve option A")

## Context
On 6.18 the Android audio HAL (`init.svc.vendor.audio-hal`) crash-loops, because the ABOX/TFA9872 audio drivers are
not ported (M10). M7.5 I1 (`log/2026-11-17-M7.5-integration.md`, section "I1") traced the M7.5 session failure to it:
1. PulseAudio's startup script `/etc/pulse/touch.pa` loads `module-droid-discover`, which talks to that HAL over
   hwbinder. PulseAudio blocks in startup, never answers clients (`pactl info` times out), and its `Type=notify` unit
   never becomes ready.
2. `lomiri-telephony-service-handler` never takes its D-Bus name and is stopped after 90 s (the link to PulseAudio is
   strongly indicated, not proven).
3. Lomiri's synchronous calls to the handler time out, its READY comes too late, and systemd stops it after 120 s.
   This also fails `ubuntu-touch-session-unencrypted.target`.

On stock 4.14, PulseAudio is ready 5 s after start and Lomiri 4.9 s after start (same section). Swapping the sound
server would not help: any Halium sound server goes through the same HAL. The standing rule "no mixer or PulseAudio
state changes" applied; the owner approved this exception for M7.5.

## Decision
For every 6.18 boot until the audio drivers are ported (M10) or this ADR is replaced, a per-boot runtime hook:
1. Checks the sha256 of the rootfs `/etc/pulse/touch.pa` (stock `04046fa3fa4ff1247705034f42fe03457d57414cdb7a9336e74246419666ccd0`)
   and refuses to continue if it is different.
2. Bind-mounts, read-only and before the phablet user session starts, a copy of that file from `/run` that is
   identical except that the `module-droid-discover` block is removed. PulseAudio's own `module-always-sink` then
   provides a null (silent) sink.

The rootfs and vendor partition are not changed; the overlay disappears at reboot and is never used on 4.14. The
Android audio HAL, mixer settings, volumes and stored stream state are not touched, and no audio device is faked.

## Consequences
- PulseAudio can become ready without the HAL, which should let the telephony handler and Lomiri start (to be verified
  in M7.5 I2).
- There is no sound, microphone, call audio or audio routing on 6.18 while this is in place. Nothing may describe audio
  as working.
- M10's DoD gains: this overlay is removed and PulseAudio uses `module-droid-discover` with the ported drivers.
- Any other rootfs file overlay needs its own ADR.
