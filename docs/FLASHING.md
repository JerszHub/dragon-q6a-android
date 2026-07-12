# Flashing the SD card

This image boots the Radxa Dragon Q6A entirely from a microSD card. The onboard
SPI firmware (Qualcomm XBL/UEFI) and any eMMC are left untouched, so flashing is
non-destructive to the board and fully reversible — just re-flash or swap the card.

- **Card size:** 8 GB minimum; 16 GB or larger recommended (the data partition is
  grown to fill the card).
- **What you need:** the release asset `dragon_q6a_universal_gapps-ready.img.zst` and a card
  reader.

---

## Option A — graphical (any OS, easiest)

[balenaEtcher](https://etcher.balena.io/) and the Raspberry Pi Imager both read
`.zst` directly:

1. Select `dragon_q6a_universal_gapps-ready.img.zst`.
2. Select your SD card.
3. Flash.

That is all the image itself needs to boot. To use the full card capacity for apps
and data, optionally grow the data partition afterwards (see *Grow the data
partition* below); otherwise the system still boots on the as-flashed layout.

---

## Option B — command line (Linux / WSL2 / macOS)

> ⚠️ `dd` writes to a raw block device. **Triple-check the target** — writing to the
> wrong disk destroys it. On Linux/WSL2 use `lsblk` to confirm the card is, e.g.,
> a removable ~239 GB "Storage Device"; on macOS use `diskutil list`.

### 1. Identify the card

```bash
lsblk -do NAME,SIZE,RM,TYPE,MODEL     # the card is the removable (RM=1) device, e.g. /dev/sdX
```

### 2. Wipe the old partition table (recommended)

Clearing any previous GPT — including the **backup GPT** at the end of the card —
avoids a stale partition table that some firmware complains about:

```bash
sudo sgdisk --zap-all /dev/sdX
sudo wipefs -a /dev/sdX
```

### 3. Decompress and write the image

```bash
zstd -d dragon_q6a_universal_gapps-ready.img.zst -o dragon_q6a_universal_gapps-ready.img
sudo dd if=dragon_q6a_universal_gapps-ready.img of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

You can also stream it without keeping the decompressed copy on disk:

```bash
zstd -dc dragon_q6a_universal_gapps-ready.img.zst | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

### 4. (Recommended) Grow the data partition

The image ships a small `userdata` partition. To use the whole card, move the
backup GPT to the real end of the card and extend partition 13:

```bash
sudo sgdisk -e /dev/sdX            # relocate backup GPT to end of card
sudo growpart /dev/sdX 13          # extend userdata to fill the card
sudo partprobe /dev/sdX
```

Android formats `/data` on first boot, so no manual filesystem resize is needed.

---

## Boot it

1. Eject the card and insert it into the Q6A.
2. Power on and **be patient on the very first boot.** It formats `/data`, runs
   first-boot optimization (dexopt), and **may reboot itself once or twice and sit
   on a black screen or the boot animation for a few minutes — this is normal.**
   Subsequent boots are much faster. Only treat it as a problem if it keeps
   power-cycling for more than ~5 minutes; then capture a UART log (below).

### Optional: watch the boot over UART

Useful if a display does not light up. Connect a **1.8 V** UART adapter (e.g.
CP2102) to UART0 on the 40-pin header (GND=pin6, board-TX=pin8, board-RX=pin10),
open a serial terminal at `115200 8N1`, and power-cycle the board. Reading only the
board's TX line is enough for logging.

---

## Installing to an NVMe SSD (optional)

From the **universal** release onward the **same image boots from either the SD
card or an NVMe SSD** — the kernel cmdline lists both boot devices
(`androidboot.boot_devices=...mmc,...1c08000.pcie`) and the PCIe PHY is baked into
the ramdisk, so `nvme0n1` is ready at first-stage and `/data`/`super` mount from
whichever medium holds the partitions.

- **Slot:** onboard M.2 **M-key 2230**, **PCIe Gen3 ×2** (`1c08000.pcie`).
- Real-world sequential throughput on the reference build: **~1.0 GB/s write,
  ~0.97 GB/s read** (single-stream `dd`; bursts higher).
- The board's **UEFI boots from NVMe**, so once the image is on the SSD it is a
  fully standalone install — the SD card can be removed.

> ⚠️ Writing the image to the SSD **erases everything on it** (including any
> existing Windows/Linux install).

### Method A — USB→M.2 adapter on a PC (recommended)

If you have a USB→M.2 (NVMe) enclosure/adapter, this is identical to flashing an SD
card: plug the SSD into the PC and follow **Option B** above, using the NVMe's
block device as the target (and `sgdisk -e` + `growpart <dev> 13` to grow `/data`
to the full SSD). Then move the SSD into the board's M.2 slot.

### Method B — no adapter, from a board already running this image

You can clone the running image straight onto the SSD from the board itself:

1. Flash the image to an **SD card** (Options A/B above) and boot the board once
   with the **NVMe seated in the M.2 slot**.
2. From a PC on the same network, over `adb` (TCP, `:5555`), stream the image onto
   the SSD:

   ```bash
   adb root
   zstd -dc dragon_q6a_universal_gapps-ready.img.zst \
     | adb shell 'dd of=/dev/block/nvme0n1 bs=4M conv=fsync'
   ```

3. **Grow `/data` to the full SSD.** The on-device `sgdisk` is limited, so the
   simplest path is to grow the partition table later from a PC with a USB→M.2
   adapter (`sgdisk -e` + `growpart … 13`). Without that step the install still
   boots fine — `/data` just uses the as-flashed size until grown.
4. Power off, **remove the SD card**, power on. The board's UEFI falls back to the
   NVMe ESP and boots Android straight from the SSD. (With both an SD and an
   NVMe install present, pick the boot device from the UEFI/systemd-boot menu.)

---

## Adding Google Apps (Play Store / GMS) via TWRP

The image ships **vanilla** (no Google apps baked in) — redistributing Google's
proprietary GMS is not permitted without a license. Instead, the image includes a
**TWRP recovery** so you can flash [MindTheGapps](https://github.com/MindTheGapps)
yourself for private use. This build is prepared for it: dm-verity is disabled, the
`super` sub-partitions are writable with free space, and TWRP handles the dynamic
(A/B) partitions.

**You need:**
- `MindTheGapps-13.0.0-arm64-*.zip` on a **USB stick** (FAT/exFAT/NTFS all work).
- A **USB keyboard + mouse** — the recovery UI is navigated with a mouse cursor
  (the HDMI panel is not multi-touch in recovery).
- `adb` over TCP to the running device (see below) to enter recovery.

### 1. Enter TWRP recovery

The bootloader auto-boots Android, so trigger recovery from the running system. **No PC
needed** — the image ships a one-tap app:

- **Easiest — on the device:** open the **"Reboot to Recovery"** app (bundled). It
  reboots straight into TWRP.
- **From a PC over adb** (adb-over-TCP is enabled from boot on port 5555):

  ```bash
  adb connect <device-ip>:5555
  adb reboot recovery
  ```

Either way the board reboots into TWRP (one-shot via the boot-control block). Plug in
the USB stick + keyboard/mouse.

### 2. Flash MindTheGapps

In TWRP: **Install** → change storage to the **USB** volume → select the
MindTheGapps zip → swipe/confirm to flash. It should report *"… mounted"* and finish
successfully.

### 3. Reset data — use **Format Data**, not "Factory Reset"

> ⚠️ **Important:** Use **Wipe → Format Data** and **type `yes`** when prompted.
> Do **not** use the "Factory Reset" slider — it tries to *mount* `/data` to delete
> files, which fails on this device (encrypted `/data`), giving *"Factory Reset
> Failed"* / *"failed to mount /data"*. **Format Data** does a raw reformat (no mount
> needed) and is the correct step. Seeing *"Unable to mount /data"* right after the
> format is expected and harmless — Android re-initializes `/data` on next boot.

### 4. Reboot

**Reboot → System.** The first boot is **slow** (it re-encrypts `/data`, runs dexopt,
and initializes Google services) — give it several minutes. You should land on the
launcher with the **Play Store** present.

### 5. (If Play shows "device not certified")

Because the build uses AOSP test-keys it is uncertified. Register the device's Google
Services Framework ID once at
[google.com/android/uncertified](https://www.google.com/android/uncertified/):

```bash
adb shell "sqlite3 /data/data/com.google.android.gsf/databases/gservices.db \
  \"select * from main where name='android_id'\""
```

Enter that ID on the page, wait a few minutes, then reboot. (Play *Integrity* /
SafetyNet-gated apps like banking will still not pass on an unlocked test-keys build.)

---

## Radxa MIPI-DSI touchscreens (optional)

HDMI is the default output. The image also ships boot entries for Radxa's MIPI-DSI
panels, selectable by editing the ESP (FAT) partition on any PC:

- **8HD** — Radxa 8" HD (`display-8hd-ad002`) + Goodix GT911 touch — **fully supported.**
- **10FHD** — Radxa 10" FHD (`display-10fhd-ad003`) — boot entry present, but the panel
  driver is not in this kernel yet, so it may not light up.

**There is no interactive boot menu** — the bootloader is set to `timeout 0` and boots
the *default* entry straight away (this is deliberate, so it always lands in Android).
So you don't *pick* a panel at boot; you make the DSI entry the **default**.

To use a DSI panel: power off, take the SD/SSD out, and on any PC open the **`esp`
partition** (it's a normal FAT partition — mounts on Windows/Linux/macOS). Edit
`loader/loader.conf` and change the `default` line:

```
default android-dsi8hd       # Radxa 8HD  (or: android-dsi10fhd for the 10FHD)
```

(HDMI users leave it as `default android`.) Save, put the card back, boot — it now
comes up on the DSI panel. Each entry carries its own device tree; switching back to
HDMI is just changing the line back. See `loader/README-DSI.txt` on the ESP.

> Prefer a pick-at-boot menu instead? You can set e.g. `timeout 5` in the same file —
> but the menu draws on whichever display is already active at boot (HDMI) and needs a
> USB keyboard, so for a DSI-only setup editing `default` is the reliable way.

---

## USB Wi-Fi adapters (optional)

Drivers and firmware for the common USB Wi-Fi chips are baked in and load at boot, so a
dongle is detected plug-and-play:

- **Realtek** — rtw88 (8811/8812/8821/8822) and rtl8xxxu (8188/8192/8723)
- **MediaTek** — mt76 (7601, 76x0, 7921, 7925)
- **Broadcom** — brcmfmac

**Interface note:** Android's Wi-Fi settings use the **primary** interface (`wlan0` =
the onboard AIC8800). If the onboard Wi-Fi works, a dongle enumerates as `wlan1` and the
Settings UI does not switch to it automatically. If your onboard Wi-Fi is **dead**, the
dongle typically takes `wlan0` and works in the UI with no extra steps.

---

## Troubleshooting

- **No picture on an HDMI monitor** — the image is universal and reads the
  display's EDID. If a particular panel ships a bad/empty EDID, you can supply one:
  put the EDID blob at `Android/edid/<name>.bin` on the ESP (FAT) partition and add
  `drm.edid_firmware=HDMI-A-1:edid/<name>.bin` to the `options` line in
  `loader/entries/android.conf`.
- **Touch acts like a mouse** — the device tree's IDC maps known USB touch panels
  to a touchscreen. For an unlisted panel, add an IDC keyed to its USB VID/PID.
- **Board reboots before any UI** — capture the UART log; a first-stage init abort
  (e.g. an unresolved kernel module) restarts the board before the kernel reaches
  the UI. The log names the failing module/service.
