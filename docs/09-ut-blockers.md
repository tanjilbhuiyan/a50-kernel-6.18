# 09 — Ubuntu Touch blockers outside the kernel milestones

Recorded 2026-11-19 by the UT-image session. These are hard blockers and open
defects of the **Ubuntu Touch side** of the A50 port (userspace, packaging,
distribution, upstream platform). Several of them exist only because of
kernel 4.14, so the 6.18 kernel resolves them. Others are kernel-independent
and must be worked after (or beside) M0–M13. `10-after-kernel-plan.md` orders
the work.

Sources:
- the port fork `../a50-ubuntu-touch` (`tanjilbhuiyan/a50-ubuntu-touch`, HEAD `b4556ed`, 2026-10-19), mainly
  `docs/official-port-plan.md`, `docs/SESSION-HANDOFF-22.md` and `docs/release-validation-backlog.md`
- measurements on the baseline phone, 2026-11-02 (`log/2026-11-02-M0*`, upstream issue sadatdaniel/a50-ubuntu-touch#1)
- UBports system-image `channels.json`, read 2026-11-19

Column "6.18?": **R** = the 6.18 kernel removes the blocker by design (must
still be verified); **H** = 6.18 helps but does not finish it; **—** = independent of the kernel.

## A. Upstream port: hard blockers (author's "official UBports route", stalled since 2026-10-20)

| ID | Blocker | Evidence | 6.18? | How it gets resolved |
|---|---|---|---|---|
| UB1 | **4.14 kernel does not boot when built with Google clang.** UBports' standard `build.sh` / community-ports CI only fetches Google prebuilt clang. Google clang 11, 12 and 14 all hang at the Samsung logo before the first printk; Proton clang 13 boots with identical source and config. The author ruled out LTO, the integrated assembler, Google LLD/LLVM back end, the extra LLVM=1 commits and `-O3`; the fault is in Google clang's front end. Escalation text drafted, never posted | `docs/SESSION-HANDOFF-22.md` "Open" item 3; `docs/official-port-plan.md` gate 1; `docs/upstream-drafts.md` item 8 | **R** | ACK 6.18 is built with Google clang by design (M1.2 Kleaf build). Verify: the M-series boot.img is Google-clang-built and boots. 4.14 itself stays unresolved; not our target |
| UB2 | **Package cohort ≠ 0.** The image overrides the official rootfs with 8 locally patched package groups (pinned 2026-10-09). An official port may carry none | `docs/official-port-plan.md` "Cohort → upstream"; `scripts/release/validated-packages.lock` | **H** | Per row below. Kernel-caused rows disappear with 6.18; the rest need upstream MRs or must be re-validated on a current rootfs |
| UB3 | **No OTA channel, no installer entry.** `system-image.ubports.com` has no `a50`; updating the rootfs means reflash + data wipe | fork `README.md` "Not working"; `channels.json` 2026-11-19 | — | Own release mechanism first (flashable zip / own channel); official channel only after UB1+UB2 and UBports' agreement (gate 6) |
| UB4 | **Unified recovery depends on UB1** (recovery.img carries the tools-built kernel) | `docs/official-port-plan.md` gate 4 | **R** | Rebuild recovery with the 6.18 kernel |

### UB2 detail: the cohort

| Package(s) | Why carried | 6.18? | Route out |
|---|---|---|---|
| `tar +a50openat2.1` | 26.04 tar fails without `openat2` (no ENOSYS fallback); 4.14 lacks it | **R** (openat2 since 5.6) | Drop after 6.18 boots UT |
| polkit legacy helper (`docs/polkit-legacy.md`) | kernel-4.14-compatible helper | **R** (verify) | Drop, use the standard helper |
| lomiri, -common, -greeter, -private `+a50state.4` | Restart/Recents window-state fixes | — | Upstream Lomiri MR 331 (open) or rebase + resubmit |
| lomiri-system-settings + 2 libs `+a50qtquick.1` | QtQuick validator / lock-security regression | — | MR to lomiri-system-settings; re-test on current rootfs first |
| waydroid `+single-instance.2+fdclose.1` | single-instance launcher; fd leak (waydroid#2357) | — | UBports packaging MR + upstream PR |
| qtmir ×3 pinned `.83` | validated version; rootfs moved to `.84` | — | Validate current qtmir, drop pin |
| content-hub ×5 | older rootfs | — | Already in current rootfs: drop |
| libexiv2-27-compat, lomiri-action-api ×2 | camera ABI / Qt5 `Lomiri.Action` | — | Upstream rootfs-seed reports (drafted) |

## B. A50 device defects measured on the baseline (kernel-independent until proven otherwise)

| ID | Defect | Evidence | 6.18? | Notes |
|---|---|---|---|---|
| UD1 | **Port services never started**: four `.wants/` symlinks committed as regular files (upstream regression 3f95df93). Caused silent audio, no autosuspend, gpsd blocked | upstream issue #1; fixed on the phone 2026-11-02 (`tools/a50-fix-wants-links.sh`) | — | **Not yet fixed in our fork.** Any image built from the fork without the fix is broken |
| UD2 | **Microphone captures no voice** (hiss floor, clicks); speaker works | M0.4 work, `log/2026-11-02-M0*` | H | Unknown layer (HAL capture route / mixer / codec). Upstream never verified mic or call voice. Must be classified before M10 can claim S6 |
| UD3 | **GPS fix not verified.** gpsd + HAL run, NMEA flows, no fix in 10 min at a window; no SV list via lomiri-location-service | UT-image session 2026-11-02 | H | Needs an open-sky test; app suspension on screen-off stops the session |
| UD4 | **Camera in UT**: `qtubuntu-camera` 0.5.1 lacks `ViewfinderSettingsControl2` → segfault | fork `README.md`, `docs/experiments/014-camera.md` | — | Upstream fix; Waydroid camera works |
| UD5 | **Fingerprint**: ET713 never leaves reset | fork `docs/experiments/012-fingerprint.md` | H | Last priority (both plans agree) |
| UD6 | **Suspend ~20% failures** (214 ok / 52 fail at one reading) | kernel session, 2026-11-02 | H | Re-measure on 6.18 (M12) |
| UD7 | Laptop USB-C seen as charger (PD) on 4.14 | `02-baseline.md` known issue 1; `08-open-questions.md` #5 | H | M12 USB modes |
| UD8 | Untested: Bluetooth HFP, wired headset, earpiece, VoLTE, NFC, factory reset, VPN, Libertine, notifications | fork `README.md`, `docs/release-validation-backlog.md` | — | Validation phase |

## C. Independence from the upstream author

Our fork still downloads from `sadatdaniel` at build time:

| ID | Dependency | Where | Resolution |
|---|---|---|---|
| UI1 | 20-package bundle (release `inputs-20261017`) | `scripts/release/fetch-release-inputs.sh` `BASE=` | Mirror to a release in our fork, repoint |
| UI2 | Kernel boot images (`kernel-builds-20261017`) | a50-halium releases (not copied by a fork) | Superseded by our 6.18 boot.img; keep a mirrored copy of `boot-aa17rf2.img` as fallback |
| UI3 | Kernel source `sadatdaniel/android_kernel_samsung_exynos9610_mint` | fork `deviceinfo` `deviceinfo_kernel_source` | Point at our 6.18 tree (ACK + A50 patches) |

## D. Platform: Ubuntu Touch 26.04 itself

| ID | Fact | Evidence | Consequence |
|---|---|---|---|
| UP1 | **26.04 is not released.** Only a hidden `26.04-1.x/arm64/android9plus/daily` channel (22 official devices); no rc/stable; no date. Current stable is 24.04-2.x | `channels.json` 2026-11-19; UBports Q&A 189 (2026-05-03); forum topic 12312 | Daily rootfs is a moving target: pin a specific daily (e.g. build 556, 2026-11-19) per candidate and record it |
| UP2 | Our baseline rootfs is from mid-October; the patched cohort (UB2) is pinned to 2026-10-09 package versions | `baseline/.../rootfs-source.txt`, `validated-packages.lock` | Rebasing on a current daily means re-validating every cohort package (version skew) |
| UP3 | Rootfs images must be built in an `ubuntu:22.04` container because 4.14 cannot mount `orphan_file` ext4 | `06-workflow.md` build environments | **R** with 6.18 (orphan_file since 5.15): verify, then allow a current build container |
