# M8.5 S1 manual input checklist — 2026-11-19

| Check | Result | Evidence / limit |
|---|---|---|
| Unlock greeter, open Settings, scroll | Pass | Owner: "Unlocked; Settings opens and touch responds." |
| Interactive UI for ten minutes | Pass for this run | Owner confirms responsive throughout and returned Home; conservative window >=600 s; 25 telemetry samples span 720.63 s |
| Touch events continue under real use | Pass | 118 / 69 / 136 contacts across three 260 s capture windows; raw events/coordinates filtered before persistence |
| Volume Up / Down | Pass | Owner reports other controls OK; three clean press/release pairs each; no repeat events |
| Power key delivery | Pass | Five clean press/release pairs captured, no repeat events |
| Power screen blank/unblank | Deferred | Owner: "the power button did not do anything"; repowerd/suspend masks remain approved until M12 |
| Hall cover transitions | Not exercised | No magnet/magnetic cover available; IRQ counts remain zero; probe/registration is not an event pass |
| Vibrator | Prior H1 pass | Three physical 300 ms pulses felt in M8.4; not repeated as a new S1 tactile test; final LED inactive |

The UI PID stayed 3391 with no restart; no GPU/SysMMU/fence fault signatures
or display copy/fallback/skip/acquire-timeout increments. See `s1-results.json`,
`s1-samples.json` and `owner-observations.json`.

This is not full M8 sign-off. Hall events remain open, shared USB re-enumeration
occurred once, and memory buffers remain above startup after the short
post-close interval. A fixed-workload retention check is still warranted.
