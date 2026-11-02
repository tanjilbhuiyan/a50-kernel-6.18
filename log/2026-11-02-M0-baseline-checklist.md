# 2026-11-02 M0.2 baseline function checklist (CLOSED)
Note: S3 touch/keys ✅ (owner, 2026-11-02).
Variable changed: none (measurements only, baseline BOOT aa17rf2 `7d5855ef…`, kernel 4.14.194 Mint-user, uptime since 2026-11-01 03:07)
Transport: root SSH over Wi-Fi (192.168.0.171); user-level commands via `runuser -u phablet`.

| Row | Result | Evidence |
|---|---|---|
| S3 touch/keys | ✅ (owner) | touch, power, volume keys work |
| S4 Wi-Fi | ✅ | `nmcli -t -f ACTIVE,SSID,SIGNAL dev wifi` -> `yes:simple_network:57` |
| S5 USB RNDIS | ✅ (M0.3) | `log/2026-11-02-M0.3-usb-access.md` |
| S6 audio devices | ✅ present, playback/record pending | pactl: sinks `sink.primary-out`, `sink.fast`, `sink.fake.sco`; sources `source.primary-in` (+monitors); default sink `sink.fast`, default source `source.primary-in`; all SUSPENDED (idle) |
| S6 speaker (heard) | ❌ no sound (owner) | Played alarm-clock-elapsed.oga x3 on `sink.fast`, x3 on `sink.primary-out`, plus a 15 s 440 Hz tone on `sink.primary-out`: all `paplay rc=0`, owner heard nothing (also nothing from the phone's own volume UI). Mid-tone: pulse sink-input present (`s16le 2ch 48000Hz`), but no RUNNING ALSA substream in /proc/asound/card0, `android.hardware.audio.service` (pid 3918) holds 0 `/dev/snd` fds, all `ABOX {DSIF,UAIF0-4} SPK` = 0, `TFA Profile`=0, `TFA music Playback Volume`=0. Amp is bound (`7-0034` driver tfa98xx, `SPEAKER Switch` on). Pulse journal: "Failed to set voice volume." x3 at 03:08. Android logcat: no audio lines. Cause unknown (userspace HAL path vs kernel/ABOX firmware); boot-time dmesg already rolled over. |
| S6 microphone | ❌ digital silence | `parecord -d source.primary-in` 5 s (owner speaking): 4.92 s, 216972 frames, 44.1 kHz mono, every sample 0 (rms 0.0, peak 0). Source not muted (see mute/volume check in session). Same symptom class as the speaker: capture path delivers nothing. |
| S7 modem registration | ✅ | ofono `/ril_1` NetworkRegistration Status=registered, Technology=lte, Name=Grameenphone, Strength=60, Mode=auto; SimManager Present=true, PinRequired=none. `/ril_0` has no NetworkRegistration (no SIM in slot 1). |
| S7 call | ✅ connects, ❌ voice path unrouted | ofono `/ril_1` VoiceCallManager.GetCalls timeline (14:27-14:31): short codes `121` (dialing -> alerting, ended ~4 s), `222`, `566` (dialing only, ~4 s each); then a mobile number: dialing -> alerting (first attempt, 14:28:04, ended after ~5 s, not answered/hung up) and a second attempt that reached `State=active` for about 61 s (seen active at 14:29:58, gone by 14:30:59; owner confirmed "call connected", then cut it). During the ACTIVE call: no RUNNING ALSA substream, audio HAL 0 `/dev/snd` fds, `ABOX DSIF/UAIF0-2 SPK` = 0, all pulse sinks SUSPENDED -> no voice audio routed (same fault as S6). Whether the owner could hear/speak was not recorded. |
| S7 SMS received | ✅ | ofono D-Bus monitor (14:33:55-14:43:55 local): one `org.ofono.MessageManager.IncomingMessage` on `/ril_1`, SentTime 2026-11-02T14:42:00+0600, from an operator promotional sender (unsolicited; content not recorded). Proves network -> modem -> ofono delivery. |
| S7 SMS sent | ✅ | Second ofono monitor (from 14:50:57): `SendMessage` on `/ril_1` at 14:51:27 local (owner sent one SMS from the Messaging app), returned `/ril_1/message_…`, State `pending` -> `sent`, then `MessageRemoved`. Delivery to the recipient not confirmed (delivery reports off: UseDeliveryReports=false). |
| S8 Bluetooth | ✅ pair + A2DP playback | Owner enabled BT in Settings (was soft-blocked before). JBL Go 3 `<bt-addr>`: Paired/Bonded/Trusted/Connected = yes; UUIDs Audio Sink, Headset, Handsfree, AVRCP. PulseAudio: `bluez_card.2C_FD_B4_9E_5E_40`, active profile `a2dp_sink`, sink `bluez_sink.2C_FD_B4_9E_5E_40.a2dp_sink` (50%). `paplay` x3 to that sink, owner HEARD it. Caveat: owner reported the speaker was not discoverable from the UI at first; a controller-side 15 s scan did list it (plus unnamed <bt-addr>, <bt-addr> and a watch); discovery reliability not characterised. Note: BT audio works while the internal speaker/mic do not, so PulseAudio itself works and the fault is in the droid HAL/ABOX path. |
| S9 battery | ✅ reads | upower `battery_battery`: state charging, 59%, 4.131 V, 35 C, energy-full 16.524 Wh, energy-full-design 0 Wh (not reported by driver), capacity 100% |
| S9 suspend | ❌ never suspends | Valid run: screen off by owner, USB unplugged, no SSH from laptop during the window; phone clock 15:18:30 -> 15:30:32 (12 min 2 s; /proc/uptime delta 721.9 s). `suspend_stats` success 0 / fail 0 before and after; 0 `PM: suspend entry` in dmesg+journal; wakeup_count 59676 -> 61171; battery 99% -> 98%. cpu0 cpuidle used (WFI, bootcl-cpu-sleep) so CPUs idled but system suspend was never entered. Busiest wake sources (cumulative counts): wlan 148795, hip4_wake_lock 113407 (+551 in the window), wlan_ma 26212, umts_ipc1 10311, bt_write_wake_lock 9531 (JBL still connected). Cause not isolated. An earlier attempt (15:16:54 -> 15:17:27, only 33 s elapsed on the phone clock) was discarded as inconclusive. The 10-cycle suspend/resume criterion (S9) cannot be measured on the baseline until the cause is found. |
| Sensors | ✅ daemon | `sensorfwd.service` active (docs/02-baseline.md said no sensorfw unit: wrong, to correct). Not exercised. |
| Failed units | `usb-tethering.service` | exit 1 at boot 03:07:39 (USB not connected then); same as docs/02 |
| GPS (stretch) | not tested | skipped by owner (needs an outdoor fix); location service was active on 2026-11-01 |

Summary (2026-11-02): ✅ S3 touch/keys, S4 Wi-Fi, S5 USB (RNDIS ssh, M0.3), S7 modem/call/SMS in+out, S8 Bluetooth pair + A2DP, S9 battery readings. ❌ S6 speaker and microphone (no audio path: HAL opens no PCM, ABOX routes 0, mic returns digital silence; BT audio works), call voice audio (same cause), S9 suspend (never enters system suspend). Not tested: GPS.
Result: M0.2 closed. Two baseline defects (audio, suspend) are recorded as the bar for S10 and need diagnosis before M10 / S9 can be met.
Restore performed: n/a (nothing changed on the phone except runtime state: Bluetooth enabled and JBL paired, USB override file in /run/usb-moded)
Next: M0 DoD reached; M1.3 contract capture (phone, root over RNDIS or Wi-Fi). Open decision: add baseline audio and suspend diagnosis to docs/05-plan.md.

## Addendum 2026-11-02 evening: re-run after the userspace fix
The baseline changed after this checklist (UT-image session fixed 4 systemd symlinks, see `log/2026-11-02-M0.4-audio-diagnosis.md`). Rows above that say ❌ for speaker, call voice and suspend describe the baseline BEFORE the fix. Re-measured:
| Row | Result after fix |
|---|---|
| S6 speaker | ✅ owner heard a loud tone clearly (16:42:20); first attempts after idle failed (paplay hung), cause unknown |
| S6 microphone | ❌ captures hiss/clicks, no voice (spectral analysis), handoff's "PASS" was only non-zero samples |
| S7 call voice | downlink ✅ uplink ❌ | Call active 17:21:48-17:22:18 (>= 30 s, read-only watcher, no state changed). Routing identical in 3 snapshots: RUNNING pcm4p (playback), pcm10c + pcm11c (capture), HAL 5 /dev/snd fds, `UAIF0 SPK`=1, `MAINMIC Switch` on, `RECMIX1L BST3` on. Owner: heard the other party, the other party could NOT hear the owner (same cause as the microphone defect, M0.5). Before the fix the same call had no PCM, 0 fds, all routes 0. |
| S9 suspend | ✅ works: suspend_stats success 214 / fail 52; phone suspends within seconds of screen-off |
| GPS | handoff: HAL runs, NMEA every 1 s, no fix after 10 min at a window; open-sky test pending |
