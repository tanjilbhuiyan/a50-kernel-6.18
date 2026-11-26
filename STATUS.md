# STATUS

Updated: 2026-11-26 (B2b5: speaker tone audible (owner) through TFA9872 + ABOX speaker protection; stock restored, fsck clean; fixes carried to WIP/clean. Next: headset/microphone paths vs stock)

## How to use this file (Claude Code and Codex)
Both tools work on this project. Claude Code reads `CLAUDE.md`; Codex enters through `AGENTS.md`, which defers to `CLAUDE.md`.
Read this file, then the active ticket and its log. Before trusting anything here, check `git status` in the outer repo and the
branch in `src/ack-6.18/common`. One tool at a time on the kernel checkout and on the phone. At the end of a session, update
**RESUME HERE** with commits, branch, image hashes, last test and rollback result, and the next action.

## RESUME HERE (2026-11-22, M10.3 B2b firmware crash on TFA message; stock restored)
- **Active ticket:** `tasks/M10.3-codec-amplifier.md`, in progress. Read latest log
  `log/2026-11-22-M10.3-tfa9872.md`. B1 codec and **B2a amplifier probes pass**. No speaker output or hardware
  DSP RPC exercised; M10.3 remains open. Owner policy: preserve existing amplifier calibration, stop if invalid;
  no EFS/recalibration. Stock pre/post calibration reading matched privately (`b2a-calibration-preserved.json`).
- **B2a:** TFA9872 recognized at **0.440721 s**, 5-0034 on 11d10000.hsi2c; transport provider registers 0.465260 s;
  Tfa9872.cnt loads 23.401212 s (vendor-mount retry). At 150/390 s: probe_only=Y, firmware_ready=1, MTPEX=1,
  RDC nonzero/non-FFFF, raw reg/rw interfaces absent. **352 controls**, four added TFA names exactly as stock,
  none removed vs B1; stock-matching card0 PCMs. Control semantics/routing/playback still untested.
- **Regression:** owner sees recognizable Ubuntu Touch UI; multi-user 168.846668 s, running/0 failed units at
  200 and 390 s, userdata rw, input/wlan0/hci0 present (Wi-Fi not joined, BT traffic untested), direct DMA
  1139/1488 frames, no copy/fallback/acquire-timeout increments. Stream and complete dump through sync
  **431.081767 s**, no oops/panic/SError/BUG/IOMMU faults. Existing boot-protocol + two iommu.c:612 WARNs remain.
- **Phone verified after B2a:** automatic stock restore **2026-11-22 01:42:39 +06:00**, 4.14.194 boot **01:42:54**,
  live DTB/DTBO/BOOT hashes pass, fsck clean **7189/3440640 files, 1979154/13745152 blocks**, 100% Charging;
  home Wi-Fi SSH verified; post-restore calibration read matches. **No test active; no action needed.**
- **B2h (2026-11-22 14:04, owner present):** first stream, earpiece: 6/6 tones ran (RDMA0 -> UAIF0, IPC 38 -> 268,
  no faults), **owner heard nothing**. Candidate: mainline RT5665 lacks stock MX-7D=0x0101 init (IF1 DAC2 reads empty
  slots 2/3). Also UAIF0 BCLK 1508502 Hz (-1.8%, AUD divider rounding; separate fix). Stock restored 14:12:30, pre-flight
  pass, fsck clean 7188 files. `b2h-results.json`.
- **B2h2 (2026-11-22 18:19, owner present): earpiece AUDIBLE.** B2a + clean 31e5ef26e (RT5665 MX-7D=0x0101 at UAIF0
  link init; test a50-m10-b2h2-test 616b18207, BOOT 58013fd8…). Gate 07d: 0101, 113/113 controls, 6/6 tones, codec DAPM
  IF1 DAC2 -> DAC L2 -> Mono MIX -> MONOOUT on, IPC 38 -> 268, no faults. 6.18 USB link re-enumerates repeatedly: run
  collectors detached on the phone (`collect_b2h2r.sh` rerun in the same boot). `b2h2-results.json`.
- **B2h3 (2026-11-22 18:45, owner present):** + clean `cd4991938` (CLK_DIVIDER_ROUND_CLOSEST on AUDIF/UAIF0-2/DSIF;
  test `ea1b92041`). AUDIF 73728003 / UAIF0 BCLK 1536001 Hz = stock dividers /16, /48 (was 69391062/1508502). Owner
  missed the six scheduled tones, heard a same-boot replay. No faults. Detached collector survived USB drops.
  `b2h3-results.json`.
- **WIP `a50-m10-b2-wip`** now carries both fixes: `8af341da3` (MX-7D) and `4b59459bd` (dividers); `b2-wip-patches/0007-0008`.
  Clean `a50-audio` head `cd4991938`.
- **Phone last verified (B2h3):** stock restore 18:53:28, 4.14.194 up 18:53:42, pre-flight passed, fsck clean 7193 files.
  **No test active.**
- **B2b (2026-11-22 19:18, owner present): no speaker sound.** Gate passes (mtpotc/mtpex/Re25 in range), calibration
  equal to the private stock record before/after on both kernels; 114 stock speaker controls; side streams start. First
  TFA DSP write crashed the ABOX firmware (`data abort ... from calliope`, PC=0, R14 in the 0x80582000 window), then all
  IPC timed out. Collector bug (stale probe-only gate) needed a same-boot rerun (`collect_b2br.sh`). `b2b-results.json`.
- **Phone last verified (B2b):** stock 19:26:22, pre-flight passed, fsck clean 7205 files, calibration matches.
  **No test active.**
- **Comparison:** stock firmware log shows REALTIME_START -> `TFADSP_init` before the 1646-byte TFA blob is accepted
  (private stock window/DRAM/log in `src/m10/b2c2-stock/`). **B2b2** (stock stream timing, same images): the firmware
  reached `ERAP out channel start - SPK_Lib_On: 1` but faulted again before `TFADSP_init` (PC=0); its log shows IPC
  messages handled one per 4 ms tick, ~75 ms behind (stock: ~0.2 ms apart). 6.18 config lacks
  `CONFIG_HIGH_RES_TIMERS`, so `abox_process_ipc()`'s `usleep_range(10, 100)` lasts a tick. Stock restored, fsck clean,
  calibration unchanged. **B2b3** (`CONFIG_HIGH_RES_TIMERS=y`): the firmware now keeps pace with the
  kernel but still never ran `TFADSP_init` and faulted on the first TFA message. Cause: the stock DT loads `tfadsp.bin`
  (NXP speaker-protection library) into ABOX DRAM (`abox/ext_bin@0`, area 1, offset 0x502000); the 6.18 DT did not.
  **B2b4** (DT loads `tfadsp.bin`): `TFADSP_init` done, TFA blob executed,
  `tfadsp_is_configured()=1`, amp cold-started, no crash. The test's aplay/arecord side streams got EIO after 100 ms
  (6.18 ALSA no-progress timeout; ABOX consumes them, stock pointers stay 0), so the speaker path stopped. **B2b5** (same images; realtime streams started like the stock HAL): **speaker
  tone audible (owner)**; NXP library initialised, amp configured with the preserved calibration, speaker path held
  for the whole tone, no kernel errors. Stock restored, fsck clean. WIP has `a0cd8b066` (high-res timers) and
  `099037655` (tfadsp.bin DT node); clean `a50-audio` has `332858bf8` (high-res timers; tfadsp node waits for the TFA
  series). **Next:** headset/microphone paths recorded against stock, then CMGP clock disposition.
- **Next B2b:** enforce existing-calibration validation at startup, review/exercise DSP transport and select stock
  routes for a supervised low-volume tone. Do not merely disable probe_only before that review/gate. Fresh owner
  presence and pre-flight required for the next flash. Temporary CMGP fixed providers are prototype only;
  native clock integration or explicit disposition needed before final acceptance. M10.4 PulseAudio not started.
- **Clock prerequisite B2C passed:** unchanged B1 image measured identical CMGP registers at 80/150/390 s;
  IPCLK **99937500 Hz**, PCLK **199875000 Hz**, gates enabled. Corrected late capture timeout works.
  `b2c-results.json`. Same cable used successfully; no evidence establishes it is faulty.
- **Source candidate:** `src/m10/b2-kernel` **a50-m10-b2-wip/bedf87ffc**, clean. First five patches through
  **2ba9b7efa** are the B2a-tested changes. Sixth patch retains probe ID for status (B2a reports an unset field
  as 0x0000); **compiled, unflashed**. `reference/m10-audio/b2-wip-patches/`, 39 affected files replay exactly;
  first five source changes equal B2a. Native production handler ASan/UBSan tests 15 pass, size-check mutant rejected.
- **Test checkout:** `src/m10/a2-kernel` **a50-m10-b2a-test/95299e7f027a4c9b37523e1b4a804b978c9cdfb8**, clean.
  Clean `src/m10/clean-kernel` stays **a50-audio/a0a748616**, common **a50-usb/4fbb731f5**, clean. B1 branch retained.
  Dev `b2-dev-out` has no timed diagnostic and must not be flashed. Latest dev object includes unflashed patch 6.
- **Frozen B2a inputs:** BOOT `src/m10/boot-b2a.img` **1383b47f2368ee9f60717d1901b05b448eed7475cc21741cf0b700f91e156feb**
  (33337344 B), DT `dt-b2a.img` **4a3aadafc2eccca395f4efa92029cea6f45ceec6d690b8e669cb91802f4d0cb7**.
  26 hashes `b2a-inputs.json`, immutable `b2a-as-built/`, raw/session `b2a-raw/`, `b2a-session-codex.txt` under
  src/m10. Exact config delta vs B1: TFA9872/SEC_SND_SYNCHRONIZED_IPC/I2C_EXYNOS5=y; same cpio, DUMP_AFTER=420.
  Linked binary probe_only=1 and NVM setters return unsupported; guard tests pass. Do not overwrite old manifests.
- **Publication:** `reproduce/m10-a1/` remains A1 only; stable M9 unchanged. B2 source is exported, not promoted to
  final clean branch or a validated public profile. Full profile refresh still pending M10.4.
- **Outer Git:** prep **8386bcf** pushed before B2a, parent f889166. Follow-up saves B2a evidence and patch-6
  metadata correction; destination origin/main. Owner present, USB connected, Claude idle through tests.

## B1 completed handoff (2026-11-22)
- **Active ticket:** `tasks/M10.3-codec-amplifier.md`, in progress. **B1r2 completed on the same cable** with the
  unchanged B1 image. RT5665 binds, supplies and card enumerate correctly; no audio playback/capture yet.
  B1/B1r were failed transport attempts, preserved separately. Cable fault is **not established**.
- **B1r2 result:** RT5665 `4-001b` on physical 13890000.i2c (DT i2c_6; Linux adapter i2c-4), driver bound;
  AVDD/LDO42 enabled 1.8 V, MICVDD/LDO40 enabled 3.3 V. Card has **348 controls** (A2c 153), seven board switch/
  wakelock names; card0 PCM list exactly matches stock/A2c (7 playback, 5 capture). DSP rSK1 ready 22.965843 s,
  reset count 0, active; ABOX SysMMU IRQ count 0, IPC IRQs 38. Owner sees recognizable Ubuntu Touch greeter/UI.
- **Limits:** 129/133 HAL names present on stock are present here. Missing: two deferred BT SCO controls,
  Samsung `Debug Buffer Switch`, known codec `Disable NG2`; 13 other XML names are absent on stock too.
  `host-contract.md` corrected: Debug Buffer Switch exists on stock. VBAT maps to a dummy regulator; stock only
  manages the two measured rails, physical VBAT wiring unverified. Control names only, no value/routing/PCM test.
- **Regression:** at 150 s: 1318 direct padded DMA frames, no copy/fallback/acquire-timeout increments, one Lomiri,
  userdata rw, input nodes present, wlan0/hci0 present (Wi-Fi association/BT traffic not retested). Multi-user at
  168.300660 s, systemd running/0 failed units at 201 s. Dump reaches sync 431.084349 s, no oops/panic/SError/BUG/
  IOMMU fault signatures. Early boot-protocol and two iommu.c:612 WARNs already occur in A2c; not newly introduced.
- **Collector correction:** late snapshot rc 124 is explained by a **200 s timeout starting at uptime ~150 while
  waiting for uptime 390**; needs at least ~240 s plus query. Stream rc 124 is its 390 s budget after starting at
  ~38 s (data through 428 s). Host USB shows **no extra runtime re-enumeration** this run, only scheduled reset.
  Do not attribute these timeouts to the cable/USB without evidence. Fix future collector budgets (late >=300 s,
  stream past 431 s) before the next test; as-tested scripts and manifests are preserved unchanged.
- **Phone last verified:** stock restored automatically **2026-11-22 00:39:24 +06:00**, 4.14.194 boot **00:39:38**,
  live stock DTB/DTBO/baseline BOOT hashes all pass; fsck clean **7173/3440640 files, 1978996/13745152 blocks**,
  94% Charging, home Wi-Fi SSH verified. **No test active.** Owner present, USB connected, Claude idle throughout.
- **Next:** B2/TFA9872 preparation, after the owner calibration choice (container defaults vs factory values from
  read-only EFS + a new ADR). No EFS or calibration change performed; no speaker/headset/microphone claim yet.
  M10.2 remains closed; M10.3 stays in progress. Fresh presence and pre-flight before a future flash.
- **Evidence:** `reference/m10-audio/b1r2-results.json`, `b1r2-control-comparison.json`, redacted B1r2 run/live/stream/
  dump/host USB/fsck files; log `log/2026-11-21-M10.3-codec-amplifier.md`. Private raw/session:
  `src/m10/b1r2-raw/`, `src/m10/b1r2-session-codex.txt`. 25 hashes in `b1r2-inputs.json`; B1 23 and B1r 25 preserved.
- **Clean kernel:** `src/m10/clean-kernel` **a50-audio/a0a74861668643df7d5925bf4a161e60ac18ea31**, clean,
  16 commits after M9. B1's two additional patches in `reference/m10-audio/b1-clean-patches/`, exact affected-file
  replay verified on A2 clean e548f4301; B1r2 validates the test branch carrying the same changes. A2's 14 patches
  remain in `a2-clean-patches/`. Common remains **a50-usb/4fbb731f5**, clean.
- **Test kernel:** `src/m10/a2-kernel` **a50-m10-b1-test/a3f5bd537ff9135dcfc0125b3fab02c5bc0529ce**, clean.
  Frozen `src/m10/b1-as-built/`; BOOT `src/m10/boot-b1.img` **0bc9daa42d77be747fea56ee46dc8b85ae999b6ce3770a5343b633138c76de90**;
  DT `src/m10/dt-b1.img` **f73a47e5bb741cfcad601e95e331be7d840980f4c46c3141b57f0631aa52693b**.
  B1r2 image copies are byte-identical; config delta from A2c RT5665/RL6231 only, same runtime cpio. No new build.
  Backup hash rechecked earlier this session: 22cb95a536489c89a738cae3105859c041a15b298c4140c6a1a018883f7bd896.
- **Publication:** full public profile `reproduce/m10-a1/` remains A1 only; stable M9 unchanged. A2/B1 public profile
  refresh pending M10.4; exported patches do not imply a completed public B1 validation build.
- **Outer Git:** session parent **8ddd814** on main (B1 prep/transport evidence pushed). This follow-up saves B1r2's
  successful same-cable retry, collector timing correction and verified restore; destination origin/main.

## Earlier handoff (2026-11-20, M10.2 A1 fixed; superseded by A2)
- **Active ticket:** `tasks/M10.2-abox-core.md`, in progress. **A1 normal DSP boot passes. Next A2:** DMA/interface
  children plus a test card matching stock seven playback/five capture PCMs. No A2 build/flash yet; codec/amp and
  PulseAudio remain M10.3/M10.4. Read the latest result in `log/2026-11-20-M10.2-abox-core.md` before older summaries.
- **Root fix:** DISPAUD CMU lacked its register-bus parent reference. The early DPU SysMMU probe could enable/release
  that shared parent before ABOX access; late DECON binding held it on. One `.clk_name = "dout_cmu_dispaud_disp"` line
  uses the standard upstream helper. A1i stalled at the post-version checkpoint; A1k reaches it with only that line
  changed. Normal A1l's tree equals failed A1b plus the same line. No delay, PLL rate/DVFS, config, DTB or runtime change.
- **A1l result:** ABOX probe complete **0.389565 s**, DSP rSK1 ready **21.939198 s**, readable version/reset count
  rSK1/0, runtime active. At 150 s: ABOX SysMMU faults 0, IPC IRQs 38, 1214 direct-DMA frames with no copy/fallback/
  acquire-timeout increments, input nodes present, userdata rw. Owner sees recognizable Ubuntu Touch UI. Multi-user
  reached **166.823078 s**, systemd running at 201 s. Timed work at **431.072694 s** (configured 420), sync completes;
  recovered log has no kernel/IOMMU fault signatures. `reference/m10-audio/a1l-results.json`.
- **Phone last verified:** stock DTB/DTBO/baseline BOOT restored **2026-11-20 22:10:22**; **4.14.194** booted
  **22:10:35**, home **192.168.0.171**, **100% Charging**. All three live partition hashes pass; fsck clean
  **7145/3440640 files, 1991708/13745152 blocks**. No test or root operation active. No button action needed.
  Owner was present/USB connected/Claude idle for each run. Fresh presence/pre-flight required for future phone work.
- **USB limitation:** extra re-enumeration **22:07:16**, descriptor timeouts -110, returns **22:07:38** on 7-1.
  SSH stream ends around 270 s; 390 s snapshot lost. Kernel still completes dump/reset at 431 s. Existing M12 USB
  issue remains; do not claim the port move fixed it. WLAN/hci0 present, but Wi-Fi association/BT traffic not retested.
- **Clean kernel:** `src/m10/clean-kernel` **a50-audio/c371ef348fb2a2c4f8a1131a2ab12afeb32c662e** (seven audio/clock
  commits after M9 e7a5bee84), clean. Fix cherry-picked from test 19572bce5. Test workspace `src/m10/a1i-kernel` now
  **a50-m10-a1l-test/7412efd15a6ece3b618783090f95a554d96c57ef**, clean. Common remains a50-usb/4fbb731f5, clean.
  A1g/A1h worktrees retain their diagnostic branches. A1j was built but not flashed; A1i0 was a host-only control.
- **Frozen A1l inputs:** 27 hashes verified; `src/m10/boot-a1l.img`
  **e999612e0aced2706d4d7559b00fbedcde8aa1290e8ceac77893a25271ea72b7**; DT `src/m10/dt-a1l.img`
  **9c04b0e045d5fe86274f56c13634922659201dd00ba01879260cd7221bf1fe65**. Immutable Image/config/DTB/cpio/System.map
  under `src/m10/a1l-as-built/`; raw/session `src/m10/a1l-raw/`, `src/m10/a1l-session-codex.txt`. Reused output
  `src/m10/a1i-out` can change; use frozen copies/source commits. Incremental helper validated byte-identical at
  unchanged A1i source. `reference/m10-audio/incremental-builder-control.json`.
- **Public build passed:** separate experimental **77-patch** profile `reproduce/m10-a1/`, **103** pinned inputs,
  clean tree **d3cf6e2ee82c5bc0e10c700112f41dff7eed8c70**. `python3 -I tools/reproduce_m10_a1.py --jobs 16` needs no
  private inputs. Full build/guard/sense/config checks pass; DTB/I5 cpio match A1l. Exact clean Image not phone-flashed.
  Validation `reference/m10-audio/publication-a1-validation.json`; workspace `src/m10/publication-a1/`. Seven clean
  patches in `reference/m10-audio/a1-clean-patches/`; stable 70-patch M9 lock/build remains unchanged.
- **Before ticket closure:** A2 PCM/card acceptance and explicit remaining regressions; GIC supplier-readiness guard
  and fault worker's GPR MMIO reads still need review. The clock fix resolves the boot stall, not all recovery paths.
  ADR-0005 audio-HAL deferral remains; no phone speaker/microphone test or calibration change performed.
- **Outer publication source commit:** **9483297** on main, after parent 1bdebd8, records all prior Claude M10.2
  evidence/tools plus the Codex fix/tests and validated public A1 profile. This final handoff follows it; destination
  **origin/main**. Earlier Claude work preserved; source/test branches are not merged into common.

## Earlier handoff (M9 done; M10.1 done; superseded by M10.2 review)
- **M9 done** (`docs/05-plan.md` M9 DoD evaluation). Wi-Fi S4 (M9.3) and Bluetooth S8 (M9.4: native BlueZ, ADR-0008;
  owner's speaker paired, A2DP tones heard) proven together on one boot (M9E2) with factory Wi-Fi/Bluetooth addresses
  from a transient read-only EFS mount (ADR-0009, runtime I5).
- **Source:** clean `a50-wlbt` (worktree `src/m92/clean-kernel`) head `e7a5bee84`; `patches/` 70, tree `4d65d4a5`;
  `reproduce/m8` builds the I5 runtime (public build byte-identical to M9E2). Test branch `a50-m92-w1-test`
  (`src/m92/test-kernel`); M9E2 BOOT `d41aa7f5f6a6bd6480dab133f3f5f2f48c3e3d80e820b511369759f617e0ade4`.
- **Phone:** stock 4.14.194 restored 2026-11-20 15:32:38, post-flight passed, fsck clean 7126 files, home
  **192.168.0.171**. Stock Bluetooth switched back off (urfkill). The M9E2 cleanup may have removed the shared JBL
  pairing; the owner re-pairs once on stock if so.
- **Open beyond M9:** Wi-Fi power-save/latency tuning; stock profiles bound to `swlan0` (one-time reconnect on 6.18);
  masked router BSSIDs remain in pushed history of earlier M9.3/B1 copies (owner decision on history rewrite).
- **Next:** M10 audio (S6). **M10.1 done** (`reference/m10-audio/host-contract.md`): codec on mainline `rt5665.c` (covers
  the HAL's mixer controls except `Disable NG2`); port ABOX core, vogue machine driver and TFA9872 (no kernel EFS
  I/O). Next ticket **M10.2 ABOX core** (boot tests A1, A2). Open owner decision: factory TFA calibration from EFS.

## Earlier handoff (superseded by M9 closure)
- **M9.3 done** (`log/2026-11-19-M9.3-wifi.md`): S4 on 6.18 (WPA2, DHCP, SSH over Wi-Fi, reconnect, rfkill off/on
  power-cycles the chip and reconnects in 3 s, private ioctls rejected, regression snapshot clean). Publication 66
  patches (tree 7574d5e9), public build passed. Open: `swlan0`-bound stock profiles (owner decision; recommend
  one-time reconnect), random MAC, power-save tuning.
- **Phone:** stock 4.14.194 restored 2026-11-20 00:53:14, post-flight passed, fsck clean 7072 files, home
  **192.168.0.171**.
- **Next:** `tasks/M9.4-bluetooth.md` — needs the owner's plan decision first (native BlueZ via stock `scsc_bluez.c`
  hci_dev vs the plan's bluebinder path; see M9.1 contract §6 B).
- Untouched uncommitted files from another session: `CLAUDE.md`, `docs/05-plan.md`, `docs/09-ut-blockers.md`,
  `docs/10-after-kernel-plan.md`.

## Earlier handoff (superseded)
- **M9.3** (`log/2026-11-19-M9.3-wifi.md`): W2s2 joined the owner's home network on 6.18 (WPA2, DHCP), SSH over
  Wi-Fi, ping 19/20, 20 MB in 17.5 s, NM disconnect/reconnect, faults 0. Found/fixed an RTNL self-deadlock
  (W2/W2d: custom regd applied from ndo_open). Stock-saved profiles are bound to `swlan0`; the test unbound them in
  NetworkManager memory only.
- **Branches:** clean `a50-wlbt` (worktree `src/m92/clean-kernel`) adds ec79c85aa import, d2ef6dd88 6.18 build,
  77a2a5e89 regd-outside-RTNL. Test `a50-m92-w1-test` (worktree `src/m92/test-kernel`). Build
  `python3 -I tools/m93/build_w2.py TAG [EXTRA]`; run `tools/m93/run_w2.sh IP TAG`. W2s2 BOOT = W2r
  `fb5cc4d18b6f8b903215b0ff2c6bea94066d3fb459f6443d26021ed5d4ff54cb`.
- **Phone:** stock 4.14.194 restored 20:17:00, post-flight passed, fsck clean 7067 files, home **192.168.0.171**.
- **Next (M9.3):** latency/throughput limits (vs stock), decide the `swlan0` profile handling, explicit regression
  and device-node checks, clean defconfig + publication refresh for Wi-Fi.

## Earlier handoff (superseded by M9.3 progress)
- **M9.2** (`log/2026-11-19-M9.2-scsc-core.md`): W1r2 booted the WLBT chip on 6.18 — CFG_REQ, EL3 SMC returns 0,
  firmware `MM_START_IND` (S620_E9610_R3-1_Y21W46A), NULL service start/stop, no faults. W1 found a DT alignment-cell
  bug, W1r a missing 9610 mif op (oops); both fixed.
- **Branches:** clean `a50-wlbt` (worktree `src/m92/clean-kernel`): 83722e28e import, e63c489a1 6.18 build,
  b6da265a1 DT, 39882bf6a recovery ops. Test `a50-m92-w1-test` (worktree `src/m92/test-kernel`) = H1 + same.
  Build `python3 -I tools/m92/build_w1.py TAG [EXTRA_CMDLINE]`; run `tools/m92/run_w1.sh IP TAG`. W1r2 BOOT
  `03650b8744c1af3145d04631b11bd08d4c92aa7a807f666a6212bc037c664467`, DT `2b674f36…6313442`.
- **Phone:** stock 4.14.194 restored 15:45:19, post-flight passed, fsck clean 7056 files, office **192.168.181.225**.
- **W1d (16:02-16:11):** chip boot repeated cleanly; the 39 s WARN is the known M7.2 display IOMMU warning, not SCSC.
  Phone restored 16:11:02, post-flight passed, fsck clean 7064 files.
- **Clean `a50-wlbt` now:** 6e0728cdf, b236e859f, acea68972, 3b5a7881d, 5032bdd3b (defconfig).
- **Publication:** 63 patches (tree 15fa201b), `reproduce/m8` config/lock refreshed, full public build passed
  (`reference/m92-scsc-core/publication-build-results.json`).
- **M9.2 done** (owner "yes"); device-node/ABI criterion moved to M9.3/M9.4.
- **Next:** `tasks/M9.3-wifi.md` — Wi-Fi station mode on upstream cfg80211 (boundary C of the M9.1 contract).

## Earlier handoff (2026-11-19, M9.1 done; superseded by M9.2 progress)
- **M9.1 done** (`log/2026-11-19-M9.1-scsc-contract.md`, result `reference/m91-scsc/contract.md`). Stock SCSC
  hardware/firmware/consumer contract recorded; chip boot is source-derived (the stock touch log stream overwrites the
  1 MiB ring before SSH at 19 s, and an rfkill toggle restarts only the Wi-Fi service). Wi-Fi service start measured.
- **Owner direction (2026-11-19):** prioritize 6.18-native mechanisms; port old Samsung features only when absolutely
  necessary. Boundary: core (M9.2) on request_firmware/wakeup_source/arm_smccc; Wi-Fi station via upstream cfg80211
  incl. SAE (M9.3); Bluetooth preferred as native `hci_dev` (stock `scsc_bluez.c`), which needs a plan change before
  M9.4 because the plan names bluebinder.
- **Phone:** stock 4.14.194, office **192.168.181.225**, Wi-Fi connected. Owner-initiated stock reboot at ~13:50 (C3)
  and one Wi-Fi rfkill block/unblock (C4); no flash, no root operation, no partition change since the S1 post-flight.
- **Next ticket:** `tasks/M9.2-scsc-core.md` (todo). First boot W1 = core only. Do not start without the owner.
- Kernel branches unchanged: common a50-usb/4fbb731f5, input a50-input/3bd96025f, runtime a50-m84-h1-test/3c651aa2d.

## Earlier handoff (2026-11-19, M8 done; superseded by M9.1)
- **M8 done** (owner: "Close M8 now"). DoD S3 (touch + power/volume keys) met by M8.5 S1; see the M8 DoD evaluation and
  plan change in `docs/05-plan.md`. M8.3 and M8.5 tickets done. Moved to M12: hall SW_LID/SW_MACHINE_COVER transitions
  (needs any magnet or cover), the intermittent USB re-enumeration (key-independent; S1 DWC3/UDC trace and
  `tools/m85/phone_usb.sh` are the starting point), and a controlled app open/close memory-retention review.
- **No phone boot for this decision.** Phone state unchanged from the S1 restore below (stock 4.14.194, fsck clean).
- **Next ticket:** `tasks/M9.1-scsc-contract.md` (todo; Wi-Fi/Bluetooth SCSC contract). Do not start without the owner.
- Kernel branches unchanged: common a50-usb/4fbb731f5, input a50-input/3bd96025f, runtime a50-m84-h1-test/3c651aa2d.
  Public build: `python3 -I tools/reproduce_m8.py --jobs 16` (58 patches).

## Earlier handoff (2026-11-19, M8.5 S1 complete; superseded by M8 closure)
- **Active ticket:** `tasks/M8.5-input-integration.md`, in progress. S3 touch/key delivery, interactive ten-minute soak,
  public build refresh and M9 ticket drafts recorded. **M8 is not closed:** hall transitions remain untested (owner has
  no magnet/cover), shared USB resets remain unresolved, and retained buffers need a controlled app-cycle review.
  Next: fixed-workload open/close cycles with a longer idle tail; hall events when a magnet/cover is available; retain
  calibrated USB tracing on the next authorized boot. Do not change keys or infer a new hall/power acceptance exception.
- **Phone last verified:** stock DTB/DTBO/baseline BOOT restored **2026-11-19 13:15:38**; stock **4.14.194** booted
  **13:15:52**, office **192.168.181.225**, **98% Charging**. Post-flight all partition hashes passed; fsck clean
  **7056/3440640 files, 1991960/13745152 blocks**. Complete 900 s dump recovered. No test active, no button action needed.
  Presence/USB/Claude idle were confirmed for S1; confirm owner presence again before a future flash.
- **S1:** flashed **12:59:47**, USB SSH **13:00:46**. Owner unlocked/used Settings and reports **"Responsive throughout;
  apps closed; back at Home."** Conservative interaction >=600 s; 25 samples span **720.63 s**. UI PID 3391 stayed stable,
  restart counts/faults zero, systemd running, four native/compat kbase/ION checks rc 0. Direct DMA **1996 -> 7025**,
  copy/fallback/skip/acquire-timeout counters zero. Volume Up/Down each three clean pairs, Power five pairs, no repeats.
  Power screen action remains deferred while repowerd is masked until M12. No raw touch coordinates or PIN saved.
- **Memory limit:** DMA-BUF 40 -> peak 92 -> 86 objects (181657600 -> peak 438743040 -> 409055232 bytes);
  UI RSS 407392 -> peak 495960 -> 487188 KiB. Some reclamation, but variable apps/short post-close interval cannot
  establish leak freedom or a leak. Follow-up stays open; no speculative allocator change made.
- **USB positive trace:** one extra re-enumeration **13:03:46**, port 7-1/PCI 06:00.4, device 5 -> 6. SSH/UI survived.
  DWC3 Suspend[U3] **219.553362 s**, Reset **219.702285**, ConnectionDone **219.752320**, Reset **219.818289**,
  ConnectionDone **219.864836**; calibrated trace has no loss or explicit gadget-disconnect call. Host power counters
  unchanged. This records a bus-reset sequence, not its cause; no USB fix established. Timed reset at 13:15:13 excluded.
- **Frozen S1 inputs:** `tools/m85/build_s1.py`, H1 source/config, only dump timer **420 -> 900**. BOOT `src/m85/boot-s1.img`
  **000cb21ecc255eb6afd12eb3cb0c437feafc97459226d58e00dc7126dd313507**; DT `src/m84/dt-h1.img`
  **44ef8b0a81dea33ef83683b9466c3b06234689e0fb0af511b9fc8abccde25151**. Config `src/m85/s1-out/.config`, portable copy
  `reference/m85-integration/s1.config`. All **34** hashes in `s1-inputs.json` reverified. Raw `src/m85/s1-raw/`, session
  `src/m85/s1-session.txt`, prep `src/m85/prep/`; public evidence/checklist/results under `reference/m85-integration/`.
- **Publication refresh passed:** **58** clean patches replay to tree **d83ea52a1943c916a3e2634acc2df8f9a381114e**;
  `reproduce/m8` LED config/lock/DTB expectation refreshed together, **81** inputs checked. Full public build, config,
  DTB/cpio and guard/sense checks passed in `src/m85/publication/`. Exact clean Image has not been flashed.
  New clone: `python3 -I tools/reproduce_m8.py --jobs 16`. M9.1-M9.4 tickets are **todo**, no M9 work started.
- **Publication source commit:** **a965dc9**, following parent 8edaa5d, records S1 evidence/tools and the validated
  58-patch build refresh. This final handoff/formatting update follows it; destination **origin/main**.
  Shared/kernel branches unchanged and clean:
  common **a50-usb/4fbb731f5**, input **a50-input/3bd96025f54968b930418c756141d958ad842495**,
  runtime **a50-m84-h1-test/3c651aa2d21cd9d7f1cde16e3251b4eb785bbd93**.
  See `log/2026-11-19-M8.5-input-integration.md` and `reference/m85-integration/s1-results.json`.

## Earlier handoff (M8.4 done; superseded)
- **Phone:** stock 4.14.194 (home **192.168.0.171**), post-flight passed, fsck clean 7096/3440640 files (H1 restore
  01:57:37). No test active.
- **M8.4 done** (`log/2026-11-19-M8.4-hall-vibrator.md`): vibrator works (`gpio-leds` "vibrator" on gpa2-1 + transient
  trigger = the `/sys/class/leds/vibrator` interface of the vendor HAL and hfd-service; owner felt three 300 ms pulses).
  Hall sensors (`gpio-keys` SW_LID gpa0-3 / SW_MACHINE_COVER gpa0-2) probe and are registered with logind; events not
  exercised (no cover/magnet), moved to M8.5 (owner Option B). Clean commits `67480e78f`, `3bd96025f` on `a50-input`.
- **Publication:** `patches/` intentionally stays at the 56-patch series locked by `reproduce/m8/sources.lock.json`
  (re-exporting rewrites all headers and breaks the locked hashes). M8.4 patches are in
  `reference/m84-hall-vib/h1-clean-patches/`. M8.5 does the 58+ patch export, lock refresh and validation build.
- **M8.3:** key checks met; still open only for the intermittent USB re-enumeration, which also occurs without keys
  (Codex K5/K6), cause unverified.
- **Next ticket:** `tasks/M8.5-input-integration.md`: S3 checklist, interactive soak, hall events with a magnet, M8
  publication refresh, M8 DoD.
- **Test base:** `a50-m84-h1-test` (`3c651aa2d`) = K1 test kernel + `a50-input`; build `tools/m84/build_h1.sh`; BOOT
  `src/m84/boot-h1.img`, DT `src/m84/dt-h1.img`.

## Earlier handoff (M8 publication, Codex; superseded)
- **Owner task:** commit and push all findings with a build path usable from a new clone. No new phone boot authorized
  or performed. Home **192.168.0.171** answers read-only phablet SSH, reports stock **4.14.194** at 01:13. Partition
  post-flight/fsck last verified during K8 below; no new root/partition check today.
- **Build gap fixed:** `tools/reproduce_m8.py` + `reproduce/m8/` reconstruct the 56-patch clean M8 tree and I4 runtime
  from pinned public inputs. README/patch docs point at this entry point. The exact clean image has not been flashed.
- **Validation:** two full builds passed: `src/m83/publish-m8-bootstrap/` and fresh staged-snapshot clone
  `src/m83/publication-clone/` with its own generated source/payload/output. All 79 locked inputs match publication;
  normalized configs/raw DTB/cpio match across paths. Optional caches supply only locked public Git objects/downloads.
  Storage/sense tests, tracked-input drift and dirty-source refusal checks pass. Public asset URLs return HTTP 200.
- **Publication source commit:** **4cea5f0bc2615dea7d83edd57f194b5b93d112b3** on outer **main** includes all M8.3
  K1-K8 evidence/tools, 56-patch export and public M8 build. This handoff update follows that source commit; remote
  destination is **origin/main**. `log/2026-11-19-publish-m8.md` and `reference/m83-publication/` record validation.
- **New-clone command:** `python3 -I tools/reproduce_m8.py --jobs 16`; prerequisites/outputs in `reproduce/m8/README.md`.
  No private inputs or existing src required. Clean build passes, but its exact Image has not been phone-flashed.
- **Kernel branches unchanged:** common a50-usb/4fbb731f5, clean a50-input/e0c2610f9, runtime a50-m83-k1-test/3a823204f.
  M8.3 remains open on the intermittent shared USB issue; key acceptance checks/export are met. M8.4 not started.

## Earlier handoff (2026-11-18, M8.3 K8 complete; superseded for publication state)
- **K8 result:** same P3 image/cable/5-1 port, calibrated private trace repeat. Zero unexpected host USB
  disconnects/errors; device number 18 throughout. Trace contains exactly START (38.932908 s) and END (390.951245 s)
  markers; all eight event enables read back 1 at both ends, zero losses/overruns on all CPUs. No USB-controller events
  occurred, so no positive USB-event control/fault diagnosis. 341 UDC samples (38.94-389.76 s), all configured; 399 host
  power samples active with unchanged suspend counters. K7/K8 clean does not clear K5/K6's intermittent failure.
- **Active ticket:** `tasks/M8.3-keys.md`. All three key acceptance checks met, including clean numbered export;
  ticket remains in progress on shared USB investigation. M8.1/M8.2 done with recorded M12 deferrals. M8.4 not started.
- **Earlier K7 result:** same P3 image/cable/5-1 port as K6 with private DWC3/UDC tracing. **Zero unexpected runtime USB
  disconnects**, zero address errors; device number 13 throughout. 343 phone UDC samples (37.38-389.08 s), all configured.
  Trace enabled at 37.388 s, frozen at 390.13 s, zero events and zero buffer overruns/drops on all 8 CPUs. Fault did not
  recur, so no diagnosis or fix established. No positive USB-event control after trace setup; instrumentation may affect
  timing. A clean run does not clear the intermittent failure in K5/K6.
- **Earlier controls:** unchanged P3 without keys reproduces on both paths: K5 four extra disconnects on 7-1/PCI
  06:00.4 (setup-address -71); K6 one on 5-1/PCI 06:00.3 at 18:19:48 (device 5->6). K6 host suspend counters remain
  unchanged across the drop, so ordinary host autosuspend is unsupported as its trigger. Root cause remains unverified.
  No spare cable available. Do not change keys/wakeup-source or claim another port fixes it.
- **Phone last verified:** stock DTB/DTBO/baseline BOOT restored **2026-11-18 19:23:16**; baseline **4.14.194** booted
  **19:23:31**, office **192.168.181.225**, **100% Charging**. Post-flight passed; fsck clean **7090/3440640 files,
  1991478/13745152 blocks**. Complete timed dump recovered; no recorded kernel fault signatures. No test active.
- **Next:** retain calibrated same-image USB tracing for an actual recurrence before choosing a code/power change.
  No further boot prepared/run. No button presses or recovery action needed during K8; owner instructed to keep setup
  still. Do not alter keys/wakeup-source or claim another port fixes the issue. Owner presence needed for future phone work.
- **K8 evidence:** `log/2026-11-18-M8.3-keys.md`, `reference/m83-keys/k8-results.json`, host USB/power records,
  `k8-late.txt`, `k8-trace-setup.txt`, `k8-trace-final.txt`, `k8-trace-stats.txt`, `k8-usb-trace.txt`, `k8-run.txt`,
  `k8-baseline-fsck.txt`. Raw `src/m83/k8-raw/`, session `src/m83/k8-session.txt`, prep `src/m83/k8-prep/`.
  Runner/watch/collectors/samplers/fsck rc 0; stream 124 expected. Live host follower terminated after restore as
  designed; unrelated host logs not published. All 24 input hashes verified after run. No source/functional change.
- **Inputs:** BOOT `src/m82/boot-p3.img`
  **295da8967c1afce2e6aeaad9b1a181023d7210919925296508ec3629892027ad**; DT `src/m82/dt-p3.img`
  **dbb3ce70d2d8e796c93af97cd1cf1ddacf626cc234c6f2526b46ff573dc643b4**. Same cable/current port 5-1/PCI 06:00.3.
  `tools/m83/run_k8.sh`, `collect_k8.sh`, `k8_phone_side.sh`, `watch_host_usb.py`. Private a50_k8 trace instance,
  64 KiB/CPU, boot clock, event & 1 DWC3 device-event filter plus seven UDC state/control events; no USB payloads.
  Backup freshly rehashed before K8: **22cb95a536489c89a738cae3105859c041a15b298c4140c6a1a018883f7bd896**.
- **Export complete:** patches **0001-0056** replay against ACK d9a614fed to **a50-input/e0c2610f9** tree
  **a92a29f0bfc9e99b91ab8184c8b9a781e7b0d8ad**. New 0055/0056 keys; first 54 only change Subject totals /54 -> /56,
  code payloads verified unchanged. `reference/m83-keys/clean-patch-replay.txt`, `clean-patch-inputs.json`. README and
  patches README updated. Power-key screen blanking stays deferred while repowerd is masked until M12.
- **Git:** outer HEAD **99b81eb**; all M8.3 K1-K8 tools/log/evidence, export and handoff edits uncommitted. No commit/push.
  Kernel worktrees checked clean: common **a50-usb/4fbb731f5**, `src/m75/runtime-kernel`
  **a50-m83-k1-test/3a823204f**, `src/m81/clean-kernel` **a50-input/e0c2610f9**. No build or branch switch.
- **Open owner question (from 2026-11-17):** history rewrite for `ccc4e48`/`f68ca87` identifiers, undecided.

## Earlier handoff (M8.2 done; next M8.3; superseded)
- **Phone:** stock 4.14.194 (office **192.168.181.225**; home 192.168.0.171), post-flight passed, fsck clean
  7071/3440640 files. No test active.
- **M8.2 done:** touch works on 6.18 (owner operated Lomiri by touch). Mainline `melfas_mip4` + format 8 + DT
  event-format fallback + zero-size fix; `patches/` 0001-0054 reproduce tree `a1fc593a`. Blank-state power and the
  start-up empty-interrupt storm moved to M12 (owner Option A, plan change). Log `log/2026-11-18-M8.2-touch.md`.
- **Next ticket:** `tasks/M8.3-keys.md`. Live DT has `gpio-keys`; M4.4 used gpa1-5 (vol up), gpa1-6 (vol down),
  gpa1-7 (power) but never booted with them; confirm against stock DT/4.14 source (power key may come from the PMIC).
  evdev is already enabled; `CONFIG_KEYBOARD_GPIO` (needs `INPUT_KEYBOARD`) is not yet.
- **Test base:** `a50-m82-p3-test` (`edd18a66c`; TEST ONLY READY_STATUS probe on top of P1 + `a50-input`); build
  `tools/m82/build_p3.sh`. Clean branch `a50-input` (`src/m81/clean-kernel`).
- **Open owner question (from 2026-11-17):** history rewrite for `ccc4e48`/`f68ca87` identifiers, undecided.

## Earlier handoff (M8.2 touch works; superseded)
- **Phone:** stock 4.14.194 (office **192.168.181.225**; home 192.168.0.171), post-flight passed, fsck clean
  7071/3440640 files. No test active.
- **M8.2 P3r:** touch works on 6.18; the owner operated Lomiri by touch (System Information showed 6.18, Terminal
  opened). Mainline `melfas_mip4` + event format 8 + DT event-format fallback + zero-size fix; DT node with the LDO
  (gpg3-1) as chip enable and gpa0-0 level-low IRQ; evdev enabled. `patches/` 0001-0054 reproduce tree `a1fc593a`.
  Log `log/2026-11-18-M8.2-touch.md`.
- **Open in M8.2 (acceptance 3):** the controller stays powered when the panel blanks, and it storms with empty
  interrupts (INT held low, READY_STATUS 0xa0) from probe until the first touch; stock storms too (265k IRQs) but is
  quiet later. Decide whether to fix now or carry with M12 power work.
- **Test base:** `a50-m82-p3-test` (`edd18a66c`) = P1 test kernel + `a50-input` + TEST ONLY READY_STATUS probe; build
  `tools/m82/build_p3.sh`; BOOT `src/m82/boot-p3.img`, DT `src/m82/dt-p3.img`. Clean branch `a50-input`
  (`src/m81/clean-kernel`).

## Earlier handoff (M8.1 done; superseded)
- **Phone:** stock 4.14.194 (office **192.168.181.225**; home 192.168.0.171), post-flight passed, fsck clean
  7060/3440640 files. No test active.
- **M8.1 done** (`log/2026-11-18-M8.1-i2c.md`): the M4.4 freeze bisects to the 6.18 CMU_PERI clock driver (T1 vs T3,
  hard lockup caught by the buddy detector). ADR-0007 keeps CMU_PERI in the bootloader's state with fixed PERI clocks
  (CMU_PERI control moved to M12). Clean branch `a50-input` (worktree `src/m81/clean-kernel`): I2C buses 0/1/3/4/6 +
  defconfig; `patches/` 0001-0048 reproduce tree `aa8bfbcf`. T4 on the phone: all five buses probe, session healthy.
- **Next ticket:** `tasks/M8.2-melfas-touch.md`. The touch controller (0x48 on `i2c@13870000`, now `i2c-3`) NACKs:
  first describe and enable its supply (`tsp_ldo_en`, a GPIO `regulator-fixed` in stock dtbo.3 ~2196), then choose the
  driver (mainline `melfas_mip4`/`mms114` vs Samsung `mss100`), never writing controller firmware.
- **Test base:** test branch `a50-m81-t4-test` (`3ef73d12e`) = I4 test kernel + `a50-input`; build `tools/m81/build_t4.sh`
  (T1 config: I2C + lockup detectors with panic); BOOT `src/m81/boot-t1.img` (Image identical), DT `src/m81/dt-t4.img`.
  Runners need a tmpfs sized for their tools (two static tools are 2.2 MB each).
- **Open owner question (from 2026-11-17):** history rewrite for `ccc4e48`/`f68ca87` identifiers, undecided.

## Earlier handoff (M7 done; superseded)
- **Milestone:** M7 closed (owner accepted Option A, 2026-11-18): DoD met with limits, recorded in `docs/05-plan.md`
  (M7) and `tasks/M7.5-graphics-integration-soak.md`. Evidence: `log/2026-11-18-M7.5-i3-handler-startup.md`.
- **Phone:** stock 4.14.194 (home **192.168.0.171**), post-flight passed, fsck clean 7070/3440640 files. No test active.
- **Next ticket:** `tasks/M8.1-real-i2c.md`: real I2C froze 6.18 in M4.4 (tests 2/3, no log); touch (`melfas,mms_ts`
  0x48 on `i2c@13870000`) depends on it. Start from `log/2026-11-10-M4.4-buses.md` and `docs/08-open-questions.md` #8.
- **Current test base:** I4/S1 images (I0 kernel source on `a50-m75-i0-test` + ADR-0005/0006 runtime,
  `tools/m75/build_i4.sh`/`build_s1.sh`). Clean driver stack: `patches/` 0001-0045 (tree `81fe4953`); the ADR-0005/0006
  hooks live in the runtime (`tools/m75/make_i4_runtime.py`), not in `patches/`.
- **Open owner question (from 2026-11-17):** serial-prefix regex in `ccc4e48` and `androidboot.em.did` in `f68ca87`
  remain in history (redacted in the tree); rewrite or not is undecided.

## Earlier handoff (S1 soak complete; superseded)
- **Active ticket:** M7.5. No test active; phone on stock 4.14.194 (home **192.168.0.171**), post-flight passed, fsck
  clean 7070/3440640 files.
- **S1 (ten-minute soak, I4 image with a 900 s timer):** regressions pass (kbase 12/12, ION 64/32, gralloc/hwcomposer,
  userdata rw); Lomiri and handler same PIDs from READY (52 s) to 720 s with 0 restarts, systemd running/0 failed,
  dma-buf/fds/RSS flat, 0 fault signatures, Mali IRQs active. Light load: idle greeter, no touch (M8).
  Log: `log/2026-11-18-M7.5-i3-handler-startup.md`, sections "S1" and "M7.5 acceptance evaluation".
- **Open for the owner:** accept Lomiri's GLES compositing as S2's "equivalent" of glmark2 (or require a GL client run),
  and accept the light-load soak; then close M7 and write the M8 tickets.
- **Images:** I4 `src/m75/boot-i4.img` (session), S1 `src/m75/boot-s1.img` (900 s timer); DT `src/m73/dt-g1.img`.

## Earlier handoff (I4; superseded)
- **Active ticket:** M7.5. No test active; phone on stock 4.14.194 (home **192.168.0.171**), post-flight passed, fsck
  clean 7064/3440640 files.
- **I4 result:** with ADR-0005 (PulseAudio without the audio HAL) and ADR-0006 (placeholder over `libgsthybris.so`,
  now **accepted**), the telephony handler is active at 42.8 s, Lomiri READY at 48.2 s, session targets active, stable
  to 330 s, systemd `running` with 0 failed units. Log: `log/2026-11-18-M7.5-i3-handler-startup.md`, section "I4".
- **Image:** `tools/m75/build_i4.sh` (I0 kernel + `src/m75/i4-runtime`), BOOT `src/m75/boot-i4.img` `6ee6c0fe…`,
  DT `src/m73/dt-g1.img`.
- **Next action:** the ten-minute UI soak on the I4 image (M7.5 acceptance 2): needs a longer timed-dump window than
  420 s, renderer evidence (Lomiri's GL renderer line, DMA counters), fence/memory sampling, and the M6
  allocator/ION/storage/USB regression checks. Owner says "present, flash <name>" before each flash.
- **Gaps:** `gst-inspect-1.0` is absent on the rootfs; touch is M8; no audio (M10) or hardware codecs (M13).

## Earlier handoff (I2/I3; superseded)
- **Active ticket:** M7.5 remains open; no ten-minute soak or stable normal session yet. **I2 committed as 2fe93af**
  (verified audio deferral and corrected diagnosis), no push. I3 tools/evidence/handoff are uncommitted.
- **I3 result:** original handler has one thread; stock control has four. Startup environment matches stock. No QPA
  plugin/libmirclient appears in early maps; the same-environment 25-second debug copy times out with zero Qt/Mir/
  Wayland output. Both handler bus names were unowned before that copy; its group was terminated/reaped. No original
  service restart or display-backend change. GUI-plugin explanation is unsupported by this run.
- **Concrete blocking lead:** at uptime 295.11, restarted handler **11330** waits in ppoll with direct child **11333**,
  gst-plugin-scanner, six threads/futex wait. Executable return-site candidates and installed-library symbol checks
  identify **libgsthybris -> media_codec_list_count_codecs -> Stagefright codec list -> IOmxStore/HIDL getService**.
  The candidate at plugin offset 0x92d8 is immediately after its call to codec enumeration. Android vendor.media.omx
  is restarting and IOmxStore/default unavailable. This is not a formally unwound backtrace or a tested repair.
- **Other results:** PulseAudio/pactl stay responsive with unchanged ADR-0005. Normal handler/Lomiri still time out.
  Final display **19,760 direct DMA frames**, zero copies/fallbacks/skips/acquire/frame/shadow timeouts; no recorded
  kernel/GPU/SysMMU fault or fence wait. Userdata rw. No acceptance box newly closed from this diagnostic alone.
- **Phone last verified:** normal timed Download **01:18:51**, stock DTB/DTBO/BOOT restore **2026-11-18 01:19:08**,
  baseline **4.14.194** boot **01:19:22**, home **192.168.0.171**, **100% Charging**. Partition post-flight passed;
  fsck clean **7064/3440640 files, 1991215/13745152 blocks**. No test active. Owner presence/USB/Claude idle was
  confirmed for I3; do not reuse it for another flash. Subsequent symbol copies were read-only as phablet.
- **Exact I3 input:** unchanged I2 BOOT **src/m75/boot-i2.img**,
  **53d23d829e6eff7028be0d2478e01171e4f0b7258c87474b9076acbc53457b59**. Same DT **src/m73/dt-g1.img**,
  dee291ace91ab19f9d241d3c7cd42557e109f066ddf0c38eb69a6a7b1f97625c. No kernel/config/DT/ramdisk rebuild.
  I2 frozen **src/m75/i2-as-built/** and runtime **src/m75/i2-runtime/**. Acquisition manifest i3-inputs.json has
  81 hashes/five original snapshots; supplemental source separately hashed in i3-extra-inputs.json. Backup verified
  22cb95a536489c89a738cae3105859c041a15b298c4140c6a1a018883f7bd896. Raw src/m75/i3-raw/, session i3-session/.
- **Evidence:** log/2026-11-18-M7.5-i3-handler-startup.md; reference/m75-integration/i3-results.json,
  i3-stack-sites.txt and i3-symbol-checks.json. Private library copies under src/m75/i3-symbols/ are not published.
  Helper tests pass fd bounds, non-consuming peer query, filtered environment and owned-child timeout cleanup.
- **Kernel unchanged:** shared common clean **a50-usb/4fbb731f5**; isolated **src/m75/runtime-kernel** clean
  **a50-m75-i0-test/6a8742362572bbc2a9c3cca2a16cba0f160e07aa**. Clean graphics c6588dc03 / tree
  81fe4953be31a74851875040fe045b648ec18064 and 45-patch export unchanged; prior G2f/G2g worktrees preserved.
- **Next:** controlled test isolating **libgsthybris during GStreamer discovery**, retaining software plugins and a
  fresh temporary registry; verify normal handler bus names/Lomiri READY before a runtime deferral or soak. Do not
  use a stock registry to pretend hardware codecs work. Any policy deferral needs its scope/removal milestone
  documented; ADR-0005 audio stays unchanged. No next test or policy change has been started. Touch remains M8.

## Earlier handoff (I2 complete; superseded)
- **Active ticket:** M7.5. No test active; phone on stock 4.14.194 (home **192.168.0.171**), post-flight passed, fsck
  clean 7055/3440640 files.
- **I2 (ADR-0005 runtime):** PulseAudio active at 35.8 s with the overlay, but the telephony handler and Lomiri still
  time out. The handler blocks early, before its D-Bus connection (1 thread on 6.18 vs 4 on stock); I1's PulseAudio
  link was wrong. Log section "I2"; ADR-0005 has an update note. Evidence `reference/m75-integration/i2-*` once
  published; raw `src/m75/i2-raw/`.
- **Next action:** I3 = same I2 image, collector-only: handler maps, decoded ppoll fds, unix socket paths, environment,
  manual handler run with Qt/Mir/Wayland debug under a timeout. Owner says "present, flash I3" first.
- Builds: `tools/m75/build_i2.sh` (I0 kernel + `src/m75/i2-runtime`), BOOT `src/m75/boot-i2.img` `53d23d82…`.

## Earlier handoff (I1 complete; ADR-0005 approved; superseded)
- **Active ticket:** M7.5. No test active; phone on stock 4.14.194 since 00:21:21 (home **192.168.0.171**), post-flight
  passed, fsck clean 7058/3440640 files.
- **I1 result:** Android audio HAL `restarting` → PulseAudio blocked in startup (`pactl` hangs) → telephony handler
  never takes its bus name → Lomiri READY too late → stopped after 120 s. Log section "I1"; evidence
  `reference/m75-integration/i1-*`.
- **Decision:** ADR-0005 (owner approved 2026-11-18): per-boot read-only overlay of `/etc/pulse/touch.pa`
  (stock sha256 `04046fa3…`) without the `module-droid-discover` block; no audio on 6.18; removed in M10.
- **Next action:** build I2 = I0 kernel/DT plus the ADR-0005 hook in the embedded runtime (one variable), host-test the
  hash check and overlay content, then flash on "present, flash I2". Expect PulseAudio, the handler and Lomiri to reach
  active; then plan the ten-minute soak.

## Earlier handoff (I0r complete; Claude Code took over from Codex; superseded)
- **Active ticket:** M7.5 (the last open M7 ticket; all four acceptance boxes open). No test active. Phone on stock
  4.14.194 since 16:31:36 (office **192.168.181.225**), post-flight passed, fsck clean 7053/3440640 files.
- **I0r** (identical repeat of I0, owner present): same failure as I0 to the second; no kernel faults. Evidence
  `reference/m75-integration/i0r-*`.
- **Finding:** Lomiri sends READY from a zero-delay timer just before `exec()`, so READY is late because its main thread
  blocks on D-Bus calls to `lomiri-telephony-service-handler`, which never takes its bus name on 6.18. PulseAudio never
  becomes ready on 6.18 either; on stock both are active in under 6 s and Lomiri is ready 4.9 s after start. The
  handler-blocks-on-PulseAudio link is **unverified**. Full analysis and stock-vs-6.18 table:
  `log/2026-11-17-M7.5-integration.md`, section "I0 and I0 repeat".
- **Next action:** I1 = same I0 image (`src/m75/boot-i0.img`, sha256 `9dc35932…`, DT `src/m73/dt-g1.img`), collector
  additions only (handler and PulseAudio journals, per-thread wchan/stack, timed read-only `pactl info`, pending D-Bus
  names). Then choose a repair. No mixer/PulseAudio state changes; owner says "present, flash I1" before the flash.
- **Build from scratch:** `patches/` 0001-0045 reproduce clean tree `81fe4953be31a74851875040fe045b648ec18064`
  (re-verified with `tools/export_patches.sh`, unchanged). Full config `reference/m75-integration/clean.config`; builder
  `tools/m75/build_clean.py`. Test diagnostics for I0 stay in `reference/m75-integration/test-diagnostics.patch`.
- **Kernel branches (local only):** clean `a50-runtime`/`a50-display`/`a50-graphics` in `src/ack-6.18/common` (clean,
  checked out on `a50-usb`); I0 test `a50-m75-i0-test` `6a8742362` in `src/m75/runtime-kernel`.
- **Git:** all G2d-G2h, M7.4, M7.5/I0/I0r work and the 45-patch export committed and pushed in this session.
- **Open owner question:** history still contains a serial prefix in a regex (`ccc4e48`) and `androidboot.em.did` in
  four M6.4 captures (`f68ca87`); both redacted in the current tree. Rewrite history or not is undecided.

## Earlier handoff (I0 complete; repeat prepared; superseded)
- **Active ticket:** M7.5. I0 finished normal timed dump and restored stock DTB/DTBO/BOOT **16:04:35**;
  baseline 4.14.194 boot **16:04:49**, office **192.168.181.225**, **100% Charging**, partition post-flight passed.
  Saved fsck clean **7060/3440640 files, 1990928/13745152 blocks**. No test active. Phone not rechecked since restore.
- **I0 result:** six native + six compat memory cases PASS on consolidated image; owner saw recognizable lock/greeter.
  Lomiri service Type=notify stays activating, then Result=timeout and stop-sigterm. Its user manager is stopped later,
  hits a five-second stop timeout and is killed; this is recorded in kernel-follow, not a spontaneous kernel crash.
  M7.5 is not done; no ten-minute soak. Need to trace real readiness before choosing a repair.
- **Owner requested repeat after interruption:** prepared **tools/m75/run_i0r.sh**, **reference/m75-integration/i0r-inputs.json**,
  raw **src/m75/i0r-raw/**, session **src/m75/i0r-session/**. Same BOOT, DT, config, ramdisk, helpers and collector;
  only capture paths/wrapper differ. Original I0 evidence remains intact. Confirm owner presence/USB/Claude idle for
  this new flash, then fresh pre-flight and run. No repeat boot started yet.
- **Build/source:** clean-stack heads and exact I0 inputs below unchanged. Isolated src/m75/runtime-kernel clean on
  a50-m75-i0-test/6a8742362; shared common clean on a50-usb/4fbb731f5. Clean publication build also completed:
  src/ack-6.18/out/m75-clean/build-results.json; no diagnostic reset code, raw DT/cpio match. It has not been flashed.
- **Git:** outer 48c9ceb unchanged; all prior work/export and current M7.5 work uncommitted. Local clean kernel commits
  exist; 45-patch export reproduces clean tree 81fe4953be31a74851875040fe045b648ec18064. No push.

## Earlier handoff (I0 preparation; superseded)
- **Active ticket:** M7.5 integration. Clean M6/M7 changes committed in the separate kernel repo on new branches:
  a50-runtime **0d910019236c1ccc07f54f0ac9afe51c31d527d6**, a50-display **af07d6ba93ea5545293a9ba563e143066c1240c2**,
  a50-graphics **c6588dc0365dffb18473e832af547787759b3ea3**, clean tree **81fe4953be31a74851875040fe045b648ec18064**.
  **45 exported patches** reproduce that tree exactly. Tests/early-reset code remains separate. Snapshot selector
  correction is on graphics; display branch has the earlier selector requiring DEBUG_KERNEL for optional snapshots.
- **I0 active, not a soak:** owner confirmed present/USB/Claude idle. Flash **15:56:39**; USB SSH verified **15:57:36**,
  6.18.33-a50-diag+ at 10.15.19.82. All six native and compat memory cases pass. Logging-only user-manager log-target
  journal/log-level info setters passed; runtime in-memory change resets on rollback. Collector diagnoses the failed
  unencrypted session target; no config/policy/encryption/authentication repair or ten-minute result claimed.
- **Do not start another boot.** Runner session **43808**, log **src/m75/i0-session/run-session.log**;
  raw **src/m75/i0-raw/**. Standard 420-second timed DSS dump and stock restore/post-flight/fsck are still pending.
  Phone currently on test image; last baseline post-flight before this flash passed (4.14.194, 100% Full).
- **Test source/build:** isolated **src/m75/runtime-kernel**, clean on **a50-m75-i0-test/6a8742362572bbc2a9c3cca2a16cba0f160e07aa**.
  Shared common remains clean **a50-usb/4fbb731f5**; prior G2f/G2g worktrees untouched. Seven regression suites pass,
  including broken controls. Compared with G2g: 337 kbase files identical, 36 display static functions identical with
  diagnostic guards enabled, ION allocation body identical without test logging wrapper. Compiled DTB and cpio identical.
- **Inputs:** **reference/m75-integration/i0-inputs.json**, 72 hashes/11 frozen copies; config delta only explicit
  FB_A50_HANDOVER=y and FB_A50_DIAGNOSTICS=y. Backup hash rechecked 22cb95a536489c89a738cae3105859c041a15b298c4140c6a1a018883f7bd896.
  BOOT **src/m75/boot-i0.img**, SHA **9dc35932904eff7422e4eab6cb63003577627f8391ffa76ae9adf9636d688f52**;
  DT **src/m73/dt-g1.img**, unchanged dee291ace91ab19f9d241d3c7cd42557e109f066ddf0c38eb69a6a7b1f97625c.
  Output **src/ack-6.18/out/m75-i0**, frozen **src/m75/i0-as-built/**. Config aeba3e2b3a05a9ab889d720d0f924ddf5adc0cdeb7aa54e34880cdfd99c07a97;
  Image 3df523e9e5724d7ee8215f7686f9bb7c14053ea7c56b416703e8ac4a960439e9.
- **Investigation:** baseline phablet reads recovered previous .xsession-errors.old and unit journal. Session target
  dependency fails; Lomiri got a signal ~209 s then LightDM session exits ~299 s. Notify/stop timeout hypothesis;
  capture actual service Result before choosing a fix. Working baseline also emits the unencrypted-home warning.
  Root operations approved for current I0 cycle; do not change encryption or extend hardware masks from that warning.
- **Outer repo:** HEAD **48c9ceb** unchanged; prior G2d–G2h/M7.4 plus current docs/tools/45-patch export uncommitted.
  Kernel clean consolidation commits are local only. Log **log/2026-11-17-M7.5-integration.md**. Continue host publication
  preparation while observing I0; then finish restore/evidence before a new boot. M7/M7.5 remain open; touch is M8.

## Earlier handoff (M7.4 decision complete)
- **Latest ticket:** M7.4 conditional G2D port **dropped for the measured normal single-layer greeter/display path**.
  Both stock vendor ABIs tolerate a missing-device initialization query, retaining the Acrylic object; actual G2D
  task execution still fails without the device. Donor source identifies the task/compat ABI. Tested G2g ELF has no
  G2D execution functions (matching symbols are clock data); positive G2f/G2g/G2h display results establish this
  scoped path works without a G2D provider. This is not a universal non-use/fallback claim or G2D hardware validation.
- **Scope/reopen:** complex composition, video/YUV, scaling/rotation, virtual displays and protected content remain
  unverified. Reopen M7.4 if a required workload selects failing G2D/M2M processing or otherwise needs G2D. M7.5 must
  assess required scenes/session stability and soak. Existing startup/phablet-session failure, standalone EGL crash
  and unresponsive touch remain open; touch is M8. M7.3 done for measured paths; M7 overall still open.
- **Evidence:** reference/m74-g2d/decision.md, host-audit.json (34 input hashes, both ABI function locations,
  build/config checks, saved display counters); reproduce with python3 -I tools/m74/audit_g2d.py.
  Proprietary disassembly stays ignored under src/m74/audit/. Session log log/2026-11-17-M7.4-g2d-decision.md.
  Ticket/index and current contract/gap tables updated. No phone access, kernel edit/build or flash this session.
- **Last verified phone (previous G2h session; not rechecked):** stock DTB/DTBO/BOOT restored 2026-11-17 **15:01:33**,
  baseline **4.14.194** boot **15:01:46**, office **192.168.181.225**, **99% Charging**. Partition post-flight passed,
  fsck clean **7051/3440640 files, 1990792/13745152 blocks**. No test left active by G2h. Current live state unverified.
- **Git/artifacts unchanged:** outer **48c9ceb252dd6be6221a70a8cd6c75e32d85d242**, prior G2d–G2h and this audit
  uncommitted; no push. Shared src/ack-6.18/common clean on **a50-usb/4fbb731f5666f9f241aa2abcd0867f15d4f1232e**.
  Isolated src/m73/g2g-kernel remains on **a50-m73-g2g-wip/dce5cdc6e9d1c3cd64f063d5f29e1344e5724756**, only
  drivers/video/fbdev/a50-decon.c dirty; tested tree **ecb4aab84e0af0b68b6fb0aab5c155aaa2574908**. G2f worktree preserved.
  BOOT src/m73/boot-g2g.img **42cbbeb884bab6088a2835697bf8446e3edb025e60bde675ed33bcb4544053ad**;
  DT src/m73/dt-g1.img **dee291ace91ab19f9d241d3c7cd42557e109f066ddf0c38eb69a6a7b1f97625c**.
  Build src/ack-6.18/out/m73-g2g, frozen src/m73/g2g-as-built/; config/cpio unchanged. Further G2h inputs,
  backup verification and restore evidence are in the earlier handoff below.
- **Next:** M7.5 integration: consolidate the tested M6/M7 changes onto the clean stack and re-export patches before
  soak; investigate startup/session failure; then required UI workloads and ten-minute soak with regressions/restore.
  Do not infer successful login from rendered greeter. Reconfirm owner presence/USB/Claude idle before phone root
  operations or a new flash. M7.5 implementation and another boot have not started.

## Earlier handoff (G2h complete)
- **M7.3 done for measured ordinary paths:** G2h final helpers pass six cases each on stock 4.14 and unchanged
  G2g 6.18, native and compat. Allocation/query/map/both sync directions, pending cookies, heap-0 dma-buf import/data/
  exporter-fd lifetime, aligned user-buffer reservation and bounded errors/cleanup pass. Probe jobs disabled;
  real GPU execution/presentation evidence is G2f/G2g. No per-buffer GPU readback or user-import job pinning claim.
- **Latest result:** 19,574 padded DMA frames, zero CPU copies/fallbacks/skips/acquire/frame/shadow timeouts;
  final queue idle/pending zero, 165 counter snapshots. No recorded WARN_ON, GPU/SysMMU fault, fence wait or panic.
  Negative-request driver diagnostics are expected. Source/image/config unchanged; no kernel build this session.
- **Integration limits:** LightDM active and userdata rw at 160/300/330 s; Android RUNNING. At 300 s systemd degraded,
  known audio failure plus two transient greeter/user-manager jobs; at 330 s two failures/one job (identities not
  captured then). Phablet session exits status 1 before greeter; cause unresolved. Owner says greeter appears slowly
  and touch does not respond. PIN/login untested; no stable logged-in desktop claim. Evdev/touchscreen off, input M8.
  Standalone EGL failure, six secure/reserved heaps and fixed-260-MHz/no-DVFS limits remain recorded.
- **Phone last verified:** normal return to Download 15:01:15; stock DTB/DTBO/BOOT restore **2026-11-17 15:01:33**,
  baseline **4.14.194** boot **15:01:46**, office **192.168.181.225**, **99% Charging**. All three partition hashes and
  post-flight passed; saved fsck clean **7051/3440640 files, 1990792/13745152 blocks**. No test active. Owner confirmed
  present/USB/Claude idle for this cycle. No new temporary USB profile created. No further phone work authorized by
  an old presence confirmation; confirm again for a new flash.
- **Git:** outer HEAD **48c9ceb252dd6be6221a70a8cd6c75e32d85d242**; nothing committed/pushed this task. Existing
  G2d/e/f/g and new G2h docs/tools/evidence remain uncommitted. Shared **src/ack-6.18/common** clean on
  **a50-usb/4fbb731f5666f9f241aa2abcd0867f15d4f1232e**. Preserved G2f worktree unchanged. G2g worktree
  **src/m73/g2g-kernel**, branch **a50-m73-g2g-wip**, Git base **dce5cdc6e9d1c3cd64f063d5f29e1344e5724756**,
  still only **drivers/video/fbdev/a50-decon.c** dirty. Exact tested tree **ecb4aab84e0af0b68b6fb0aab5c155aaa2574908**.
- **Artifacts:** reuse **src/m73/boot-g2g.img**, SHA **42cbbeb884bab6088a2835697bf8446e3edb025e60bde675ed33bcb4544053ad**;
  **src/m73/dt-g1.img**, SHA **dee291ace91ab19f9d241d3c7cd42557e109f066ddf0c38eb69a6a7b1f97625c**.
  Build output **src/ack-6.18/out/m73-g2g**, frozen **src/m73/g2g-as-built/**; config/runtime cpio unchanged.
  Backup hash rechecked **22cb95a536489c89a738cae3105859c041a15b298c4140c6a1a018883f7bd896**.
  **reference/m73-gpu/g2h-boot-inputs.json** records 25 hashes/16 frozen copies, verified unchanged.
  Raw **src/m73/g2h-raw/**, published redacted **reference/m73-gpu/g2h-*.txt**; helpers in **src/m73/g2h-session/**.
  Log **log/2026-11-17-M7.3-g2h-memory-abi.md**, results **reference/m73-gpu/g2h-results.json**, recipe **tools/m73/G2h.md**.
- **Next ticket:** **M7.4 conditional G2D requirement decision**, using consumer/source evidence. Then M7.5 startup/
  session integration, consolidation onto clean branches/patch exports and ten-minute soak. M7 overall not complete.
  Do not start another boot or ticket from orientation alone.

## Earlier handoff (G2g completed)
- **Owner clarification (after G2g):** 6.18 eventually reaches the login/greeter screen, startup feels slow,
  and the screen does not respond to touch. PIN entry/authentication was not tested. Prior visible-UI statements
  mean greeter rendering, not a working logged-in desktop. Current config has INPUT_EVDEV and INPUT_TOUCHSCREEN
  unset; input bring-up remains M8. Slow startup/session progression should be tracked during M7.5 integration.
- **Active ticket:** M7.3 remains in progress. **G2g PASS:** real UI buffers (1088x2352, visible 1080x2340) now scan
  directly through IDMA/SysMMU. **19,725 padded DMA frames, zero CPU copies/fallbacks/skips/acquire/frame/shadow
  timeouts**. Late source/image registers match 0x09300440 / 0x09240438, offset zero. Queue pending zero/idle.
  Owner: **"UI looks correct; smoothness unclear"**. Native/compat metadata regression probes pass.
- **Measured rate:** around uptime 100–200, **59.972 completed updates/s** versus G2f CPU-copy **3.022/s** over the
  corresponding window. This is workload-specific presentation throughput, not a general GPU benchmark or a
  claim of subjective smoothness. 175 snapshots, peak pending 2. No recorded GPU/SysMMU faults, fence waits or panic.
- **Runtime/storage:** LightDM active at 100/200/300 s, correct 1080x2340 mode; Android RUNNING. At 300 s systemd
  degraded/zero jobs/one known audio-route failure. Userdata rw at all snapshots. Tight bootfb geometry restoration
  passes the host test; this natural UI run had zero fallback, so restoration was not exercised on the phone.
- **Phone last verified:** stock restore **2026-11-17 13:45:22**, baseline 4.14.194 boot **13:45:36**;
  office **192.168.181.225**, **100% Charging**. DTB/DTBO/BOOT post-flight passed; saved fsck clean
  **7054/3440640 files, 1992243/13745152 blocks**. No test active. Owner present/USB/Claude idle confirmed for G2g.
  The runner deleted its temporary NetworkManager USB profile after restore.
- **Git:** outer HEAD **48c9ceb**; no commits/push. Existing G2d/G2e/tracing/G2f and new G2g work remain uncommitted.
  Shared **src/ack-6.18/common clean on a50-usb/4fbb731f5**. Prior dirty G2f worktree **src/m73/g2b-kernel** is
  unchanged. New **src/m73/g2g-kernel**, dirty on **a50-m73-g2g-wip**, Git base **dce5cdc6e** plus G2f metadata
  and G2g stride changes, only **drivers/video/fbdev/a50-decon.c** modified. Candidate tree
  **ecb4aab84e0af0b68b6fb0aab5c155aaa2574908**. Export **reference/m73-gpu/g2g-padded-stride.patch** applies
  incrementally to tested G2f tree **7253f8a58c52a3aa9c77b6458bd4ce81c28589b4** and reproduces that exact tree.
- **Artifacts:** output **src/ack-6.18/out/m73-g2g**, frozen **src/m73/g2g-as-built/**.
  BOOT **src/m73/boot-g2g.img**, SHA **42cbbeb884bab6088a2835697bf8446e3edb025e60bde675ed33bcb4544053ad**.
  DT **src/m73/dt-g1.img**, SHA **dee291ace91ab19f9d241d3c7cd42557e109f066ddf0c38eb69a6a7b1f97625c**.
  Config/DTB/runtime cpio equal G2f. Backup hash rechecked **22cb95a536489c89a738cae3105859c041a15b298c4140c6a1a018883f7bd896**.
  Exact **33 inputs / 15 snapshots:** **reference/m73-gpu/g2g-boot-inputs.json**, **g2g-scripts/**.
  Log **log/2026-11-17-M7.3-g2g-padded-scanout.md**, results **reference/m73-gpu/g2g-results.json**;
  recipe **tools/m73/G2g.md**. Raw ignored **src/m73/g2g-raw/**; published captures redacted.
- **Next action:** focused kbase allocation/import/query/sync/error-path checks to close M7.3's remaining acceptance
  item. Keep the separate standalone EGL failure explicit. Then M7.4 G2D decision and M7.5 integration/10-minute
  soak; this 420-second test does not complete that soak. Reconfirm owner presence/exclusive access before a new flash.

## Earlier handoff (G2f completed)
- **Active ticket:** M7.3, still in progress. **G2f PASS:** EXYNOS_DISP_INFO now supplies the exact stock metadata;
  native and compat ABI/error/preservation probes pass. Mir reports **1080x2340**, physical **68x147 mm**, ARM/Mali-G72.
  Owner confirmed **recognizable Ubuntu Touch UI** on 6.18. GPU rendering reaches visible presentation through the
  CPU-copy display bridge. This is not direct DMA presentation or M7's completed 10-minute soak.
- **Display evidence:** real UI buffers are **1088x2352**, visible 1080x2340. Fixed-1080-pitch DMA eligibility rejects
  that padding. Late counters: **1019 WIN_CONFIGs, 1019 CPU copies, zero scanned/skipped/acquire/frame timeouts**,
  queue pending zero/idle. 174 snapshots, peak pending 2; ~3 updates/s during active copying (not a GPU benchmark).
  No recorded fence-wait warnings, kernel panics or GPU/SysMMU faults. No standalone graphics clients launched.
- **Runtime/storage:** userdata rw at 100/200/300 s. At 300 s systemd degraded, zero jobs, only known
  a50-audio-route timeout failed. Multi-user and graphical targets active; LightDM remains running. Android RUNNING.
- **Phone last verified:** stock DTB/DTBO/BOOT restore **2026-11-17 13:15:08**, baseline 4.14.194 boot **13:15:23**;
  office **192.168.181.225**, **100% Charging**. Partition post-flight passed; saved fsck clean
  **7045/3440640 files, 1992124/13745152 blocks**. No test active. Owner present/USB/Claude idle confirmed for G2f.
- **Git:** outer remains `48c9ceb`; no commits or push this session. Prior G2d/G2e/tracing and G2f implementation/
  tools/evidence remain uncommitted. Shared `src/ack-6.18/common` clean on **a50-usb/4fbb731f5**.
  Isolated `src/m73/g2b-kernel` dirty on **a50-m73-g2f-wip**, base **dce5cdc6e9d1c3cd64f063d5f29e1344e5724756**,
  only `drivers/video/fbdev/a50-decon.c` changed. Candidate tree **7253f8a58c52a3aa9c77b6458bd4ce81c28589b4**;
  exported **reference/m73-gpu/g2f-display-info.patch** reproduces that tree from G2e.
- **Build/artifacts:** output `src/ack-6.18/out/m73-g2f`, frozen `src/m73/g2f-as-built/`.
  BOOT **src/m73/boot-g2f.img**, SHA **0c60496fdb454f4a84a472d9245184d5bcdc390f8818eac51fa5eddd2f429b2a**.
  DT **src/m73/dt-g1.img**, SHA **dee291ace91ab19f9d241d3c7cd42557e109f066ddf0c38eb69a6a7b1f97625c**.
  Config/DTB/runtime cpio exactly match G2e; backup hash rechecked 22cb95a536489c89a738cae3105859c041a15b298c4140c6a1a018883f7bd896.
  Exact inputs/frozen scripts `reference/m73-gpu/g2f-boot-inputs.json`, `g2f-boot-scripts/`; recipe `tools/m73/G2f.md`.
  Log `log/2026-11-17-M7.3-g2f-metadata-boot.md`; results `reference/m73-gpu/g2f-results.json`.
  Raw ignored `src/m73/g2f-raw/`; published captures redacted. Earlier G2f trace inputs remain historical.
- **Next action:** audit/add direct scanout for the observed padded 1088-pixel stride (G2g), including correct IDMA
  source geometry and restoring boot-framebuffer pitch on fallback. Validate geometry/buffer bounds before boot.
  M7.3 still needs focused kbase allocation/import/query/sync checks; standalone EGL failure and M7 soak remain open.
  Reconfirm owner presence/exclusive access before another flash. Do not start another test from old confirmation.

## Earlier handoff (G2f tracing; before handler implementation)
- **Active ticket:** M7.3, in progress. M7.1/M7.2 done. G2c format translation is committed in outer `48c9ceb`;
  G2d passed direct display/fence tests after unblanking (30 flips, 16.9 ms/frame) and identified rejected heap-0
  gralloc flags 0x48/0x43. G2e has now tested the hint fix successfully. Rendering/Lomiri acceptance remains open.
- **Latest G2f tracing result:** both vendor library ABIs call mandatory `EXYNOS_DISP_INFO` (`0x40f84704`,
  248 bytes) before FBIOGET_VSCREENINFO; a failure returns from hardware-info initialization early. G2e's driver
  lacks that case and returns -ENOTTY. Baseline phablet metadata query succeeds: ver=2, psr=2, chip=9610,
  mres disabled/count 1, first entry `(68,147,0,0,0)`. Version/reserved bytes are preserved by the stock handler.
  All three optional mode queries also return ENOTTY on baseline, with a working library fallback; they need
  no implementation for that path. Trace/log `reference/m73-gpu/g2f-hwc-mode-trace.md`,
  `log/2026-11-17-M7.3-g2f-hwc-trace.md`. No kernel changes/build/flash or compositor restart for this tracing task.
  Rendering remains unverified; a fixed-image boot is still needed.
- **Latest G2e result:** native and compat replay of the gralloc requests passed allocation, full-buffer zeroing,
  mmap/sync/close. Protected/unknown flags and unsupported heap remain rejected. Natural gralloc 0x48 succeeds;
  all six recorded ION failures are deliberate helper negative controls. LightDM/Mir stays active and initializes
  the stock Mali-G72 GL renderer, but reports a **0x0 mode**; Lomiri repeatedly errors "An output ID must be specified".
  Final display counters: 79 WIN_CONFIGs, 76 CPU copies (sampled buffers 16x16), zero scanouts/skips/acquire timeouts,
  pending zero. Zero recorded fence-wait warnings or kernel panics; late frame timeouts zero.
  Owner saw Samsung warning screen with red/green/blue/white bars at the top, no verified recognizable UI/scene.
  GLES exits 134, "failed to create composer client", while Mir is active (contention plausible, unverified).
  EGL still exits 139. Direct-display helper was skipped because LightDM remained active.
  Evidence/result: `log/2026-11-17-M7.3-g2e-ion-hints.md`, `reference/m73-gpu/g2e-results.json`.
- **Baseline control:** fresh restored Mir reports 1080x2340/68x147 mm; G2e Mir reports 0x0/0x0 mm, although the same
  fbdev ioctl gives 1080x2340/68x147 mm on both. Both report pixclock zero; do not infer a missing pixel clock is
  the cause. Test/control captures `reference/m73-gpu/g2e-{fb-mode,baseline-fb-mode,baseline-display}.txt`.
- **Phone last verified:** stock restore completed 2026-11-17 **12:26:40**, baseline 4.14.194 boot **12:26:54**;
  office Wi-Fi **192.168.181.225**, battery 99% Charging at restore. G2f phablet queries confirm baseline still running;
  no new reboot. Stock DTB/DTBO/BOOT post-flight at G2e restore passed; saved fsck clean
  (6630/3440640 files, 1989163/13745152 blocks). No test active. Owner present/USB/Claude idle confirmed for this cycle.
- **Git:** outer HEAD `48c9ceb`; no commits made this session. G2d evidence and G2e preparation/results/tools are
  uncommitted, along with G2f tracing evidence and the metadata reader. Shared kernel `src/ack-6.18/common` clean on `a50-usb/4fbb731f5`.
  Isolated `src/m73/g2b-kernel` clean on `a50-m73-g2e-wip/dce5cdc6e9d1c3cd64f063d5f29e1344e5724756`,
  tree `b632eb2709cbce0cfad645109d94b5ce4ba9b8cb`, parent G2d `596020e39`. No kernel edits this session.
  Source exports: `g2c-format.patch`, `g2d-ion-log.patch`, `g2e-ion-flags.patch` under `reference/m73-gpu/`.
- **Tested artifacts:** BOOT `src/m73/boot-g2e.img`, SHA `9202dbc17d63260bbe593ea5775f1698239041a450277c40b818a70aff4614fc`;
  DT `src/m73/dt-g1.img`, SHA `dee291ace91ab19f9d241d3c7cd42557e109f066ddf0c38eb69a6a7b1f97625c`.
  Config/DTB/cpio unchanged from G2d; frozen `src/m73/g2e-as-built/`; build output `src/ack-6.18/out/m73-g2e`.
  Exact inputs: `reference/m73-gpu/g2e-{inputs,session-inputs,observation-inputs}.json`; frozen `g2e-scripts/`.
  Backup hash rechecked `22cb95a536489c89a738cae3105859c041a15b298c4140c6a1a018883f7bd896`.
  Raw logs ignored in `src/m73/g2e-raw/`; published copies redacted. Recipe `tools/m73/G2e.md`.
- **Next action (G2f metadata fix):** implement only EXYNOS_DISP_INFO, with exact 248-byte native/compat layout,
  stock copy-in/copy-out/error behavior and measured metadata. Preserve caller version/reserved bytes. Validate
  before building, then boot-test HWC2/Mir dimensions and Lomiri. Do not change pixel clocks or implement the
  optional mode queries without new evidence. Reconfirm owner presence/exclusive access before that flash.

## Earlier handoff (G2b; superseded by the resume section above)
- **Active ticket:** `tasks/M7.3-mali-kbase.md`, in progress. M7.1 and M7.2 are done.
  G1b now exposes `/dev/mali0`; native and AArch32 VERSION_CHECK 11.27 and GET_GPUPROPS pass (82 properties each).
  G2 removed the metadata restriction: client `4021_7` queued work but stalled on active fence context 1 (300 warnings),
  then panicked in `kbase_cancel_soft_job()` during cancellation. Rendering/completion remains unverified.
- **Latest G2b result:** cancellation fix survived the GLES timeout; no kernel panic, normal timed dump and clean restore.
  Display context 1 is confirmed as `a50-decon`/`decon_f`. All 1800 buffer updates are single-layer format 2 (RGBA_8888),
  unsupported by the current display path: 1800 skipped, zero CPU copies, zero DMA scanouts. The queue progresses and
  drains to pending zero/1800 completions despite 603 fence-wait warnings. Slow CPU pixel copying is not demonstrated.
  `test_egl` exits 139 (userspace SIGSEGV); `test_glesv2` times out 124. Owner saw black/flicker, no recognizable scene.
  Rendering remains unverified. Log `log/2026-11-17-M7.3-g2b.md`; results `reference/m73-gpu/g2b-results.json`.
  Config/DTB/cpio are identical to G2; full build/link and host regression controls pass.
  BOOT `src/m73/boot-g2b.img`, SHA `56da9fe40fe969fe643ce0e77446ca895a244126722af0cf36b539b9ed27dc42`.
  Exact inputs and frozen scripts: `reference/m73-gpu/g2b-inputs.json`, `g2b-scripts/`. Recipe `tools/m73/G2b.md`.
- **Owner screen observation:** G2 blackened/flickered then returned to baseline UI; G2b also black/flicker only, no scene.
  G2's observation is in `log/2026-11-17-M7.3-g2-observation.md`; G2b now identifies the presentation format gap.
- **Phone:** baseline restored 01:59:18, boot 01:59:33 on 2026-11-17. Home Wi-Fi `192.168.0.171`, kernel 4.14.194,
  battery 100% Charging. Stock DTB/DTBO/BOOT hashes passed; saved fsck clean (6518/3440640 files, 1989376/13745152 blocks).
  No test active. Owner confirmed presence/USB/Claude idle for the completed G2b cycle. Reverify on resumption.
- **Fix:** G1 failed before GPU initialization: legacy raw IORESOURCE_IRQ lookup returned no IRQ 0.
  G1b changes only IRQ acquisition to `platform_get_irq_byname()` and `irq_get_trigger_type()`. Config/DTB/cpio identical.
  The GPU identifies as Mali-G72 r0p1 MP3 at the measured fixed 260 MHz. No DVFS, power-domain switching or secure calls.
- **Diagnostic restriction:** G1/G1b used `mali_kbase.a50_g1_probe_only=1`; G2 removes it. The source defaults to unrestricted
  ioctls without that parameter. Keep this config distinction explicit for future tests.
- **Git handoff:** outer HEAD `dbbc6a8` records G1/G1b. G2 tools/evidence, observation follow-up and completed G2b work are uncommitted.
  Shared kernel is **clean on `a50-usb/4fbb731f5`**; GPU base/G2 source is committed on `a50-m73-g1-wip/c04d5ada5`.
  G2b uses isolated worktree `src/m73/g2b-kernel`, dirty on `a50-m73-g2b-wip/c04d5ada5` (no source commit made).
  Candidate tree `89009e6d9e9170360d724a9e6258c2a917e66389`, exported as `g2b-cancel.patch` and `g2b-display-diagnostics.patch`.
  Build output `src/ack-6.18/out/m73-g2b`; all artifacts frozen under `src/m73/g2b-as-built/`.
  Exact G1b source tree `2c8ab17e16c68ae7a72ed3c814f08d39894e5413`; reconstruct from M6 source using
  `reference/m73-gpu/g1-kernel.patch` then `g1b-irq.patch` (both verified by tree hash).
- **Build/artifacts:** tools/recipe `tools/m73/README.md`; full config `reference/m73-gpu/g1.config`.
  Workspace `src/ack-6.18/out/m73-g1-candidate` reused only after archiving each variant in `src/m73/g1-as-built/` and
  `g1b-as-built/`. G1b BOOT `src/m73/boot-g1b.img`, SHA `1c545ebc84c1daea807dd7dc935aebfb3ae1be6c15d4193d529ba96bc06edd43`.
  DT `src/m73/dt-g1.img`, SHA `dee291ace91ab19f9d241d3c7cd42557e109f066ddf0c38eb69a6a7b1f97625c`.
  Exact manifests/as-run scripts under `reference/m73-gpu/g1*-inputs.json`, `g1*-scripts/`; log `log/2026-11-17-M7.3-g1-kbase.md`.
- **Latest G2 inputs:** `reference/m73-gpu/g2-inputs.json`, config `g2.config`; BOOT `src/m73/boot-g2.img`, SHA
  `bf0934e7f727502e615be471d1fec9c93ab0c83b2b369c72dc3c59a87276e93a`. DTB/cpio unchanged from G1b.
- **Next action:** address observed display format 2 (RGBA_8888) before judging visible rendering. Audit stock ABI-to-DPP
  byte-order translation and geometry/stride, then test known colors and GLES. Source evidence:
  `reference/m73-gpu/g2b-format-analysis.md`. Track the separate EGL userspace SIGSEGV. M7.3 is not done.
  Confirm owner presence/exclusive access before any new phone test.

## Earlier handoff (2026-11-14–16; historical)
- **Connection:** home `192.168.0.171`. Final stock restore completed 2026-11-14 at 02:57:44, baseline boot time
  02:57:58, battery 100% Charging. DTB/DTBO/BOOT post-flight hashes passed; saved baseline fsck clean. No test active.
  Owner confirmed presence, USB connected and Claude Code idle for this completed session; reverify live state on resumption.
- **Milestone:** M6 done, M7.1 done. **M7.2 in progress: D0 ran (2026-11-14, Claude Code)**. The TOP→DISPAUD clock is
  manual-off because of the 6.18 CMU init (range 0x8000, so every gate is forced to manual). D0b (2026-11-16):
  enabling only `gout_cmu_dispaud_disp` ran to the timed dump with no logged fault, but no USB gadget came up and the dump
  window missed the probe lines (`log/2026-11-16-M7.2-d0b-display-clock.md`). D0c (2026-11-16) captured the display state:
  DECON enabled in command mode, TE trigger masked, window 3/IDMA0 reading `0xca000000`, DSI configured, DPU SysMMU
  clock off (`log/2026-11-16-M7.2-d0c-display-state.md`). **D1 PASS (2026-11-16):**
  first 6.18 frame on the panel; the owner saw red/green/blue/white bands, FRAME_COUNT 3→9, format a8r8g8b8
  (`log/2026-11-16-M7.2-d1-first-frame.md`, kernel `a50-m72-d1-test` `3a9d3da33`). **D2a PASS (2026-11-16):**
  the `a50-decon` fbdev driver (kernel `a50-m72-d2a2-test` `cd08e9304`, DT `src/m72/dt-d2.img`) gives `/dev/fb0` with
  frames on pan and 60 Hz TE vsync; the owner saw the test pattern. It needed a 9610 TOP pinctrl GPIO-interrupt fix
  (bound for the clean stack). `log/2026-11-16-M7.2-d2a-fbdev-driver.md`. **D2b PASS:** `S3CFB_WIN_CONFIG` with stock
  fences works (kernel `a50-m72-d2b-test` `b7e58452f`, CPU-copy bridge, ~300 ms/frame;
  `log/2026-11-16-M7.2-d2b-win-config.md`). **D3a2 PASS:** display
  DMA goes through the DPU SysMMU with translation on and a boot-framebuffer identity map (kernel `a50-m72-d3a2-test`
  `b22b17c94`, DT `src/m72/dt-d3a.img`; `log/2026-11-16-M7.2-d3a-sysmmu-attach.md`). **D3b PASS:** WIN_CONFIG
  buffers are scanned out by DMA through the SysMMU at 60 Hz (kernel `a50-m72-d3b-test` `97c03597f`;
  `log/2026-11-16-M7.2-d3b-dma-scanout.md`). **D4a PASS; M7.2 DONE**
  (2026-11-16): blank/unblank via DCS sleep commands; acceptance in `log/2026-11-16-M7.2-d4a-blank-and-close.md`. Latest
  display kernel `a50-m72-d4a-test` `6c1151fb6`, DT `src/m72/dt-d3a.img`. Limits: handover design, single-window
  scanout, test branches. **M7.3 started:** G0b
  read the GPU: Mali-G72 r0p1, 3 cores, PLL_G3D fixed at 260 MHz, register path clocked
  (`log/2026-11-16-M7.3-g0-gpu-probe.md`, kernel `a50-m73-g0b-test` `88ece9a15`). Next: G1, the kbase r26p0 port. Confirm owner presence before every flash. Office network: phone `192.168.181.225`. Log `log/2026-11-14-M7.2-d0-display-probe.md`; kernel test branch `a50-m72-d0-test`
  (`e5b86c629`). Phone restored, post-flight passed, fsck clean. The warning screen is normal during 6.18 boots: don't
  key-recover inside the runner window. M7.3 may start in parallel with G0 (read-only GPU ID probe; check the TOP G3D
  gate first). M7.1 audit and boot ladder:
  `log/2026-11-14-M7.1-display-gpu-audit.md`. Display needs neither M4.4 nor M4.3 (panel power is GPIO-only; S2MPB03
  feeds cameras). The composer already starts on simplefb, so check ioctls and the panel, not the process.
  Vendor display libraries read as phablet (no root) into ignored `src/m71/vendor/` (proprietary; never commit).
  M6.4 session log: `log/2026-11-14-M6.4-runtime.md`.
- **Final M6 result:** test 7 Android RUNNING, normal `sys.boot_completed=1`, real graphics allocator guest PID 133
  running and registered over HIDL. Both 64/32-bit ION replays passed as UID 1000/GID 1003, 64 captured allocations and
  boundary/lifetime checks, zero exported buffers afterward. All raw block open modes and mknod denied by the guest
  device policy, with baseline negative control. USB root SSH retained; vendor ro/norecovery; EFS/CPEFS unmounted;
  userdata rw and guard range intact. All seven stock restores and saved fsck checks passed.
- **Runtime fix:** stock TEEGRIS post-fs waits for an unported daemon before HAL startup. A hash-checked, read-only,
  per-boot RC bind defers that action. Vendor contents are unchanged; no TEE readiness or secure storage is fabricated.
  Tools `tools/m64/`; exact tested scripts/manifests and result summary under `reference/m64-runtime/`.
- **Masks:** all four M5 HAL masks are removed. Multi-user reached at 212.21 s; late systemd state degraded with zero jobs.
  Rild/ofono settled; bluebinder still retries, audio-route times out and LightDM fails, without blocking multi-user.
  Hardware Bluetooth/audio/modem/display are not established. Three diagnostic masks remain: repowerd.service,
  a50-enable-autosuspend.service, sleep.target. Their automatic-suspend paths are unvalidated; owner approved keeping
  them until M12, whose DoD removes them (2026-11-14; owner rules below).
- **Final test inputs:** source `a50-m63-sysmmu-test/bd3fe49b2d2c3b0b04be490b3440d38d806949a3`, unchanged during M6.4.
  BOOT `src/m64/runtime7/boot.img`, SHA `28fb0f6bdf887ea59d2d431465d5be8c721a7c3cf2274fa4a07ae1e92ad9c680`.
  Config/Image/cpio frozen under `src/m64/runtime7/as-built/`; workspace `out/m64-runtime2` was reused after archiving.
  DT `src/m63/dt-sysmmu.img`, SHA `8072be7a4f3f7e588b5c547599784d2d88499c46acbbcfdd2463c1d279baf36d`.
  Manifest `reference/m64-runtime/runtime7-inputs.json`. All overrides live in /run; timed diagnostic window 420 seconds.
- **Remaining limits:** six reserved/secure heaps and TEE/security HALs unsupported; legacy Android cgroup profiles still
  emit setup warnings despite native v2. Scheduling/QoS, real IOMMU translation/DMA, GPU and display remain unvalidated.
  Do not infer their success from the allocator process or CPU ION replay.
- **Git handoff:** this publication checkpoint includes M6.2 wakelock, M6.3, M6.4 and the next M7 tickets
  (outer starting HEAD `a829080`). Kernel checkout remains clean on `a50-usb/4fbb731f5`; production branches unchanged.
- **Build from a clone:** `python3 -I tools/reproduce_m6.py --jobs 16`; instructions in `reproduce/m6/README.md`.
  Complete diagnostic source/config exported separately from clean `patches/`. Pinned public donor/toolchains replace
  private workspace dependencies. Fresh isolated build passed, reproducing the tested source tree, cpio and raw DTB;
  Image/BOOT hashes depend on the embedded config's absolute initramfs path. Publication evidence:
  `log/2026-11-14-publish-m6.md`, `reference/m6-reproduce/`. No phone operations during publication.
- **M6.3 source history:** `log/2026-11-12-M6.3-ion-design.md` maps all seven baseline heaps. A live allocator payload capture
  found 32 successful heap-0 allocations. Source `a50-m63-ion-test/33c851162` adds a native DMA-heap-backed ION frontend
  for that measured subset. Native and AArch32 replay/boundary/lifetime tests passed over USB. All four boots restored stock
  and passed post-flight/fsck. The final native SysMMU provider bound and reported version 7.2. No DMA master is attached.
  Test log `log/2026-11-12-M6.3-ion-tests.md`, evidence `reference/m63-ion/`; included in this publication checkpoint.
- **M6.3 SysMMU history:** `log/2026-11-12-M6.3-sysmmu.md`. Config control with the old DT and provider candidate with the new DT
  passed; both used source `a50-m63-sysmmu-test/bd3fe49b2`, config `src/ack-6.18/out/m63-sysmmu/.config`.
  BOOT `src/m63/boot-sysmmu.img`, SHA `de28abe867bf95c65e89fc3fd5a7369ed64f899f31cf1d5a466af9fa12c92d90`;
  provider DT `src/m63/dt-sysmmu.img`, SHA `8072be7a4f3f7e588b5c547599784d2d88499c46acbbcfdd2463c1d279baf36d`.
  Full inputs in `reference/m63-sysmmu/inputs.json`. Seven replay-helper runs across four boots passed 224 captured allocations,
  with zero exported buffers afterward; same four expected failed units, guard intact and userdata rw throughout.
- **M6.3 limits:** only heap 0 is implemented and advertised. The six reserved/secure heaps remain unsupported. M6.4 verified
  the real service running/registered and the measured heap-0 replay in the guest. DPU provider probing is verified;
  IOVA/page tables, real DMA, other controllers, secure access and suspend/resume remain untested for consumer milestones.
- **Wakelock boot log:** `log/2026-11-12-M6.2-wakelock.md`. Control and PM candidate passed. The native wakelock interface
  passed acquire, release and timeout. Binder's Halium device paths, ashmem and sync also passed. All eight CPUs were online.
  Guard and userdata stayed healthy, and stock restore plus saved baseline fsck passed after both boots.
  Same kernel source `a50-m62-ashmem-test/078d5dbf1`. Final config `src/ack-6.18/out/m62-wakelock/.config`.
  Image `src/m62/boot-wakelock.img` SHA `2aa56e2dc70986d4c28b5c28f4047b1697dac9a5482362fe959ff3266cc94794`.
  Inputs/config deltas/evidence are in `reference/m62-wakelock/`. Recorded outer base `a829080`; results/tools checkpointed.
- **Diagnostic power setup:** both wakelock builds add runtime masks for `repowerd.service`, `a50-enable-autosuspend.service`
  and `sleep.target` to the existing M6.2 test masks. Kernel autosleep and hibernation are disabled. M6.4 reviewed and retained
  these three masks; approved until M12 (2026-11-14). Suspend integration remains M12.
- **Sync boot log:** `log/2026-11-11-M6.2-sync.md`. Two software fences merged and became ready only after both signaled.
  Binder and ashmem passed again over USB root SSH. The guard passed, userdata stayed rw and baseline restore/fsck passed.
  Same kernel source as ashmem. Image `src/m62/boot-sync.img` SHA `4c77d2dc31979bf31d95f130af04589ccbc1426f9c033254ccc45c88cb9f6583`.
  Inputs, config delta and live evidence are in `reference/m62-sync/`.
- **Ashmem boot log:** `log/2026-11-11-M6.2-ashmem.md`. Native `/dev/ashmem` passed the AArch64 size ioctl and shared mmap
  test, and all three Binder contexts still returned protocol 8 over USB root SSH. Guard passed, userdata stayed rw, and
  post-flight and saved baseline fsck passed. Test source `a50-m62-ashmem-test/078d5dbf1` includes two ACK Rust config fixes.
  Image `src/m62/boot-ashmem.img` SHA `287f3ca0c02078a8891f9d24f462878ba1196105c7438d05873d867f1fe3b20a`.
  Exact config delta, input hashes, patches and live evidence are in `reference/m62-ashmem/`.
- **BinderFS boot log:** `log/2026-11-11-M6.2-binderfs.md`. Both boots reached USB root SSH on 6.18 with Android `STOPPED`
  and userdata rw. Control mount failed as expected. Candidate exposed all three contexts with `BINDER_VERSION=8` using
  a temporary executable tmpfs because `/run` is noexec. Both dumps show one UNMAP refusal and the same seven failed units.
  Stock restore, pre-flight and saved baseline fsck passed after both boots.
- **M6.2 artifacts:** BinderFS control and candidate built from `a50-m62-binder-test/e8a5a7fea`.
  The two-line tracepoint export guard fixes the Binder candidate build with PM sleep disabled. Guard/sense tests passed.
  Both images use the same partition-unit mask, M5.4 initramfs and build version. Full inputs in `reference/m62-binderfs/inputs.json`.
  Control `src/m62/boot-binder-control.img` SHA `bd23da74daedcadf12fbb351175870708c55fadf166a0e6bba3be9ab1e7c913f`.
  Candidate `src/m62/boot-binder.img` SHA `800d2b36756127f4c979030977ed506c85d3ae3a27e69a24bd6158a32503749b`.
  Outer test preparation started from `0ebaf48`. The checkpoint includes the M6.1 audit and M6.2 evidence through sync.
- **M6.1 audit:** `log/2026-11-11-M6.1-android-runtime-abi-audit.md`. Host audit of the tested config, archived Android 11
  rootfs and vendor traces. EFS write denial confirmed. Missing BinderFS likely accounts for the Android mount-unit exit;
  exact exit command still unverified. Legacy cgroup profiles are present and runtime compatibility is pending M6.4.
  Outer audit base `0ebaf48`. No M6 code, build or phone operations during M6.1.
- **M5.4 boot log:** `log/2026-11-10-M5.4-usb-ssh.md`. M5.4 root SSH verified twice over USB on 6.18.33-a50-diag+, with trusted
  baseline host key and route-to-phone explicitly using USB enp6s0f4u1. Final endpoint 10.15.19.82:22, host DHCP 10.15.19.5.
  lxc-info android STOPPED (expected until M6); systemd settled degraded with zero jobs and the seven known hardware failures.
- **Fix:** added NETDEVICES to tools/m51 Halium prerequisites. Without it, SO_BINDTODEVICE returns ENOPROTOOPT and packaged
  udhcpd fails even though USB RNDIS itself works. Test 2 verifies udhcpd active/running and DHCP OFFER/ACK, no new failed units.
  Full olddefconfig delta archived (new network menus and PPS/PTP defaults included); no UFS guard/cmdline/USB function changes.
- **USB method:** generated Halium /init creates only /run/usb-moded/99-a50-m54.conf with USB_MODED_ARGS="-f -r" before the
  original handoff. Packaged fallback/rescue selects RNDIS developer mode despite missing charger detection/charging functions.
  No persistent rootfs/vendor/auth changes. Main root SSH port 22 used; host needed no temporary profile from the watcher.
- **Operational limits:** automatic cable/role detection, other modes and legacy usb-tethering/dual DHCP ownership remain M12;
  evidence and follow-up in docs/08-open-questions.md. Both DHCP helpers run, but tested lease came from packaged Busybox udhcpd.
- **Config checkpoint:** current checker reports 89 differences, exactly the same red CONFIG diagnostics as accepted M5.1 modern
  config. Classification/replacements documented; broader checker/controller/BPF_JIT/KCMP review remains deferred by owner.
- **Source/artifacts:** M5.4 preparation 8434c1a; NETDEVICES fix/first SSH proof b18a792. Result evidence accompanies this update.
  Final image `src/m54/boot-m54-netdevices.img`, SHA eb86ac8c5228c5d0182590dc7bf74bf6e25f1598e12da4e952c660657a4ed9a4.
  Inputs/checks/SSH/DHCP/dumps under reference/m54-usb-ssh/. Kernel source is committed a50-m54-test/f0618ab59; no source edits.
- **Guard:** clean a50-userdata/c7bde3fe3, included in test source. WRITE(10/16) policy denials report DATA_PROTECT; other denied
  operations ILLEGAL_REQUEST. One UNMAP refusal, no WRITE(6)/FUA fallback or userdata errors; userdata rw at all snapshots.
- **Checkout:** kernel clean on a50-usb/4fbb731f5. To reproduce M5 USB access, use a50-m54-test and the M5.4 build recipe below.
- **Next action:** M7.1 saved-evidence display/GPU ABI audit and implementation design. Start from the final M6 source,
  config and runtime setup above. Preserve USB/storage and the unmasked M5 HAL units; identify real power/I2C prerequisites
  before hardware enablement. Record new heap or DMA requirements when observed.

## State of the phone (verified after M6.4 test 7, 2026-11-14)
Baseline BOOT `7d5855efd34e01f09659c7d47ecb0773c30f2acc7443ee87181a0536804086c5`, stock DTB/DTBO verified by post-flight.
Home IP **192.168.0.171**, root SSH verified, kernel 4.14.194, baseline boot time 2026-11-14 02:57:58,
battery 100% Charging. Restore completed 02:57:44. Saved baseline init fsck clean: 6321/3440640 files,
1995384/13745152 blocks, no repairs. Evidence `reference/m64-runtime/runtime7-run.txt` and `runtime7-baseline-fsck.txt`.
No test active. M6.4 overrides/masks were runtime-only. Recheck the actual phone before future operations.
Userdata retains the M5.2 scratch file. Read-only backup (2026-11-10 before writes):
`../a50-ubuntu-img-backup/ubuntu.img-2026-11-10`, sha256
`22cb95a536489c89a738cae3105859c041a15b298c4140c6a1a018883f7bd896`; rechecked 2026-11-14. Restore: docs/02-baseline.md.

## Kernel tree `src/ack-6.18/common` (not pushed; patches are exported to `reference/m*/`)
Checkout: `a50-usb` (clean). Check it before any build: builds check out a test branch and return to `a50-usb`.
- Portable final M6 diagnostic snapshot: `reproduce/m6/`; exact base-to-test tree export, config, toolchain/input locks.
  Its independent build workspace does not switch this shared checkout. This is separate from the clean driver export.
- Clean driver stack: `a50-dt -> a50-clk -> a50-pinctrl -> a50-ufs -> a50-usb -> a50-acpm -> a50-pmic -> a50-thermal -> a50-core`
  (`364673845`, M4 done) `-> a50-userdata` (`c7bde3fe3`, write allow-list + corrected denial sense split).
- `patches/` is the public export of the clean stack (base `d9a614fed`, 35 patches, ends at `a50-userdata`). After any
  change to a clean branch, run `tools/export_patches.sh` (it checks the series reproduces the branch) and commit `patches/`.
- `a50-diag` (`88040ffc9`, v8: DSS readout, panic dump, sync before the timed dump): diagnostics, do not merge into clean branches.
- `a50-bus` (on `a50-pmic`): I2C/PWM/keys DT. **Do not boot with its I2C nodes enabled: it freezes the phone.**
- Test branches, do not merge: `a50-m36-*`, `a50-m37-test`, `a50-m42-test` to `a50-m46-test*`, `a50-m48-test`, `a50-m52-test` (m48 + userdata),
  `a50-m53-test` (m52 + diag v8); a50-m53-3/4 historical broad sense; a50-m53-split/5 and a50-m54-test `f0618ab59` corrected split.
- `a50-m62-binder-test` (`e8a5a7fea`) extends M5.4 with the PM tracepoint export guard. Patch under `reference/m62-binderfs/`.
- `a50-m62-ashmem-test` (`078d5dbf1`) extends the Binder test branch with Rust KABI-field and DMA-BUF config guards.
  Patches under `reference/m62-ashmem/`.
- `a50-m63-ion-test` (`33c851162603f15d9d01baa4b7fba27cf19b7126`) extends that source with the native DMA-heap-backed
  legacy ION frontend and Samsung tracking hints. Native/compat builds use `out/m63-ion` and `out/m63-ion-compat`.
- `a50-m63-sysmmu-test` (`bd3fe49b2d2c3b0b04be490b3440d38d806949a3`) adds the isolated DPU provider DTS.
  Final test config/image under `src/ack-6.18/out/m63-sysmmu`; BOOT `src/m63/boot-sysmmu.img`, DT `src/m63/dt-sysmmu.img`.
  Both M6.3 source changes are actual commits; patches and full input manifests are under `reference/m63-ion/` and
  `reference/m63-sysmmu/`. Clean production branches are unchanged; do not merge diagnostic test branches into them.

## Build and test loop
- For the working M5.4 USB access image, run `python3 -I tools/m54/make_force_init.py` to regenerate init/list.
- Build (M5.4 form), from the outer repo with the kernel on the test branch:
  `A50_HALIUM=1 A50_DIAG=1 A50_DIAG_DUMP_DSS=1 A50_DIAG_DUMP_AFTER=240 A50_INITRAMFS_LIST=$PWD/src/m54/embed-force.list.in
  A50_CMDLINE_APPEND="clk_ignore_unused printk.devkmsg=on systemd.log_target=kmsg systemd.journald.forward_to_kmsg=1 systemd.show_status=1 systemd.mask=rild.service systemd.mask=ofono.service systemd.mask=bluebinder.service systemd.mask=a50-audio-route.service"
  A50_CONFIG="<M3.7 base flags> $(tr '\n' ' ' < tools/m52/userdata.flags)" tools/m22_build.sh src/ack-6.18/out/<name>`;
  the base flags are in `log/2026-11-10-M3.7-halium-initramfs.md`. Pack: `tools/m22_pack.sh IMAGE OUT.img`.
- `A50_HALIUM=1` applies `tools/m51/halium.flags`; `rdinit=/a50/init` in `A50_CMDLINE_APPEND` runs our diagnostic init instead of
  Halium's (`A50_INIT=tools/m48/init`, `tools/m52/init-write`, ...). S-Boot drops the boot.img cmdline: `CONFIG_CMDLINE` is what counts.
- Test: `DT_IMG=src/m48/dt.img tools/m32_run_test.sh IMG OUT_DUMP PHONE_IP WAIT_S`: pre-flight, flash our DT+BOOT, 6.18 dumps its
  log and returns to Download mode, rollback to stock DT + baseline BOOT, read the dump, pre-flight again.
- Readout when a boot sticks: telnet `192.168.2.15` over USB RNDIS (our init, or Halium's panic handler); `tools/m37/telnet_test.py`.
- Guard: any UFS-enabled kernel must carry `A50_UFS_SAFE` (the build script refuses otherwise). Writes are allowed only inside
  userdata, LUN 0 blocks `0x1c8700-0xee42ff` (`tools/m52/userdata.flags`); host test `tools/m52/guard_unittest.py`.
- Host: USB-C cable only. udev rule `99-a50-acm.rules`, NetworkManager profile `a50-rndis` (192.168.2.1). Host sudo is run by
  the owner in a local terminal; verify its effect with a real conditional before flashing.
- A failed Heimdall handshake leaves Download mode stuck; a replug does not clear it, the key combo does (`docs/06-workflow.md`).

## Owner rules and decisions in force
- Prefer 6.18-native mechanisms over 4.14-era or legacy ones (nftables, `CONFIG_LSM`, cgroup v2, mainline drivers) (2026-11-10).
- Take the shortest route to the ticket's acceptance; record side questions in `docs/08-open-questions.md` instead of chasing them.
- Do not send requests on ACPM channel 7 (thermal): it stalls the firmware for the boot. Do not pursue loading ACPM firmware plugins.
- Do not change mixer or PulseAudio state on the phone. Never commit device identifiers (check `grep -c 'R28[M]'` (phone serial prefix) before commit and push).
- M5 checker goal reworded (2026-11-10): every checker option that exists in 6.18 is set or replaced by its 6.18-native mechanism,
  the rest listed with reasons. To revisit later.
- M5 runtime masks are temporary (2026-11-10): M6.4 boots once without them and records what still blocks; bluebinder is
  removed in M9, a50-audio-route in M10, rild/ofono in M11 (each milestone's DoD in `docs/05-plan.md`).
  M6.4 removed all four. Power masks approved (2026-11-14): repowerd.service, a50-enable-autosuspend.service and sleep.target
  stay masked per boot until suspend is validated; removed in M12 (M11's gate covers only the M5 HAL masks).
- TEEGRIS deferral approved (2026-11-14): `docs/decisions/ADR-0004-defer-teegris-runtime.md`. Per-boot, hash-checked, read-only
  overlay of `teegris_v3.rc` only; security HALs/DRM/secure heaps stay unsupported. Any other vendor-file overlay needs its own ADR.
- Flashing (2026-11-14): Heimdall flashes BOOT, DTB and DTBO; DTB/DTBO only through `tools/m32_run_test.sh` (or a wrapper),
  which restores stock in the same cycle. No per-test approval needed beyond rule 7 (owner present). CLAUDE.md rule 3.

## Done (details in each log; index `tasks/README.md`)
- **M0** baseline locked and measured; **M1** reproducible builds, vendor ABI captured; **M2** first light on 6.18.
- **M3** storage + USB: our DT, readout at any time, clocks, pinctrl, read-only UFS with the guard, USB gadget (ACM/RNDIS),
  Halium ramdisk embedded in the kernel (a boot.img ramdisk does not reach 6.18), telnet over USB. Caveat: our init, not Halium's.
- **M4** core SoC on `a50-core`: 8 CPUs, ACPM, 35 S2MPU09 regulators (read-only), power domains (read-only), thermal (4 zones).
- **M5.1** Halium/UT config via `A50_HALIUM=1`, modern-first. **M5.2** `ubuntu.img` backed up; 6.18 writes inside userdata only,
  scratch file read back on the baseline, `e2fsck -n` clean before and after.
- **M5.3** Halium init boots ubuntu.img to multi-user/degraded with approved runtime HAL masks.
- **M5.4 / M5** USB RNDIS root SSH verified; packaged DHCP fixed by NETDEVICES, M5 DoD evaluated with accepted exceptions and clean restore.
- **M6.1** Android runtime and ABI audit complete with BinderFS first-test plan.
- **M6.2** Native BinderFS, Rust ashmem, sync fences and userspace wakelocks verified with diagnostic power-service masks.
- **M6.3** Measured heap-0 legacy ION ABI on native DMA heaps, native/compat replay and lifetime checks; native DPU SysMMU
  v7.2 provider probe. Other six heaps and actual device DMA remain explicit limits; runtime validated in M6.4.

- **M6.4 / M6** Normal Android boot property 1, real allocator/HIDL registration and guest 64/32-bit ION replay verified.
  Protected storage and USB retained; all four M5 HAL masks removed; runtime TEEGRIS deferral and three PM masks explicit.
  Final stock restore/fsck clean. M7 tickets written; M7.1 next.

## Deferred, to work again
- M4.4 real I2C (freezes 6.18; plan in the ticket; needed before M7/M8). Blocks M4.3 S2MPB03, keys, PL330.
- M4.7 CPU frequency (dropped from M4; route without the firmware plugin in the ticket).
- M5.1 checker goal (see above). M0.5 microphone (UT-image session).
- Open questions (ramdisk delivery, one-off hang, I2C freeze, ...): `docs/08-open-questions.md`.

## Open baseline defects (found in M0.2, still valid)
1. **Audio**: speaker fixed (userspace config, `docs/02-baseline.md` restore step 5). **Microphone captures no voice**; call uplink
   fails the same way. Tracked in `tasks/M0.5-mic-capture-defect.md`.
2. **Suspend**: ~20% of attempts fail (214 ok / 52 fail).
3. GPS: HAL runs, no fix yet (open-sky test pending).
