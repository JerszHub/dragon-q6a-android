# Technical reference

Reference documentation for the Android 13 distribution for the Radxa Dragon Q6A. It
describes the system as shipped; installation instructions are in
[FLASHING.md](FLASHING.md).

## Platform

| | |
|---|---|
| Android | 13 (AOSP), GloDroid device support |
| Kernel | RadxaOS prebuilt `6.18.2-4-qcom`, GKI-style with most drivers built as modules |
| Graphics | Mesa — freedreno (OpenGL ES 3.2) and Turnip (Vulkan 1.3), drm_hwcomposer, minigbm |
| Partitioning | Virtual A/B, dynamic partitions in `super` |
| `/data` | ext4, unencrypted — the kernel does not provide the dm-default-key crypto stack |
| Build target | `dragon_q6a-userdebug` |

## Boot chain

```
Qualcomm XBL / UEFI  (SPI flash, unmodified)
        │
        ▼
systemd-boot  (EFI/BOOT/BOOTAA64.EFI on the ESP)
        │  reads loader/loader.conf and loader/entries/*.conf
        ▼
Linux kernel + first-stage ramdisk + DTB   (from /Android on the ESP)
        │
        ▼
Android first-stage init → super (system/vendor/product) → Android
```

The bootloader runs with `timeout 0` and boots the entry named by `default` in
`loader/loader.conf`. Entry names have their `.conf` suffix stripped, so the value is
`android`, not `android.conf`.

### Boot entries

| Entry | Purpose |
|---|---|
| `android` | Default. HDMI output, quiet console (`loglevel=3`, no serial console) |
| `android-dsi8hd` | Radxa Display 8HD (MIPI-DSI) |
| `android-dsi8hd-debug` | Radxa Display 8HD with full kernel logging on the serial console |
| `android-dsi10fhd` | Radxa Display 10FHD (MIPI-DSI); the panel driver is not in this kernel |
| `twrp` | TWRP recovery |

Apart from the default entry, all entries carry `console=ttyMSM0,115200n8` with
`ignore_loglevel` for diagnostic use.

Recovery is also selected at runtime through the Android boot control block, which the
bootloader reads on start — this is what `adb reboot recovery` and the bundled
Reboot to Recovery application use.

## Storage layout

Thirteen partitions: the ESP (FAT, holds the bootloader, kernel, ramdisk and device
trees), the Qualcomm and Radxa firmware partitions, `metadata`, `super` and `userdata`.

The same image boots from either SD or NVMe. `androidboot.boot_devices` lists both the
SD controller and `1c08000.pcie`, and the PCIe PHY module is loaded in first-stage init
so an NVMe device is available before `/data` and `super` are mounted.

## Subsystem notes

**Display.** The DPU drives the DisplayPort controller and the onboard RA620 DP→HDMI
bridge. `simpledrm` is blacklisted at boot so the msm DRM device is the one the
hardware composer targets. HDMI mode selection is driven entirely by the connected
display's EDID.

**GPU.** Adreno 643. The a660 SQE and GMU firmware must be present uncompressed under
`/vendor/firmware`, with `firmware_class.path` pointing at it.

**Audio.** The full QCS6490 LPASS/AudioReach path: ADSP firmware, q6apm kernel modules
loaded in dependency order, the board topology binary, and a tinyalsa HAL configuration
describing the output devices. ALSA card 0 (`QCS6490-Radxa-Dragon-Q6A`) carries HDMI and
the analog jack; routing between headphone, HDMI and Bluetooth outputs is exclusive and
follows connection state. Bluetooth A2DP uses its own HAL.

**Wi-Fi.** The onboard AIC8800D80 is a USB fullmac device driven by `wpa_supplicant`
and `wificond` with no vendor HAL. Its firmware is loaded through `filp_open`, so it must
be reachable on a filesystem that survives `switch_root`. USB adapter drivers and
firmware for Realtek, MediaTek and Broadcom parts are included; the active interface is
switched at runtime rather than by rebuilding.

**Bluetooth.** The AIC8800D80 Bluetooth function is a standard USB transport;
`bluetooth.ko` and `aic_btusb_usb.ko` bring up `hci0` and the GloDroid `btlinux` HAL
drives it. `rt_group_sched=0` is set on the kernel command line.

**Kernel modules.** Modules loaded in first-stage init are fatal on failure: every entry
in `modules.load` must also resolve through `modules.dep`, or init aborts before
userspace starts.

**Console.** Printing to the serial console is synchronous and blocking, so verbose
kernel logging materially increases boot time. The default entry therefore runs quiet
(`loglevel=3`, no `console=ttyMSM0`); the remaining entries keep full serial logging for
diagnostic use.

## Reference material

`references/` contains the kernel configuration (`config-6.18.2-4-qcom`) and the board
device tree source (`qcs6490-radxa-dragon-q6a.dts`) for the shipped kernel.
