# A50 kernel modernization: Samsung 4.14 → Android Common Kernel 6.18

Read this file first in every session, then `STATUS.md`, then the ticket it
names in `tasks/`. Work only on that ticket; do not start the next one early.

## Goal (one sentence)

Boot Ubuntu Touch 26.04 (Halium 11) on the Samsung Galaxy A50 (SM-A505F) with
a **6.18 LTS kernel** (Google ACK `android17-6.18`) carrying forward-ported
A50 drivers, while keeping the **stock Android 11 vendor partition** working
unchanged. Full definition: `docs/00-goal.md`.

## Where things are

| Path | What |
|---|---|
| `STATUS.md` | current milestone, last result, next action. Update at the end of every session |
| `docs/00-goal.md` | goal, success criteria, scope, non-goals |
| `docs/01-device.md` | verified device facts: board, partitions, boot chain, USB IDs |
| `docs/02-baseline.md` | the known-good system on the phone today and how to restore it |
| `docs/03-kernel-contract.md` | what the new kernel MUST provide: Halium config, vendor device nodes/ABIs, firmware |
| `docs/04-gap-matrix.md` | every enabled DT node → driver status in 6.18 → strategy |
| `docs/05-plan.md` | milestones M0–M13 with tasks and Definition of Done |
| `docs/06-workflow.md` | build / flash / test / recover loop and rules |
| `docs/07-risks.md` | known risks and mitigations |
| `docs/decisions/` | ADRs (0001 base kernel, 0002 keep stock vendor, 0003 newer Halium — deferred); a decision changes only through a new ADR |
| `tasks/` | tickets (one file per task) for the current + next milestone; index in `tasks/README.md` |
| `log/` | one file per test session (what changed, what was flashed, result) |
| `reference/` | evidence: live DT dump, gap matrix TSV, stock vendor extracts, measurements |
| `tools/` | scripts used to produce the evidence (re-runnable) |
| `baseline/` | known-good boot.img + ubuntu.img currently on the phone |
| `src/` | kernel trees: `samsung-a50-4.14-aa17rf2` (baseline source), `linux-4.14.194`, `linux-6.18.60` |
| `../backup/` | EFS/boot dumps, TWRP backup, rescue images (TWRP, vbmeta). Never modify |
| `../SAMFW.COM_SM-A505F_BKD_A505FDDS9CWA2_fac.zip` | stock firmware for full restore |

## Rules (non-negotiable)

1. **Evidence over assumption.** Every claim in docs cites a file, command
   output, or URL. Unknown = write "unverified", never guess.
2. **One variable per boot test.** Change one thing, flash, record in `log/`.
3. **Only BOOT is flashed with Heimdall** (≤ ~67 MB works; ≥ 800 MB fails on
   this host). Large images go through TWRP + adb + dd with read-back hash.
4. **A known-good fallback must exist before every flash**: `baseline/…/boot.img`
   (sha256 `7d5855ef…`). Recovery path is in `docs/06-workflow.md`.
5. **Never touch** EFS, SEC_EFS, CPEFS, PARAM, bootloader, or the vendor
   partition contents. The vendor partition is the contract, not our code.
6. **Scope discipline:** a task not in `docs/05-plan.md` needs a plan change
   (edit the plan, say why) before work starts. No drive-by refactors.
7. Root-only operations on the phone and every flash require the owner present.
8. Destructive host operations (rm of `../backup`, the firmware zip) are forbidden.

## Phone access (today)

- Ubuntu Touch over Wi-Fi: `ssh phablet@<phone-ip>` (key auth; DHCP, IP was 192.168.0.171).
- TWRP 3.7.1: `adb` over USB (Vol Down+Power → Vol Up+Power, cable in).
- Download mode: `heimdall` (power off, Vol Up+Vol Down while plugging USB).
- Laptop USB-C is detected as a PD charger in Ubuntu Touch → no adb/RNDIS;
  see `docs/02-baseline.md` "Known issues".
