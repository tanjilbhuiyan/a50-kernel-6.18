# Vendor kernel ABI contract (M1.3): what the stock Android 11 userspace actually does

Captured on the baseline phone (kernel 4.14.194 Mint-user, UT 26.04 with the 2026-11-02 systemd-symlink fix), 2026-11-02/03.
Raw strace logs: `raw/`; opener map: `openers-raw.txt`; all rows: `summary.tsv`; per-subsystem tables: `mali.md`, `ion.md`,
`display.md`, `audio.md`, `wifi_bt.md`, `modem.md` (+ `net.md`, `other.md`, `binder.md`). Produced by `tools/cap_ioctl.sh` (phone)
and `tools/ioctl_summary.py` (laptop; numbers computed from `_IOC` tuples and the 4.14 headers, names from the driver headers).
Scenarios traced: steady UI use (38 s), UI with app cold-starts (42 s), audio playback (14 s), cellular call (45 s window, ~27 s of call),
Wi-Fi idle (14 s), GNSS + sensors idle (12 s), Bluetooth power-cycle + reconnect (36 s).

## How to read this (important)
- **Observed is not the same as needed.** Clients that were already running had finished their initialisation, so open-time ioctls
  (for example Mali `VERSION_CHECK`/`SET_FLAGS`/`GET_GPUPROPS`, and firmware or boot handshakes) are not in the tables. The complete
  ioctl sets are in the driver headers (e.g. `drivers/gpu/arm/b_r26p0/mali_kbase_ioctl.h` has 92 ioctls) and must keep working.
- The audio HAL is a **32-bit process**: its request numbers are compat-sized (e.g. `SNDRV_CTL_IOCTL_ELEM_READ` = 0xc2c85512, size 0x2c8).
  The hex values for NAMED requests in the tables come from 64-bit headers; the 6.18 kernel must keep the compat ioctl paths.
- Attach-mode strace makes the traced process very slow: tracing the Lomiri shell broke login/input while attached (see the M1.3 log).
  Read/write/mmap/netlink traffic and boot-time activity were not traced.

## Per subsystem
| Subsystem | Opener(s) | Node(s) | Observed ioctls (calls) | What 6.18 must provide |
|---|---|---|---|---|
| Mali GPU | lomiri, lomiri-system-compositor, maliit-server (host side, libhybris/Mali blob) | `/dev/mali0` | kbase type 0x80: JOB_SUBMIT, MEM_SYNC, MEM_QUERY, MEM_ALLOC, FENCE_VALIDATE, MEM_IMPORT, MEM_FREE (19882 calls) | The exact Mali kbase **r26p0** ioctl ABI (the userspace blob is fixed); `mali.md` |
| ION / buffers | allocator@2.0 (gralloc, Android container); composer, lomiri, compositor use the resulting dma-bufs | `/dev/ion`, `anon_inode:dmabuf_ion`, `anon_inode:sync_file` | ION_IOC_ALLOC (43), ION_IOC_HEAP_QUERY (86); **Samsung-only DMA_BUF_IOCTL_TRACK/UNTRACK** (type 'b' nr 8/9, ~650 calls each); sync_file SYNC_IOC_MERGE (1244) | ION is gone upstream: needs an ION-compatible node with ALLOC and HEAP_QUERY, plus TRACK/UNTRACK on dma-buf fds (or the userspace must be patched); `ion.md` |
| Display | composer@2.1 (HWC, Android container); lomiri-system-compositor opens fb0/g2d | `/dev/graphics/fb0` | FBIOBLANK, S3CFB_POWER_MODE, S3CFB_SET_VSYNC_INT, **S3CFB_WIN_CONFIG** (1040-byte struct, 638 calls in 42 s) | The DECON/dpu20 fbdev ioctl interface (`S3CFB_*`); `display.md` |
| Audio | audio.service (audio HAL, 32-bit, Android container) | `/dev/snd/controlC0`, `pcmC0D0p`, `D2p`, `D4p`, `D7p` (speaker amp), `D11c`, `D12c` | standard ALSA PCM ioctls (HW_PARAMS, SW_PARAMS, PREPARE, START, WRITEI_FRAMES, SYNC_PTR, DROP, INFO) and CTL ELEM_READ/WRITE | ABOX + tfa98xx ALSA cards with the same PCM device numbering, plus 32-bit compat ioctls; `audio.md` |
| Wi-Fi / BT (scsc) | bluetooth@1.0 -> `/dev/scsc_h4_0`; wpa_supplicant and Wi-Fi HAL via sockets | `/dev/scsc_h4_0` (no ioctls seen); sockets | none on `/dev/scsc_*` during a BT power-cycle + connect (read/write not traced); socket ioctls by wpa_supplicant: FIONREAD (1662), TIOCOUTQ (46), TCGETS2 (4), SIOCGIFINDEX (2) | The scsc h4 char device and the Wi-Fi netdev/nl80211 interface; `wifi_bt.md`, `net.md` |
| Modem | rild (2 processes), cbd | `/dev/umts_ipc0`, `umts_ipc1`, `umts_rfs0`, `umts_boot0` | **IOCTL_MODEM_STATUS** (`_IO('o', 0x27)`) polled by rild (125 calls in ~27 s of call); cbd quiet | The modem_v1 IPC device nodes and their ioctls (`drivers/misc/modem_v1/modem_prj.h`); `modem.md` |

## Nodes open at scan time but with NO ioctl seen in the tested scenarios
`/dev/fb0` (lomiri-system-compositor), `/dev/g2d` (composer@2.1, lomiri-system-compositor), `/dev/gnss_ipc` (gpsd, idle only),
`/dev/scsc_h4_0` (bluetooth@1.0), `/dev/ssp_sensorhub` (sensors@2.0, idle only), `/dev/tzdev` (7 TEE daemons, not traced),
`/dev/umts_boot0` (cbd, quiet in window), `/dev/umts_rfs0` (rild). They are used by the stock userspace (they are open), so treat them
as required; "no ioctl observed" is a statement about the captured scenarios only.

## Not covered
Boot-time ioctls, camera (`/dev/video*`), input (`/dev/input/event*`), sensors under load, GNSS with a fix, MFC/codecs, TEE traffic, read/write
protocols on char devices, netlink. M1.3 acceptance covers the six subsystems above; extend captures when a later milestone needs them.
