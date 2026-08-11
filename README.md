# Android 13 for the Radxa Dragon Q6A

An AOSP-based **Android 13** distribution for the **Radxa Dragon Q6A** (Qualcomm
QCS6490), built on [GloDroid](https://github.com/GloDroid). This repository contains
the device tree, the prebuilt kernel and firmware required to build it, and the
end-user documentation.

Ready-to-flash images are published on the [Releases](../../releases) page. The
system boots from an SD card or an NVMe SSD via the board's UEFI firmware; the
onboard SPI firmware and eMMC are not modified.

## Device specifications

| Component | Specification |
|---|---|
| SoC | Qualcomm QCS6490 (Kodiak) |
| CPU | 4× Cortex-A78 + 4× Cortex-A55 |
| GPU | Adreno 643 |
| Memory | 8 GB LPDDR5 |
| Storage | microSD, M.2 M-key 2230 NVMe (PCIe Gen3 ×2), eMMC |
| Display | HDMI via onboard RA620 DP→HDMI bridge; MIPI-DSI |
| Networking | Gigabit Ethernet (RTL8168h), AIC8800D80 Wi-Fi + Bluetooth |
| Audio | HDMI/DisplayPort, 3.5 mm analog jack, Bluetooth A2DP |

## Features

**Platform**

- Android 13 (AOSP) with GloDroid HAL support
- Adreno 643 hardware acceleration — OpenGL ES 3.2 and Vulkan 1.3 (Mesa, freedreno/Turnip)
- Virtual A/B partition layout with dynamic partitions
- Linux 6.18 (`6.18.2-4-qcom`)

**Display and input**

- HDMI output at the connected display's native mode, configured from its EDID
- MIPI-DSI support for the Radxa Display 8HD (Jadard JD9365DA-H3 + Goodix GT911 touch)
- USB touchscreens, including multitouch up to 5 points
- Manual display rotation through a Quick Settings tile (the board has no accelerometer)
- Adaptive navigation: a 3-button navigation bar on small displays, the system taskbar on large ones

**Connectivity**

- Gigabit Ethernet
- Onboard Wi-Fi (AIC8800D80) and Bluetooth
- USB Wi-Fi adapters — Realtek (rtw88, rtl8xxxu), MediaTek (mt76) and Broadcom (brcmfmac)
  drivers and firmware are included. Connecting an adapter raises a notification that
  switches the active Wi-Fi interface to it; removing the adapter restores the onboard radio
- USB mass storage with FAT, exFAT and NTFS
- ADB over TCP on port 5555

**Audio**

- HDMI/DisplayPort output through the QCS6490 LPASS/AudioReach pipeline
- 3.5 mm analog stereo output
- Bluetooth A2DP
- Automatic routing between outputs as devices are connected and disconnected

**System**

- TWRP recovery, reachable from the bundled Reboot to Recovery application or `adb reboot recovery`
- Lawnchair launcher
- Google applications are not included; they can be installed through the bundled
  recovery — see [docs/FLASHING.md](docs/FLASHING.md#google-applications-play-store--gms)

## Not supported

- **Hardware video decoding.** The Venus video codec requires proprietary firmware that
  is not part of this distribution. Video is decoded in software.
- **Hexagon NPU.** On-device ML acceleration requires proprietary Qualcomm libraries.
  GPU acceleration is unaffected.
- **ADB over USB.** Both USB controllers on this board are host-only; the USB-C port
  supplies power only. Use ADB over TCP.

## Installation

Download the image from the [Releases](../../releases) page and write it to an SD card
or NVMe SSD. Full instructions, including NVMe installation and Google applications,
are in **[docs/FLASHING.md](docs/FLASHING.md)**.

```bash
zstd -d dragon_q6a_universal-v6.img.zst -o dragon_q6a_universal-v6.img
sudo dd if=dragon_q6a_universal-v6.img of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

The first boot initialises `/data` and runs application optimisation; it takes several
minutes and may restart once. Subsequent boots are fast.

## Building

The device tree builds inside a GloDroid (Android 13) checkout:

```bash
# from a synced GloDroid tree
cp -r device/glodroid/dragon_q6a <glodroid>/device/glodroid/

# fetch the Lawnchair launcher (third-party, not redistributed here)
scripts/fetch-lawnchair.sh

source build/envsetup.sh
lunch dragon_q6a-userdebug
make droid

# assemble the flashable image
device/glodroid/dragon_q6a/gensdimg-uefi.sh
```

The kernel is the RadxaOS prebuilt `6.18.2-4-qcom` and is not rebuilt: `prebuilt/Image`
and `prebuilts-radxa/modules.tar.gz` are committed directly. See `NOTICE` for the
GPL-2.0 source offer.

## Repository layout

```
device/glodroid/dragon_q6a/   device tree (BoardConfig, device.mk, esp/, firmware/, prebuilt/)
  apps/                       bundled applications: Lawnchair, ScreenRotate
  health/                     health HAL for the battery-less board
  idc/                        input device configuration
docs/                         installation guide, technical reference, kernel/DT references
prebuilts-radxa/              kernel modules, audio firmware, bootloader
scripts/                      build helpers
```

## Licence and attribution

Repository contributions are licensed under **Apache-2.0** (see `LICENSE`). The prebuilt
kernel and modules are **GPL-2.0** (RadxaOS); GPU, Wi-Fi and Bluetooth firmware are
proprietary redistributable vendor blobs. The Lawnchair launcher is **GPL-3.0** and is
fetched at build time rather than redistributed here. Full attribution and the kernel
source offer are in `NOTICE`.

This is an independent, unofficial project and is not affiliated with or endorsed by
Google, Radxa, Qualcomm or AICSemi. Android is a trademark of Google LLC. This is an
uncertified AOSP build and ships no Google applications.
