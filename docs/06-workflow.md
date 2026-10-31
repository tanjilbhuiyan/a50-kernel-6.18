# 06 — Workflow: build → flash → test → record → recover

## Session routine

1. Read `CLAUDE.md`, `STATUS.md`, the current milestone in `05-plan.md`.
2. State the one variable this test changes.
3. Build in a container; record toolchain + commit + output sha256.
4. Ensure fallback: baseline boot.img hash `7d5855ef…` on disk.
5. Flash BOOT (and DTB/DTBO only when the milestone says so).
6. Observe; collect pstore / logs; restore if needed.
7. Write `log/YYYY-MM-DD-<milestone>-<topic>.md`; update `STATUS.md`.

## Build environments

| Purpose | Container | Notes |
|---|---|---|
| Baseline 4.14 kernel (M1.1) | as in `sadatdaniel/a50-halium` (`build/`, Proton clang) | reproduce byte-identical `Image` |
| ACK 6.18 kernel | Ubuntu 24.04+ with clang/LLVM + Rust (versions per ACK `build.config`) | Rust needed for ashmem |
| Ubuntu Touch rootfs | `ubuntu:22.04` privileged + `mknod /dev/loopN b 7 N` | never 24.04+ (orphan_file); not needed unless rootfs changes |

Host: Arch Linux. ARM64 binfmt is not persistent; re-register only if a
rootfs/chroot step needs it.

## Flashing rules

- BOOT: `heimdall flash --BOOT boot.img --no-reboot` (≤ ~67 MB OK).
- DTB / DTBO / VENDOR / SYSTEM / anything ≥ 100 MB: TWRP → `adb push` →
  `dd` to `/dev/block/by-name/<part>` → read back sha256 must equal source.
- After a failed Heimdall session the phone needs re-entry into Download mode;
  the "emergency recovery" screen is still Download mode and is flashable.
- Never flash RECOVERY unless replacing TWRP is the task.

## Getting logs from a failed boot

- pstore/ramoops (once M1.5 verified): boot baseline or TWRP, read
  `/sys/fs/pstore/*` (root).
- UT journal (if rootfs mounted): `/data/system-data/var/log/journal` via TWRP
  adb; read with `journalctl -D`.
- Halium initramfs telnet `192.168.2.15` when USB gadget works.

## Phone access helpers

- SSH key install (owner, in phone Terminal):
  `mkdir -p ~/.ssh` then fetch `~/.ssh/id_ed25519.pub` from a temporary
  `python3 -m http.server` on the laptop (`wget -qO- http://<laptop>:8765/k >> ~/.ssh/authorized_keys`),
  `chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys`. Stop the server after.
- Live DT dump (re-generate `reference/live-dt-compatibles.tsv`): `tools/dump_live_dt.sh <phone-ip>`.
- Gap matrix: `python3 -I tools/gap_matrix.py reference/live-dt-compatibles.tsv src/samsung-a50-4.14-aa17rf2 <target-tree>`.

## Test log template (`log/YYYY-MM-DD-Mx-topic.md`)

```
# <date> <milestone> <topic>
Variable changed: <one thing>
Inputs: kernel commit <sha>, config <sha256>, boot.img <sha256>, DTB/DTBO <sha256 or stock>
Flashed: <partitions>
Expected: <DoD item>
Observed: <facts, log excerpts, pstore>
Result: PASS / FAIL / INCONCLUSIVE
Restore performed: yes/no (how)
Next: <one action>
```
