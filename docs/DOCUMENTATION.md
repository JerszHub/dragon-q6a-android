# Android 13 (AOSP / GloDroid) on Radxa Dragon Q6A — Bring-up Documentation

**Status:** Android 13 boots fully and deterministically from SD card.
`sys.boot_completed=1` at ~100 s, UI visible on screen, zero crashes. Display, GPU,
USB host, touch (with multitouch), WiFi and Bluetooth all work; on-screen navigation
is present at any display size.

This is an **unofficial community port**. It is not endorsed by Google, Qualcomm or Radxa.

---

## 1. Hardware

| Component | Detail |
|---|---|
| Board | Radxa Dragon Q6A (Qualcomm QCS6490 "Kodiak", Adreno 643 GPU) |
| Boot medium | SD card (8 GB image), UEFI + systemd-boot (BLS type#1 entries) |
| Kernel | Radxa prebuilt `6.18.2-4-qcom` (binary identical to RadxaOS), GKI-style, many drivers `=m` |
| Display | Any HDMI monitor via the onboard RA620 DP→HDMI bridge (kernel reads the display's EDID); USB touchscreens supported, including multitouch |
| WiFi/BT | AICSemi AIC8800D80 combo, attached via USB (`a69c:8d80`) behind onboard 4-port hub |
| USB-C | **Power only.** Both USB controllers are host-only (`dr_mode="host"`, no peripheral controller in DT) → **adb over USB cable is impossible on this board.** Use adb over TCP (WiFi) or UART console |
| Debug UART | UART0 on 40-pin header: GND=pin6, TXD=pin8, RXD=pin10, 115200 8N1, **1.8 V** (use a 1.8 V-capable adapter, e.g. CP2102) |

## 2. Software stack

- **AOSP 13** with **GloDroid** device support (Mesa/Turnip GPU userspace, drm_hwcomposer, minigbm).
- Boot chain: Qualcomm XBL/UEFI (from Radxa firmware partitions) → systemd-boot → kernel `Image` + combined first-stage ramdisk + DTB from the ESP (`/Android/` directory).
- Virtual A/B layout, dynamic partitions in `super`; `/data` ext4 **unencrypted** (FBE disabled in fstab — the kernel lacks the dm-default-key crypto stack).
- The DTB is byte-identical to RadxaOS's `qcs6490-radxa-dragon-q6a.dtb`.

### SD card layout (13 partitions)
1 ESP (vfat, kernel/ramdisk/DTB + systemd-boot), 2–10 Qualcomm/Radxa firmware blobs,
11 `metadata` (ext4), 12 `super` (system/vendor/product), 13 `userdata` (ext4, casefold!).

## 3. The bring-up ladder (every wall, in order, and its fix)

Each item below cost a debug cycle (UART log → root cause → targeted fix). They are listed
in the order they were hit; all are **required** for a working boot.

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 1 | Instant kernel panic | Qualcomm ICE (inline crypto) vs SD boot | Disable ICE; combined ramdisk; `console=tty0` |
| 2 | Silent kernel, dead HDMI | `earlycon=efifb` wrote to dead framebuffer | `earlycon=qcom_geni,0x00994000` (UART) |
| 3 | Recovery loop | No fstab / no dm-* modules in first-stage ramdisk | Add fstab + dm modules (kernel has `DM=m`) |
| 4 | Reboot loop ~57 s, `init_user0_failed` | Blank `metadata` + missing dm-default-key → FBE impossible | Unencrypted `/data` in fstab |
| 5 | Blank screen, SurfaceFlinger crash loop | `a660_sqe.fw` not found (-2) | GPU firmware (sqe/gmu/zap) installed uncompressed to `/vendor/firmware/qcom/` + `firmware_class.path=/vendor/firmware`; zap needs `qcom/qcs6490/` subdir |
| 6 | SF SIGABRT everywhere, `reboot,vold-failed` | (a) FMQ needs ashmem, kernel has no `CONFIG_ASHMEM` → use memfd (`sys.use_memfd=true` + libcutils force-memfd); (b) `fuse.ko` not loaded (`CONFIG_FUSE_FS=m`) | memfd everywhere + fuse.ko in ramdisk |
| 7 | netd crash loop | Netfilter/xtables modules missing | ~30 netfilter modules added to ramdisk |
| 8 | system_server crash → RescueParty | `bandwidthSetGlobalAlert` EREMOTEIO — kernel lacks `xt_quota2` | Patch netd: setGlobalAlert/removeGlobalAlert non-fatal |
| 9 | Sporadic reboot via RescueParty | `com.android.bluetooth` abort loop: `timer_create(CLOCK_BOOTTIME_ALARM)`/SCHED_FIFO EPERM caused by `CONFIG_RT_GROUP_SCHED=y` in the prebuilt kernel | `rt_group_sched=0` on the cmdline disarms it. Bluetooth is then fully enabled: `btlinux` HAL + `bluetooth.ko`/`aic_btusb_usb.ko` in the ramdisk → working `hci0` |
| 10 | Boots fine but panel shows only fbcon (most boots) | GloDroid drm_hwcomposer `ResourceManager::Init()` scans `/dev/dri/card%d` and **breaks at the first stat() failure**; `simpledrm` (built-in, registers from SYSFB) takes minor 0, dies at msm takeover → HWC finds zero devices | `initcall_blacklist=simpledrm_platform_driver_init` → msm becomes card0 deterministically. **This was the single most elusive bug of the port** |
| 11 | Wrong/failed display mode on DP→HDMI | Flaky EDID over DP-AUX through RA620 at boot | `video=HDMI-A-1:e` (+ optionally `drm.edid_firmware=` with your panel's EDID for stubborn panels) |
| 12 | No USB at all (no touch, no WiFi) | `dwc3-qcom.ko` (the Qualcomm glue, `=m`) missing from ramdisk | Add to ramdisk; xhci/usbhid/onboard-hub are built-in |
| 13 | WiFi dead | AIC8800 driver + firmware absent | 4 modules in ramdisk (`rfkill`→`cfg80211`→`aic_load_fw_usb`→`aic8800_fdrv_usb`) + firmware on `/metadata` (see below) |
| 14 | Bluetooth dead (`hci0` never appears, HAL loops "IBluetoothHci not found") | BT transport modules not loaded | `bluetooth.ko` + `aic_btusb_usb.ko` in the ramdisk (dep: `rfkill`, already present) → `hci0` comes up, `btlinux` HAL registers |
| 15 | Touch works but single-touch only | `hid-generic` claims the panel | `hid-multitouch.ko` in the ramdisk, loaded before `dwc3-qcom` so it binds the panel → up to 5-point multitouch |
| 16 | Board reboot-loops before any UI | A kernel module listed in `modules.load` had no `modules.dep` entry → first-stage init's module load is **fatal**, so init aborts and reboots | Every `modules.load` entry must have a matching `modules.dep` line (regenerate `modules.dep` whenever modules are added) |
| 17 | No on-screen navigation (no Home/Back/Recents) | On a tablet form factor navigation is the taskbar; a phone form factor uses a 3-button bar — the wrong density left neither | `ro.sf.lcd_density=170`: small displays become a phone form factor with a navigation bar; large displays keep the taskbar |

### WiFi firmware quirk (important!)
The AICSemi vendor driver does **not** use `request_firmware()` — it opens files directly
with `filp_open()`. Default path `/lib/firmware/aic8800_fw/USB/<chipdir>/<file>`; with the
`aic_fw_path` module parameter the chip subdirectory is **not appended** (flat `path/file`).
Because the WiFi USB device enumerates *after* `switch_root` (~7.9 s vs 7.25 s), ramdisk
files are gone at probe time, and `/vendor` is read-only — so the firmware lives on the
**`metadata` partition** (mounted r/w at 6.8 s, survives switch_root, no dm-verity):

```
/metadata/aic8800_fw/USB/aic8800D80/   ← 15 files from RadxaOS /lib/firmware
cmdline: aic_load_fw_usb.aic_fw_path=/metadata/aic8800_fw/USB/aic8800D80
```
(Permanent home should be the real vendor partition in a future build.)

### Current kernel cmdline (reference)
```
initcall_blacklist=simpledrm_platform_driver_init console=tty0 console=ttyMSM0,115200n8
earlycon=qcom_geni,0x00994000 fbcon=nodefer video=HDMI-A-1:e keep_bootcon ignore_loglevel
loglevel=8 modprobe.blacklist=msm panic=10 coherent_pool=2M
firmware_class.path=/vendor/firmware
aic_load_fw_usb.aic_fw_path=/metadata/aic8800_fw/USB/aic8800D80
irqchip.gicv3_pseudo_nmi=0 psi=1 selinux=1 androidboot.force_normal_boot=1
androidboot.slot_suffix=_a androidboot.hardware=dragon_q6a androidboot.selinux=permissive
androidboot.boot_devices=soc@0/8804000.mmc lsm=landlock,lockdown,yama,integrity,selinux,bpf
printk.devkmsg=on
```
(The cmdline is universal — the kernel reads the connected display's EDID. For a panel
that ships a bad/empty EDID you can supply one with `drm.edid_firmware=HDMI-A-1:edid/<name>.bin`,
placing the blob on the ESP under `Android/edid/`.)

## 4. Developer workflows (Windows/WSL2 host)

- **Full flash:** balenaEtcher with the 8 GB image. Needed only when `super`/`vbmeta` change or `/data` must be wiped.
- **Ramdisk/conf-only changes (no reflash):** attach the SD reader to WSL (`usbipd bind/attach` or `wsl --mount \\.\PHYSICALDRIVE1 --bare`), then `mcopy` directly into the ESP:
  `sudo mcopy -o -i /dev/sdX1 ramdisk.img ::/Android/ramdisk.img && sync`
- **Ramdisk format:** concatenated newc cpio archives, `lz4 -l -9`. Additions are appended as an extra cpio; for `modules.load`/`modules.dep` the **last copy in the stream wins**.
- **Reading crash data without adb:** userdata is casefold ext4 (WSL kernels lack `CONFIG_UNICODE`) — use `debugfs -R "rdump /tombstones /tmp/t" /dev/sdX13`, do **not** mount.
- **UART capture:** PowerShell serial reader on COMx @115200 (board TX → adapter RX only is sufficient for logging).

## 5. Known issues / open items

- **Dark-boot flakiness (layer 2):** on some boots (esp. quick power cuts) the DP link/RA620 produces no signal at all. Suspected residual-charge / link-training issue; success rate across many cold boots still being characterized.
- WiFi and Bluetooth are both working (see ladder #9, #13, #14). `wpa_supplicant`
  brings up `wlan0`; `rt_group_sched=0` + the BT transport modules bring up `hci0`.
- GPU/WiFi firmware should eventually be baked into the real vendor partition
  (GPU firmware is in `/vendor/firmware`; WiFi firmware currently lives on `/metadata`).
- SELinux runs permissive.

## 6. Licensing & redistribution

This port is an integration of existing open-source projects plus binary vendor components:

| Component | Copyright holder | License |
|---|---|---|
| AOSP (system, frameworks) | Google LLC & AOSP contributors | Apache-2.0 (mostly) |
| Linux kernel `6.18.2-4-qcom` | Linus Torvalds & contributors; Qualcomm; Radxa | **GPL-2.0** — source must be available (Radxa publishes it) |
| GloDroid components | GloDroid contributors | Apache-2.0 / GPL (per repo) |
| Mesa (Turnip/Freedreno) | Mesa contributors | MIT |
| Qualcomm firmware (XBL/UEFI, GPU sqe/gmu/zap, etc.) | Qualcomm Technologies, Inc. | Proprietary, redistributable per linux-firmware/Radxa terms |
| AIC8800 driver (dkms) | AICSemi / Radxa packaging | GPL-2.0 |
| AIC8800 firmware | AICSemi | Proprietary blob (redistributed by Radxa) |
| Integration work, patches, scripts, this documentation | the project author | (choose: Apache-2.0 / MIT / CC-BY for docs) |

**Trademark note:** "Android" is a trademark of Google LLC. An uncertified build must not be
marketed as simply "Android" — call it an *unofficial AOSP 13 port*. Do not ship Google apps
(GMS/Play) — they are not licensed for redistribution. **This image contains none.** Users who
want Google apps can flash [MindTheGapps](https://github.com/MindTheGapps) themselves for private
use via the bundled TWRP recovery — see
[FLASHING.md → *Adding Google Apps*](FLASHING.md#adding-google-apps-play-store--gms-via-twrp).
