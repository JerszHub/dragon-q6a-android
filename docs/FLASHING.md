# Installation guide

This guide covers writing the Android 13 image to an SD card or an NVMe SSD,
selecting a display panel, and installing Google applications.

The image boots through the board's existing UEFI firmware. The onboard SPI
firmware and any eMMC contents are left untouched, so the installation is
reversible — re-write or replace the card to go back.

**Requirements**

- An SD card of 8 GB or more (16 GB or larger recommended), or an M.2 2230 NVMe SSD
- The release asset `dragon_q6a_universal-v6.img.zst` (or `.img.xz`)
- A card reader, or a USB→M.2 adapter for NVMe

---

## Writing the image

### Graphical (any operating system)

[balenaEtcher](https://etcher.balena.io/) and Raspberry Pi Imager read the compressed
image directly:

1. Select `dragon_q6a_universal-v6.img.zst` (or the `.img.xz` asset).
2. Select the target card.
3. Write.

### Command line (Linux, WSL2, macOS)

> **Warning:** `dd` writes to a raw block device. Confirm the target before running it —
> writing to the wrong disk destroys its contents. Use `lsblk` on Linux or
> `diskutil list` on macOS.

Identify the card:

```bash
lsblk -do NAME,SIZE,RM,TYPE,MODEL     # the card is the removable (RM=1) device
```

Clearing any previous partition table first — including the backup GPT at the end of
the card — avoids a stale table being detected:

```bash
sudo sgdisk --zap-all /dev/sdX
sudo wipefs -a /dev/sdX
```

Write the image:

```bash
zstd -dc dragon_q6a_universal-v6.img.zst | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

### Using the full card capacity

The image ships a small `userdata` partition. To extend it across the whole card, move
the backup GPT to the end of the device and grow partition 13:

```bash
sudo sgdisk -e /dev/sdX            # relocate the backup GPT
sudo growpart /dev/sdX 13          # extend userdata
sudo partprobe /dev/sdX
```

Android formats `/data` on first boot, so no filesystem resize is required. This step is
optional; the system boots on the as-written layout.

### First boot

Insert the card and power on. The first boot initialises `/data` and runs application
optimisation. It takes several minutes, may restart once, and shows the boot animation or
a black screen while it works. Subsequent boots are considerably faster.

---

## Installing to an NVMe SSD

The same image boots from either medium: the kernel command line lists both boot devices
and the PCIe PHY is loaded in first-stage init, so `/data` and `super` mount from
whichever device holds the partitions. The board's UEFI boots from NVMe, so an SSD
installation is standalone and the SD card can be removed.

- Slot: onboard M.2 M-key 2230, PCIe Gen3 ×2
- Measured throughput: approximately 1.0 GB/s write, 0.97 GB/s read (single-stream `dd`)

> **Warning:** writing the image to the SSD erases everything on it, including any
> existing operating system.

### With a USB→M.2 adapter

Identical to writing an SD card: connect the SSD to a computer and follow the steps
above, using the SSD's block device as the target. Grow partition 13 the same way, then
move the SSD into the board's M.2 slot.

### From a running system

The image can also be written to the SSD from the board itself:

1. Write the image to an SD card and boot the board once with the NVMe installed.
2. From a computer on the same network, stream the image onto the SSD over ADB:

   ```bash
   adb connect <device-ip>:5555
   adb root
   zstd -dc dragon_q6a_universal-v6.img.zst | adb shell 'dd of=/dev/block/nvme0n1 bs=4M conv=fsync'
   ```

3. Power off, remove the SD card and power on. The system boots from the SSD.

To use the SSD's full capacity, grow partition 13 later from a computer with a USB→M.2
adapter. Without that step the installation still boots; `/data` simply uses the
as-written size.

---

## Google applications (Play Store / GMS)

The image is vanilla AOSP and contains no Google applications, which cannot be
redistributed without a licence. The bundled TWRP recovery allows them to be installed
afterwards. The build is prepared for this: dm-verity is disabled, the `super`
sub-partitions are writable and have free space, and TWRP handles the dynamic partitions.

**Requirements**

- `MindTheGapps-13.0.0-arm64-*.zip` on a USB stick (FAT, exFAT or NTFS)
- A USB keyboard and mouse — the recovery interface is cursor-driven
- Network access to the device for ADB, if entering recovery from a computer

### 1. Enter recovery

The bootloader boots Android directly, so recovery is triggered from the running system:

- **On the device:** open the bundled **Reboot to Recovery** application.
- **From a computer:**

  ```bash
  adb connect <device-ip>:5555
  adb reboot recovery
  ```

The board restarts into TWRP. Connect the USB stick, keyboard and mouse.

### 2. Install the package

In TWRP select **Install**, change the storage to the USB volume, select the
MindTheGapps archive and confirm.

### 3. Format data

> **Important:** use **Wipe → Format Data** and type `yes` when prompted. Do not use the
> Factory Reset slider — it mounts `/data` to delete files, which fails on this device and
> reports *"Factory Reset Failed"*. Format Data performs a raw reformat instead. An
> *"Unable to mount /data"* message immediately after formatting is expected; Android
> re-initialises the partition on the next boot.

### 4. Reboot

Select **Reboot → System**. This boot is slow — it re-initialises `/data`, runs
application optimisation and sets up Google services. The Play Store is present once the
launcher appears.

Sign in to the Google account from the setup wizard and the Play Store works — no device
registration step is required.

Applications gated on Play Integrity, such as banking applications, will not pass on a
test-key build. In the rare case that sign-in is refused with *"This device isn't Play
Protect certified"*, register the device's Google Services Framework ID once at
[google.com/android/uncertified](https://www.google.com/android/uncertified/).

---

## Display selection

HDMI is the default output and requires no configuration — the kernel reads the connected
display's EDID and uses its native mode.

The image also ships boot entries for Radxa's MIPI-DSI panels:

- **Radxa Display 8HD** (`android-dsi8hd`) — panel and Goodix GT911 touch drivers are
  included. DSI support is experimental.
- **Radxa Display 10FHD** (`android-dsi10fhd`) — a boot entry is present, but the panel
  driver is not in this kernel, so the panel may not initialise.

There is no interactive boot menu; the bootloader is configured with `timeout 0` and boots
the default entry immediately. A DSI panel is selected by making its entry the default.

Power off, remove the card and open the **`esp`** partition on any computer — it is a
standard FAT partition. Edit `loader/loader.conf` and set the `default` line:

```
default android-dsi8hd
```

HDMI installations leave this as `default android`. Each entry carries its own device
tree; reverting is a matter of changing the line back. Further details are in
`loader/README-DSI.txt` on the ESP.

---

## Troubleshooting

**No picture on an HDMI display.** The image reads the display's EDID. If a display
provides an invalid or empty EDID, supply one manually: place the EDID blob at
`Android/edid/<name>.bin` on the ESP partition and add
`drm.edid_firmware=HDMI-A-1:edid/<name>.bin` to the `options` line in
`loader/entries/android.conf`.

**A USB touchscreen behaves like a mouse.** Known USB touch panels are mapped to
touchscreens by input device configuration. An unlisted panel needs an `.idc` file keyed
to its USB vendor and product ID.

**A USB Wi-Fi adapter is not used.** Android uses the onboard radio by default. Connecting
an adapter raises a notification offering to switch to it; the onboard radio is restored
when the adapter is removed.

**Verbose boot logging.** The default boot entry runs with a quiet console. The
remaining entries in `loader/entries/` keep full kernel logging on the serial console
(UART0, 115200 8N1) and can be made the default the same way a DSI panel is selected.
