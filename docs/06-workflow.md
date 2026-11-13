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
- DTB + DTBO + BOOT for a 6.18 test: only through `tools/m32_run_test.sh`, which flashes the
  test set and then restores stock DTB/DTBO and the baseline BOOT (owner approved 2026-11-14).
- VENDOR / SYSTEM / any other DTB/DTBO change / anything ≥ 100 MB: TWRP → `adb push` →
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

## USB link to the phone (Ubuntu Touch baseline; verified 2026-11-02, M0.3)

Needs Wi-Fi root SSH once (M0.1). Cable used: USB-C <-> USB-C on the laptop's
USB-C ports. USB-A cable: untested.

1. Plug in. Phone's view varies: sometimes `usb/online=1`, `Cable(USB)`, `rp(1)`
   (gadget comes up by itself); sometimes `usb/online=0`, `ac/online=1`,
   `Cable(PDIC)`, `rp(3)` (usb-moded refuses: "requested while not connected to pc").
2. In the PDIC state force the gadget (root, via Wi-Fi; lives in /run, gone after reboot):
   `ssh root@<wifi-ip> 'echo "USB_MODED_ARGS=-f" > /run/usb-moded/90-force-pc.conf && systemctl restart usb-moded'`
   Without this the link is dead in that state (tested: removing the file kills RNDIS
   with the cable untouched).
3. If `/sys/class/udc/*/state` says `not attached` (session dropped), replug the
   cable first, then step 2.
4. Laptop gets an `enp*u*` interface with `10.15.19.9/24`; the phone is
   `10.15.19.82`: `ssh root@10.15.19.82` / `ssh phablet@10.15.19.82`
   (host key SHA256:aHBdcZCSVr0dXofEX2Yb/DH8yd+TC7oPOYFYgI4aZqE, verified over Wi-Fi).
5. adb is NOT exposed in `developer_mode` (gadget functions: mass_storage, mtp,
   rndis). adb exists only in TWRP (flashing path unchanged).

Limits: the override needs a working Wi-Fi/other root path to the phone first, and
does not survive a reboot; a Wi-Fi-free method will be needed from M3 (initramfs telnet).

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

## Interrupted flash (observed 2026-11-07, log/2026-11-07-M3.3-clocks.md)
If Heimdall fails mid-transfer (USB re-enumeration), partitions may be half-written and the phone may show Samsung's
"An error has occurred while updating the device software" screen. It is a Download-type mode: `heimdall detect` sees it.
Re-flash the stock set in one session: `heimdall flash --DTB reference/stock-images/dt.img --DTBO reference/stock-images/dtbo.img
--BOOT baseline/ut-26.04-2026-10-19-aa17rf2/boot.img --no-reboot`, then restart and run tools/m24_preflight.sh.
If the session is stuck ("Protocol initialisation failed"), re-enter Download mode with the key combo first.
