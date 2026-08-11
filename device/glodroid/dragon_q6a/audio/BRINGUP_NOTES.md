# Dragon Q6A — audio/HDMI bring-up (working doc, 2026-06-20)

## Root cause (diagnosed live via adb 2026-06-20)
No ALSA card at all (`/proc/asound`, `/dev/snd` absent). The whole audio + ADSP
stack is modular (`=m`) and NONE of it is in the ramdisk; ADSP firmware was also
missing. So tinyhal's `audio.primary.dragon_q6a` fails to load (no card to open)
-> AudioFlinger has no primary output -> "audio output not available" + system
lag (audioserver/apps spin-retry the missing output).

HDMI/DP audio IS wired in the DTB: sndcard `qcom,qcs6490-rb3gen2-sndcard`, dai-link
**`dp0-dai-link "DP0 Playback"`** (codec = DP ctrl hdmi-codec phandle 0x165, cpu =
q6apm-lpass-dais 0x166 port 0x68, platform = q6apm-dai). Path = AudioReach/APM
(GPR), NOT legacy APR (no q6afe/q6asm). GPR/APR transport is built-in
(CONFIG_QCOM_APR=y). Also a WCD analog playback dai + a capture dai.

## DONE (offline, in tree)
- Firmware extracted from Radxa OS rootfs (/lib/firmware) -> device tree
  `firmware/qcom/qcs6490/radxa/dragon-q6a/`: adsp.mbn, cdsp.mbn,
  QCS6490-Radxa-Dragon-Q6A-tplg.bin (AudioReach topology), adspr.jsn, adspua.jsn,
  cdspr.jsn. Wired into device.mk PRODUCT_COPY_FILES -> /vendor/firmware/...
  (firmware_class.path=/vendor/firmware already on cmdline).

## TO DO (needs board / adb — start when jersz is back)
### 1. Modules into /vendor (NOT first-stage ramdisk)
Load LATE, after /vendor is mounted, to avoid the firmware-timing trap: if
qcom_q6v5_pas autoboots the ADSP during first-stage init (before /vendor mount),
the adsp.mbn request fails and the DSP never comes up. So: stage modules in
/vendor/lib/modules + modprobe them from a vendor init .rc once /vendor is up.
Source = prebuilts-radxa/modules.tar.gz (6.18.2-4-qcom), decompress .ko.zst.

modprobe leaf targets (deps auto-resolved by modules.dep; order below is safe):
```
# remoteproc / ADSP (pulls qcom_q6v5, qcom_common, qcom_sysmon, qcom_pil_info, qcom_glink_smem)
modprobe qcom_q6v5_pas
modprobe qcom_pd_mapper          # protection-domain mapper for "avs/audio"
# pinctrl for LPASS lpi (pulls pinctrl-lpass-lpi)
modprobe pinctrl-sc7280-lpass-lpi
# codec + soundwire (pulls wcd938x-sdw, mbhc, wcd-common, wcd-classh, regmap-sdw, soundwire-bus, snd-soc-core...)
modprobe snd-soc-wcd938x
# LPASS macros (pull lpass-macro-common)
modprobe snd-soc-lpass-wsa-macro snd-soc-lpass-va-macro snd-soc-lpass-rx-macro snd-soc-lpass-tx-macro
# QDSP6 APM (pull snd-q6apm, snd-q6dsp-common)
modprobe q6apm-dai
modprobe q6apm-lpass-dais
modprobe q6prm-clocks            # pulls q6prm
# DP/HDMI codec helper (may be optional if DP ctrl registers its own hdmi-codec)
modprobe snd-soc-lpass-hdmi
# MACHINE driver — creates the card, binds dp0/wcd dai-links  ** LAST **
modprobe snd-soc-sc7280
```
NOTE: do NOT need q6afe/q6asm/q6adm/q6routing/q6core (legacy APR path).

### 2. Verify card came up (board)
`cat /proc/asound/cards` (expect a card; model "QCS6490-Radxa-Dragon-Q6A"),
`cat /proc/asound/pcm` -> note the card# and the device# of **"DP0 Playback"**,
`cat /sys/class/remoteproc/*/state` (adsp should be "running"),
`dmesg | grep -iE 'adsp|q6apm|sndcard|asoc|remoteproc'`.
If card missing -> read dmesg for EPROBE_DEFER / missing-dai / pd_mapper / firmware
load errors and iterate (likely a missing modprobe or load-order tweak).

### 3. tinyhal config /vendor/etc/audio.dragon_q6a.xml
tinyhal loads /vendor/etc/audio.dragon_q6a.xml (ETC_PATH=/vendor/etc, key=ro.product.device).
Without it adev_open returns -ENOENT and the HAL never loads. Template =
device/glodroid/rpi4/audio.rpi4.xml. Fill cardname + DP0 device index from step 2.
Draft (FINALIZE device= after /proc/asound/pcm):
```xml
<audiohal>
    <stream type="pcm" dir="out" cardname="QCS6490DragonQ6A" device="DP0_DEV#"
            rate="48000" period_size="1024"></stream>
    <stream type="pcm" dir="in" cardname="Dummy" device="0" rate="48000"></stream>
</audiohal>
```
Add PRODUCT_COPY_FILES line in device.mk:
`$(LOCAL_PATH)/audio/audio.dragon_q6a.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio.dragon_q6a.xml`

### 4. Build + deploy + verify
Rebuild vendor/super (+ the module-install + rc), `dd super.img -> /dev/sde12`.
Pure vendor/super change — no ramdisk surgery. Verify: card+PCM exist, tinyhal
loads (logcat: no "Failed to open config"), AudioFlinger primary output present,
**lag GONE**, SmartTube/Plex stop erroring. Fold into Recovery+GApps rebuild.

### Testing caveat
jersz's WaveShare 1024x600 HDMI panel has NO speakers -> can't verify HDMI audio
by ear. Verify card/HAL/lag-gone on-device; audible HDMI test needs the Discord
member's HDMI-audio TV (or analog WCD jack if the board exposes one).
