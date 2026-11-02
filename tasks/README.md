# tasks/ — tickets

One file per task. A ticket is the unit a session works on ("work on
`tasks/M1.1-…`"). Tickets exist only for the current and next milestone;
later milestones get tickets when we reach them (evidence first, Rule 1).

## Status values
`todo` · `in-progress` · `blocked (reason)` · `done (log/…)` · `dropped (reason)`

## Rules
- A ticket is done only when **every** acceptance criterion has evidence in `log/`.
- Change scope → edit the ticket (and `docs/05-plan.md` if the milestone changes) first.
- `Needs phone: yes` tickets wait for M0 DoD and require the owner present.

## Index

| ID | Title | Needs phone | Depends on | Status |
|---|---|---|---|---|
| M0.1 | Root SSH key on the phone | yes | — | done (log/2026-11-02-M0.1-root-ssh.md) |
| M0.2 | Baseline function checklist | yes | M0.1 | done (log/2026-11-02-M0-baseline-checklist.md) |
| M0.3 | USB access despite PD detection | yes | M0.1 | done (log/2026-11-02-M0.3-usb-access.md) |
| M0.4 | Diagnose baseline audio failure (kernel vs userspace) | yes | M0.2 | done (log/2026-11-02-M0.4-audio-diagnosis.md): userspace config |
| M0.5 | Microphone captures no voice (tracked defect) | yes | M0.4 | deferred: UT-image session |
| M1.1 | Reproduce baseline 4.14 kernel byte-identically | no | — | done (log/2026-11-01-M1.1-reproduce-baseline.md) |
| M1.2 | Build ACK android17-6.18 GKI for arm64 | no | — | done (log/2026-11-01-M1.2-ack-build.md) |
| M1.3 | Capture the vendor kernel ABI (contract capture) | yes | M0, M0.4 | done (log/2026-11-02-M1.3-contract-capture.md) |
| M1.4 | Does S-Boot boot a compressed Image? | yes | M0, M1.1 | todo |
| M1.5 | Working ramoops/pstore crash log | yes | M0, M1.1 | todo |
| M2.1 | A50 device tree for 6.18 (first-light subset) | no | M1.2 | done (log/2026-11-01-M2.1-dt.md; fb format risk accepted) |
| M2.2 | Minimal 6.18 defconfig + boot.img within 57.67 MB | no | M1.2, M1.4 | todo |
| M2.3 | DTB/DTBO partition images in stock dt_table format | no | M2.1 | done (log/2026-11-02-M2.3-dt-images.md) |
| M2.4 | First light on the phone | yes | M2.1–M2.3, M1.5 | todo |
