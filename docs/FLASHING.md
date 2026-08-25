# Installation guide

This guide covers writing the Android 13 image to an SD card or an NVMe SSD,
selecting a display panel, and installing Google applications.

The image boots through the board's existing UEFI firmware. The onboard SPI
firmware and any eMMC contents are left untouched, so the installation is
reversible — re-write or replace the card to go back.

**Requirements**

- An SD card of 8 GB or more (16 GB or larger recommended), or an M.2 2230 NVMe SSD
- The release asset `dragon_q6a_universal-v7.img.zst` (or `.img.xz`)
- A card reader, or a USB→M.2 adapter for NVMe

---

## Writing the image

### Graphical (any operating system)

[balenaEtcher](https://etcher.balena.io/) and Raspberry Pi Imager read the compressed
image directly:

1. Select `dragon_q6a_universal-v7.img.zst` (or the `.img.xz` asset).
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
zstd -dc dragon_q6a_universal-v7.img.zst | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
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
2. Confirm the system is running from the **card**, not the SSD — otherwise the following
   steps overwrite the running system:

   ```bash
   adb connect <device-ip>:5555
   adb root
   adb shell readlink /dev/block/by-name/super    # must print mmcblk1p12
   ```

3. Copy the image across in chunks, verifying each one before writing it:

   ```bash
   zstd -d dragon_q6a_universal-v7.img.zst -o img
   off=0
   while [ $off -lt $(stat -c%s img) ]; do
     dd if=img of=chunk.bin bs=1M skip=$((off/1048576)) count=64 status=none
     adb push chunk.bin /data/local/tmp/chunk.bin
     [ "$(sha256sum chunk.bin | cut -d' ' -f1)" = \
       "$(adb shell sha256sum /data/local/tmp/chunk.bin | cut -d' ' -f1 | tr -d '\r')" ] \
       || { echo "chunk corrupted — aborting"; break; }
     adb shell "dd if=/data/local/tmp/chunk.bin of=/dev/block/nvme0n1 \
                bs=1M seek=$((off/1048576)) conv=fsync"
     off=$((off + 64*1024*1024))
   done
   ```

   > **Do not pipe the image through `adb shell dd`.** Streaming an image into
   > `adb shell 'dd of=…'` (or `adb exec-in`) exits successfully while silently dropping
   > blocks. The result appears to have been written correctly and then fails to boot.
   > The chunked form above is also several times faster.

4. Verify the whole write before booting from it:

   ```bash
   adb shell "dd if=/dev/block/nvme0n1 bs=1M count=8192 2>/dev/null | sha256sum"
   sha256sum img          # the two values must match
   ```

5. Power off, remove the SD card and power on. The system boots from the SSD.

To use the SSD's full capacity, grow partition 13 later from a computer with a USB→M.2
adapter. Without that step the installation still boots; `/data` simply uses the
as-written size.

### Updating an existing installation in place

Releases keep the same partition layout, so a card or SSD already running an earlier
release can be updated **without touching `/data`**. Write every partition except
`userdata` — that is `esp`, `boot_a`, `boot_b`, `vendor_boot_a`, `vendor_boot_b`, the
four `vbmeta` partitions and `super`. Leave `metadata` alone as well; it holds Wi-Fi
firmware placed there when the image was first written.

Installed applications, accounts, Wi-Fi credentials and game data all survive. Google
applications live inside `super` and are replaced along with it, so they have to be
flashed again — see **Upgrading** below, which does *not* involve wiping data.

---

## Google applications (Play Store / GMS)

The image is vanilla AOSP and contains no Google applications, which cannot be
redistributed without a licence. The bundled TWRP recovery allows them to be installed
afterwards. The build is prepared for this: dm-verity is disabled, the `super`
sub-partitions are writable and have free space, and TWRP handles the dynamic partitions.

**Requirements**

- `MindTheGapps-13.0.0-arm64-*.zip`
- A USB keyboard and mouse — the recovery interface is cursor-driven
- Network access to the device for ADB, if entering recovery from a computer

The package can be supplied on a USB stick (FAT, exFAT or NTFS), or — if the system is
already running and `/data` is intact — copied straight to internal storage, which avoids
needing a stick at all:

```bash
adb push MindTheGapps-13.0.0-arm64-*.zip /sdcard/
```

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

In TWRP select **Install**, choose the storage holding the package and select the
MindTheGapps archive.

> A package copied to `/sdcard` appears at the top level of **Internal Storage**. TWRP
> lists directories before files, so scroll past the folders to find it.

### 3. Format data — first installation only

> **Skip this step when upgrading.** It is required only when installing Google
> applications onto a system that has never had them. On an upgrade it is unnecessary and
> destroys the data you were preserving — see **Upgrading** below.

> **Important:** use **Wipe → Format Data** and type `yes` when prompted. Do not use the
> Factory Reset slider — it mounts `/data` to delete files, which fails on this device and
> reports *"Factory Reset Failed"*. Format Data performs a raw reformat instead. An
> *"Unable to mount /data"* message immediately after formatting is expected; Android
> re-initialises the partition on the next boot.

### 4. Reboot

Select **Reboot → System**. This boot is slow — it re-initialises `/data`, runs
application optimisation and sets up Google services. The Play Store is present once the
launcher appears.

### Upgrading: installing Google applications over existing data

When a release is installed over a previous one without wiping `userdata`, `super` is
replaced and the Google applications in it disappear, while everything in `/data` stays.
Flashing the package again restores them — **without Format Data**:

1. Copy the package to `/sdcard` (or use a USB stick) and enter recovery.
2. Install the package.
3. Reboot straight to the system. Do not wipe anything.

The first boot afterwards is slow while Android rebuilds caches for the newly added
system packages; allow several minutes before assuming something has gone wrong.

Verified on this release: Play Store and Play Services come back as system packages with
their updates intact, neither crashes, and Play updates itself normally. The Google
Services Framework identifier is stored in `/data` and is therefore unchanged, so a
device previously registered at
[google.com/android/uncertified](https://www.google.com/android/uncertified/) stays
registered.

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
- **Radxa Display 8HD, alternate touch address** (`android-dsi8hd-alt`) — identical
  except that the GT911 touch controller is declared at I²C address `0x5D` instead of
  `0x14`. **Try this if the panel lights up but touch does not respond.** The controller
  selects its address from the INT pin level during reset and the driver does not probe
  both. Serial logging is enabled in this entry, so a UART adapter will show the driver's
  probe messages. Neither address has been confirmed on a physical panel; please report
  which one works.
- **Radxa Display 10FHD** (`android-dsi10fhd`) — a boot entry is present, but the panel
  driver is not in this kernel, so the panel may not initialise.

There is also a display-mode example unrelated to DSI:

- **`android-120hz`** — drives HDMI at 1280×768 @ 120 Hz instead of the display's
  preferred mode, using `androidboot.hwc.force_mode=WxH@R` on the kernel command line.
  Use it as a template for a screen whose preferred mode is not the one you want. Only
  modes the connected display actually reports can be selected, so a wrong value falls
  back to the preferred mode rather than blanking the screen. Android caps refresh rate
  separately; to exceed 60 Hz also run
  `settings put system peak_refresh_rate <N>`.
  Note that HDMI-to-MIPI bridges which scale (for example Macrosilicon MS1861) drive
  their panel at a fixed internal rate — the pipeline will report the requested rate
  while the panel shows no difference, so verify before keeping a lower resolution.

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
