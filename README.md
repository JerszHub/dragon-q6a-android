# Android 13 (GloDroid / AOSP) on the Radxa Dragon Q6A

A from-scratch [GloDroid](https://github.com/GloDroid)-based **Android 13** port for
the **Radxa Dragon Q6A** (Qualcomm QCS6490), booting from SD card via UEFI +
systemd-boot. This repository holds the device tree, the prebuilt artifacts needed
to build and flash, the cmdline/ramdisk history, and the full UART bring-up journey.

> Status: **boots to the Android 13 UI with working display, GPU, USB/touch
> (multitouch), WiFi and Bluetooth.** See `docs/PROGRESS.md` and `boot-logs/` for
> the hardware-in-the-loop bring-up.

## What works


| Subsystem | Status | Notes |
|-----------|--------|-------|
| Boot chain | ✅ | Qualcomm UEFI (SPI) → systemd-boot → kernel + DTB + ramdisk from ESP |
| Boot to UI | ✅ | `sys.boot_completed=1`, zero reboots |
| Storage (SD **or NVMe**) | ✅ | **One universal image boots from either the SD card or an M.2 NVMe SSD.** PCIe PHY (`phy-qcom-qmp-pcie`) baked into the ramdisk; `boot_devices` lists both `mmc` + `1c08000.pcie` (Gen3 ×2). UEFI boots from NVMe, so the SD can be removed. ~1.0 GB/s write / ~0.97 GB/s read (`dd`) |
| Ethernet | ✅ | Onboard Realtek RTL8168h on PCIe (`1c00000.pcie`); `r8169` in the ramdisk → Gigabit `eth0`, link verified at 1 Gbps full-duplex |
| Display | ✅ | DPU → DP → onboard RA620 DP→HDMI bridge. `initcall_blacklist=simpledrm` so HWC takes the panel. **Universal HDMI** — the kernel reads the connected display's EDID (`video=HDMI-A-1:e`); no per-panel configuration required |
| GPU | ✅ | Adreno 643 (A660), OpenGL ES 3.2 / Mesa 23.0 (freedreno), Vulkan 1.3 (Turnip); GPU firmware uncompressed in vendor |
| USB host + touch | ✅ | dwc3 host + onboard hub; USB touchscreens work as real touchscreens (IDC forces `touch.deviceType=touchScreen`), with **multitouch** via `hid-multitouch` (up to 5 points) |
| WiFi | ✅ | AIC8800D80 (USB), fullmac; `wpa_supplicant` + `wificond`, no vendor HAL |
| Bluetooth | ✅ | AIC8800D80 BT = standard USB transport; `bluetooth.ko` + `aic_btusb_usb.ko` bring up `hci0`, GloDroid `btlinux` HAL drives it. `rt_group_sched=0` on the cmdline disarms an `RT_GROUP_SCHED` abort-loop |
| adb over TCP | ✅ | `service.adb.tcp.port=5555` (USB-C is power-only — both USB controllers are host-only, so adb-by-cable is not possible on this board) |
| Navigation | ✅ | A 3-button navigation bar on small displays; on large displays the system taskbar provides navigation. Driven by the UI density (`ro.sf.lcd_density=170`), so there is always an on-screen way to go Home/Back/Recents |
| Launcher | ✅ | Lawnchair as the default home (seeded at boot); Launcher3QuickStep kept for recents. APK fetched via `scripts/fetch-lawnchair.sh`, not committed |
| Screen orientation | ✅ | No accelerometer on this board, so rotation is manual: a built-in `ScreenRotate` app (Quick Settings tile + drawer app) rotates the panel via `IWindowManager.freezeRotation()`. `display_settings.xml` makes WM ignore per-app orientation requests so the user's choice wins |
| Battery | ✅ | Battery-less SBC; a small health HAL reports full AC power instead of a stuck 0% |

🔥

## Hardware

- **Board:** Radxa Dragon Q6A (Qualcomm QCS6490 / Kodiak)
- **Display:** any HDMI monitor via the onboard RA620 DP→HDMI bridge (the kernel
  reads the display's EDID); USB touchscreens are supported, including multitouch
- **Storage:** boots from SD card (`mmc@8804000`) **or M.2 NVMe SSD** (M-key 2230,
  PCIe Gen3 ×2 on `1c08000.pcie`) — the same universal image works on either; eMMC untouched
- **Ethernet:** onboard Realtek RTL8168h Gigabit on PCIe (`1c00000.pcie`)
- **WiFi/BT:** AIC8800D80 combo, USB-attached behind the onboard hub
- **Debug:** UART0 on the 40-pin header (GND=pin6, board-TX=pin8, board-RX=pin10, 115200 8N1, 1.8 V)

## Quick flash (ready-made image)

A ready-to-flash community image (`.img.zst`) is attached to the
[Releases](../../releases) page. Full step-by-step instructions — including how to
prepare the card and grow the data partition — are in **[`docs/FLASHING.md`](docs/FLASHING.md)**.

The short version (replace `sdX` with your card — double-check the device!):

```bash
zstd -d dragon_q6a_universal_gapps-ready.img.zst -o dragon_q6a_universal_gapps-ready.img
sudo dd if=dragon_q6a_universal_gapps-ready.img of=/dev/sdX bs=4M status=progress conv=fsync && sync
```

Then insert the card and power on. **The first boot is slow and may reboot itself
once or twice and sit on a black screen / boot animation for a few minutes — this is
normal** (it formats `/data` and runs first-boot optimization). Later boots are fast.

## Build from source

This device tree plugs into a GloDroid (Android 13, `master`) checkout:

```bash
# inside a synced glodroid tree:
cp -r device/glodroid/dragon_q6a <glodroid>/device/glodroid/
# the prebuilt kernel Image + DTB live under device/glodroid/dragon_q6a/prebuilt/
# fetch the Lawnchair launcher APK (third-party, not committed):
scripts/fetch-lawnchair.sh
source build/envsetup.sh
lunch dragon_q6a-userdebug
make droid              # add -j<N> to taste for your build host
# then assemble the SD image:
device/glodroid/dragon_q6a/gensdimg-uefi.sh
```

The kernel is the **RadxaOS prebuilt 6.18.2-4-qcom** (not rebuilt) — `prebuilt/Image`
and `prebuilts-radxa/modules.tar.gz` are committed directly. See `NOTICE` for the
GPL-2.0 source offer.

## Repository layout

```
device/glodroid/dragon_q6a/   the device tree (BoardConfig, device.mk, esp/, firmware/,
                              prebuilt/, gensdimg-uefi.sh) — drop into a GloDroid checkout
  apps/                       baked apps: Lawnchair (prebuilt import) + ScreenRotate (rotation UI)
  health/                     AC-power health HAL for the battery-less board
docs/                         DOCUMENTATION, FLASHING, ARCHITECTURE, PROGRESS + reference DTS/kernel config
prebuilts-radxa/              RadxaOS extracts (modules.tar.gz, BOOTAA64.EFI)
images/                       latest ramdisk + cmdline (.conf) history
boot-logs/                    verbatim UART boot logs across the whole bring-up
scripts/                      helper scripts
```

## Notes on the bring-up

This port required solving a chain of QCS6490/GloDroid-specific issues, all
documented in the boot logs and `docs/PROGRESS.md`:

- **FMQ / memfd** — kernel lacks `CONFIG_ASHMEM`; needs `sys.use_memfd=true`.
- **fuse / netd / RescueParty loops** — `fuse.ko`, netfilter modules, and netd
  `setGlobalAlert` made non-fatal (kernel lacks `xt_quota2`).
- **Display** — `simpledrm` had to be blacklisted so the real msm DRM (`card0`)
  is the one HWC composes onto.
- **GPU firmware** — a660 SQE/GMU must be uncompressed in `/vendor/firmware`.
- **WiFi** — GloDroid is intentionally no-vendor-HAL; the only gap was a build
  flag (`GD_NO_DEFAULT_WIFI`) that dropped `wpa_supplicant`. The AIC fullmac
  driver creates `wlan0` on demand. Firmware loads from `/metadata` (the driver
  uses `filp_open`, so it must survive `switch_root`).
- **Bluetooth** — same kernel-module pattern: `bluetooth.ko` + `aic_btusb_usb.ko`
  in the ramdisk bring up `hci0`; the `btlinux` HAL then drives it. The
  `RT_GROUP_SCHED` abort-loop is disarmed with `rt_group_sched=0`.
- **Kernel modules are loaded fatally in first-stage init** — every module listed
  in `modules.load` must also have a `modules.dep` entry, or init aborts and the
  board reboot-loops before the kernel even reaches userspace UI. (This bit the
  multitouch and Bluetooth bring-up; see `docs/FLASHING.md`/`docs/PROGRESS.md`.)

## License & attribution

Repository contributions: **Apache-2.0** (`LICENSE`). Prebuilt kernel/modules are
**GPL-2.0** (RadxaOS); GPU and WiFi/BT firmware are proprietary-redistributable
vendor blobs. The Lawnchair launcher is **GPL-3.0** (fetched at build time, not
redistributed here). Full attribution and the kernel source offer are in `NOTICE`.

This is an independent, unofficial project, not affiliated with or endorsed by
Google, Radxa, Qualcomm, or AICSemi. "Android" is a trademark of Google LLC; this
is an uncertified AOSP-based build and ships no Google apps.
