# SPDX-License-Identifier: Apache-2.0
#
# Device makefile for Radxa Dragon Q6A

# Q6A has no camera HAL. The default GloDroid camera-provider crashes in a loop
# (camera: "Could not load camera HAL module: -2" + "must be in VINTF manifest"),
# which trips system_server RescueParty -> reboot,recovery before boot completes.
# This flag must ALSO be set here (PRODUCT config) BEFORE inheriting
# device-common.mk, or its gate still pulls the HAL PRODUCT_PACKAGES in.
GD_NO_DEFAULT_CAMERA := true
# No modem on this board. GD_NO_DEFAULT_MODEM was set in BoardConfig (board side) but was
# MISSING here (product side), so device-common.mk still inherited modem/device.mk -> the
# ModemManager stack + modem_manager.rc shipped, and its `on boot: wait system_bus_socket`
# TIMED OUT 5s every boot (dbus-daemon fails with no modem). Setting it here drops the whole
# telephony/ModemManager stack -> -5s boot + less bloat. (Board side already gates on it.)
GD_NO_DEFAULT_MODEM := true

# Bluetooth IS enabled. It was previously disabled because com.android.bluetooth
# abort-looped on timer_create(CLOCK_BOOTTIME_ALARM)/SCHED_FIFO EPERM caused by
# CONFIG_RT_GROUP_SCHED=y in the prebuilt kernel -> RescueParty reboot. That mine
# is now disarmed by rt_group_sched=0 on the kernel cmdline (v35+). The AIC8800D80
# BT is a standard USB transport (iface e0/01/01); bluetooth.ko + aic_btusb_usb.ko
# in the ramdisk bring up hci0 (BD_ADDR confirmed live via HCIDEVUP), and GloDroid's
# btlinux HAL (android.hardware.bluetooth@1.1-service.btlinux) drives it.

$(call inherit-product, device/glodroid/common/device-common.mk)

# GPU firmware — Adreno 643 (a660 family)
# The msm/adreno driver requests sqe+gmu as "qcom/a660_*.{fw,bin}" (NO soc subdir,
# uncompressed); only the zap shader is referenced via DTB firmware-name
# "qcom/qcs6490/a660_zap.mbn". Installing sqe/gmu under qcs6490/ (and sqe only as
# .zst) made the kernel fail with -2 (ENOENT) -> GPU never inits -> SF crash loop.
# Pair this with firmware_class.path=/vendor/firmware on the kernel cmdline.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/firmware/a660_sqe.fw:$(TARGET_COPY_OUT_VENDOR)/firmware/qcom/a660_sqe.fw \
    $(LOCAL_PATH)/firmware/a660_gmu.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/qcom/a660_gmu.bin \
    $(LOCAL_PATH)/firmware/a660_zap.mbn:$(TARGET_COPY_OUT_VENDOR)/firmware/qcom/qcs6490/a660_zap.mbn \

# ADSP audio firmware — the whole audio path (HDMI/DP "DP0 Playback" + analog WCD)
# runs on the ADSP via the q6apm/AudioReach stack. remoteproc@3700000
# (qcom,sc7280-adsp-pas) requests firmware-name "qcom/qcs6490/radxa/dragon-q6a/
# adsp.mbn"; with firmware_class.path=/vendor/firmware the kernel looks under
# /vendor/firmware/. Without adsp.mbn the ADSP never boots -> no ALSA card at all
# -> tinyhal primary HAL fails to load -> "audio output not available" + system
# lag (audioserver/apps spin-retry the missing output). The tplg.bin is the
# AudioReach topology for this card (model "QCS6490-Radxa-Dragon-Q6A"); the *.jsn
# describe the audio protection-domains (avs/audio) for qcom_pd_mapper. Pulled from
# Radxa OS rootfs /lib/firmware. cdsp.mbn is the NPU (not audio) — copied for
# completeness since the DTB also references it.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/firmware/qcom/qcs6490/radxa/dragon-q6a/adsp.mbn:$(TARGET_COPY_OUT_VENDOR)/firmware/qcom/qcs6490/radxa/dragon-q6a/adsp.mbn \
    $(LOCAL_PATH)/firmware/qcom/qcs6490/radxa/dragon-q6a/cdsp.mbn:$(TARGET_COPY_OUT_VENDOR)/firmware/qcom/qcs6490/radxa/dragon-q6a/cdsp.mbn \
    $(LOCAL_PATH)/firmware/qcom/qcs6490/radxa/dragon-q6a/QCS6490-Radxa-Dragon-Q6A-tplg.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/qcom/qcs6490/radxa/dragon-q6a/QCS6490-Radxa-Dragon-Q6A-tplg.bin \
    $(LOCAL_PATH)/firmware/qcom/qcs6490/radxa/dragon-q6a/adspr.jsn:$(TARGET_COPY_OUT_VENDOR)/firmware/qcom/qcs6490/radxa/dragon-q6a/adspr.jsn \
    $(LOCAL_PATH)/firmware/qcom/qcs6490/radxa/dragon-q6a/adspua.jsn:$(TARGET_COPY_OUT_VENDOR)/firmware/qcom/qcs6490/radxa/dragon-q6a/adspua.jsn \
    $(LOCAL_PATH)/firmware/qcom/qcs6490/radxa/dragon-q6a/cdspr.jsn:$(TARGET_COPY_OUT_VENDOR)/firmware/qcom/qcs6490/radxa/dragon-q6a/cdspr.jsn \

# --- Audio (HDMI/DP + analog WCD) — full LPASS/AudioReach bring-up, solved live
# 2026-06-20 (see audio/BRINGUP_NOTES.md). dragon_q6a uses a prebuilt kernel with
# hand-baked ramdisk modules, NOT the buildtime vendor_dlkm path, so the audio module
# stack is PRODUCT_COPY'd to /vendor/lib/modules and insmod'd by audio-modules.rc on
# 'post-fs' (AFTER /vendor mounts, so adsp.mbn in /vendor/firmware is reachable when
# qcom_q6v5_pas boots the ADSP).
# (1) the 44-module dependency closure (snd-soc-sc8280xp machine + ADSP remoteproc +
#     q6apm/q6prm + LPASS macros/clocks + wcd938x + soundwire-qcom/slimbus + hdmi-codec
#     + qrtr-smd). Prebuilts from Radxa OS modules.tar.gz 6.18.2-4-qcom.
#     /vendor/lib/modules is a symlink to /vendor_dlkm/lib/modules (BOARD_USES_VENDOR_
#     DLKMIMAGE), so we ship them in a plain real dir /vendor/lib/audio-modules/ and
#     insmod by full path from audio-modules.rc (no depmod/modprobe needed).
PRODUCT_COPY_FILES += $(foreach m,$(wildcard $(LOCAL_PATH)/modules/audio/*.ko),\
    $(m):$(TARGET_COPY_OUT_VENDOR)/lib/audio-modules/$(notdir $(m)))
# (2) the load sequence (init.rc), the tinyhal config, and the AudioReach topology at
#     the path q6apm actually requests it: qcom/qcs6490/ (NOT the radxa/dragon-q6a/
#     subdir) — without this copy the card fails to instantiate with -2.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/audio/audio-modules.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/audio-modules.rc \
    $(LOCAL_PATH)/audio/audio.dragon_q6a.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio.dragon_q6a.xml \
    $(LOCAL_PATH)/firmware/qcom/qcs6490/radxa/dragon-q6a/QCS6490-Radxa-Dragon-Q6A-tplg.bin:$(TARGET_COPY_OUT_VENDOR)/firmware/qcom/qcs6490/QCS6490-Radxa-Dragon-Q6A-tplg.bin \

# --- USB plug-and-play modules (2026-07-08) — pendrive/mass-storage + USB-WiFi adapters.
# Same hand-baked pattern as audio (prebuilt kernel, /vendor/lib/modules is a symlink to
# vendor_dlkm, so ship in a plain real dir + insmod by full path — no depmod/modprobe).
# Load order in usb-modules.rc is dependency-topological, VALIDATED LIVE 2026-07-08 (two
# real adapters + a pendrive: usb-storage/uas + vfat/exfat/ntfs3, and rtw88/rtl8xxxu/mt76/
# brcmfmac via mac80211+cfg80211+libarc4). Drivers sit idle until a matching USB device is
# plugged -> true hotplug. See device/.../modules/usb + memory project_usb_modules.
PRODUCT_COPY_FILES += $(foreach m,$(wildcard $(LOCAL_PATH)/modules/usb/*.ko),\
    $(m):$(TARGET_COPY_OUT_VENDOR)/lib/usb-modules/$(notdir $(m)))
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/modules/usb-modules.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/usb-modules.rc
# rtw88 firmware for the common Realtek USB-WiFi chips (8822b/bu, 8822c, 8821a=8811au/8821au,
# 8821c=8811cu/8821cu, 8723d, 8814a, 8812a=8812au). firmware_class.path=/vendor/firmware -> /vendor/firmware/rtw88/.
PRODUCT_COPY_FILES += $(foreach f,$(wildcard $(LOCAL_PATH)/firmware/rtw88/*.bin),\
    $(f):$(TARGET_COPY_OUT_VENDOR)/firmware/rtw88/$(notdir $(f)))
# 2026-07-29: firmware for ALL other plug-and-play USB-WiFi chip families, so every supported
# dongle works out of the box (no more "adapter seen but no wlanX" / manual firmware push).
#   rtlwifi/  -> rtl8xxxu (8188EUS/CUS/FU, 8192CU/EU/FU, 8710BU, 8723AU/BU) e.g. TL-WN725N
#   mediatek/ + root mt7601u/mt7662* -> mt76 (7601u, 761x, 766x, 7921/MT7961, 7925)
#   brcm/     -> brcmfmac USB chips (43143, 43236b, 43242a, 43569, 4373)
# Staged under firmware/wifi/ mirroring /vendor/firmware/; the wildcard covers root + 2 subdir
# depths (mediatek/mt7925 is the deepest). Blobs sourced 1:1 from upstream linux-firmware.
wifi_fw_files := \
    $(wildcard $(LOCAL_PATH)/firmware/wifi/*.bin) \
    $(wildcard $(LOCAL_PATH)/firmware/wifi/*/*.bin) \
    $(wildcard $(LOCAL_PATH)/firmware/wifi/*/*/*.bin)
PRODUCT_COPY_FILES += $(foreach f,$(wifi_fw_files),\
    $(f):$(TARGET_COPY_OUT_VENDOR)/firmware/$(patsubst $(LOCAL_PATH)/firmware/wifi/%,%,$(f)))

# Vulkan — Turnip (freedreno)
PRODUCT_PACKAGES += \
    vulkan.freedreno

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.vulkan.level-0.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.vulkan.level.xml \
    frameworks/native/data/etc/android.hardware.vulkan.version-1_1.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.vulkan.version.xml \
    frameworks/native/data/etc/android.software.vulkan.deqp.level-2022-03-01.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.software.vulkan.deqp.level.xml \

PRODUCT_VENDOR_PROPERTIES += \
    ro.hardware.vulkan=freedreno \

# Touch + GPU feature declarations. These are STORE METADATA, not runtime gates:
# Play (and Uptodown) hide apps whose manifest has <uses-feature required="true">
# for a feature the device does not declare, even though the hardware handles them
# fine once installed. Brawl Stars and Genshin Impact were both filtered out.
#
# handheld_core_hardware.xml (in common/base) declares android.hardware.touchscreen
# but NOT faketouch — AOSP keeps that in a separate file. The jazzhand variant below
# is a superset: touchscreen + multitouch + multitouch.distinct + multitouch.jazzhand
# + faketouch, so it covers all of it in one copy. jazzhand = 5+ independent points,
# which is what the WaveShare panel does via hid-multitouch and what the DSI 8HD
# (Goodix GT911) reports.
#
# opengles.aep = the GLES 3.1 Android Extension Pack. Adreno 643 under Mesa/freedreno
# supports it, but nothing declared it.
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.jazzhand.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.touchscreen.multitouch.jazzhand.xml \
    frameworks/native/data/etc/android.hardware.opengles.aep.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.opengles.aep.xml \

# OpenGL ES 3.2 (Freedreno/Turnip). 196610 = 0x30002.
# Was 196609 (3.1), which understated the driver: SurfaceFlinger reports
# "freedreno, Adreno 7c+ Gen 3, OpenGL ES 3.2 Mesa 23.0.0-devel" (verified on
# hardware 2026-08-11). Play filters on reqGlEsVersion, so under-declaring hid
# games that require 3.2.
PRODUCT_VENDOR_PROPERTIES += \
    ro.opengles.version=196610

# Shared memory: force memfd for libcutils/FMQ.
# The prebuilt RadxaOS kernel 6.18.2-4-qcom is a mainline build with NO
# CONFIG_ASHMEM (ashmem was dropped from mainline in 5.18). libcutils defaults
# sys.use_memfd=false, which makes it fall back to /dev/ashmem; that device does
# not exist here, so every FMQ ring-buffer allocation fails (mmap -> mReadPtr
# null) and libfmq aborts. That killed SurfaceFlinger's HIDL composer, the audio
# HAL and the BT audio HAL -> reboot loop. Kernel has CONFIG_MEMFD_CREATE=y and
# ro.vndk.version=33 (>=Q) so the memfd path is allowed once this is true.
PRODUCT_VENDOR_PROPERTIES += \
    sys.use_memfd=true

# Display density = 170. This is the NAVIGATION lever, not a cosmetic tweak.
# At 160 the 1024x600 panel computes sw600dp => Android treats it as a TABLET, and
# on tablets the *navigation* affordance is the Launcher taskbar (SystemUI draws no
# 3-button bar). At 170 the panel is sw516dp => PHONE => SystemUI draws a real
# NavigationBar0 (back/home/recents) — verified live on HW. On a large external
# monitor the same 170 keeps it a tablet => taskbar reappears => still navigable.
# So 170 (NOT force_phone) gives navigation on every screen size.
GD_LCD_DENSITY := 170

# NOTE: ro.launcher.force_phone REMOVED. It suppressed the Launcher3 taskbar but on
# a tablet-class screen that left ZERO navigation (no taskbar AND no nav bar). The
# Launcher3 DisplayController.isTablet() patch stays in tree but is now inert (prop
# unset). At density 170 the small panel is already phone form-factor (no taskbar,
# nav bar instead), so the taskbar-overlap problem it solved no longer occurs.

# Device framework-res overlay (squircle icon mask, baked default wallpaper).
PRODUCT_PACKAGE_OVERLAYS += device/glodroid/dragon_q6a/overlay

# Ethernet — RTL8111K/r8169 is primary network
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.ethernet.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.ethernet.xml \

# Disable suspend — no battery, always-on SBC
PRODUCT_COPY_FILES += \
    device/glodroid/common/no_suspend.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/no_suspend.dragon_q6a.rc \

# Touchscreen IDC — the WaveShare WS170120 USB panel (Vendor 0eef Product 0005)
# reports ABS_X/ABS_Y + BTN_TOUCH but no INPUT_PROP_DIRECT, so Android defaults it
# to POINTER mode (a mouse cursor that cannot tap). This IDC forces
# touch.deviceType=touchScreen -> DIRECT mode, real absolute touch.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/idc/Vendor_0eef_Product_0005.idc:$(TARGET_COPY_OUT_VENDOR)/usr/idc/Vendor_0eef_Product_0005.idc \

# adb over TCP — the only adb path on this board: both USB controllers are
# host-only (no peripheral/gadget mode), so adb-by-cable is physically
# impossible. adbd listens on :5555 once a network (WiFi) is up.
PRODUCT_SYSTEM_PROPERTIES += \
    service.adb.tcp.port=5555

# --- UI / cosmetic bring-up (2026-06-14) ---

# Lawnchair = default launcher, baked as a non-privileged system app in /product.
# Launcher3QuickStep stays installed as the recents/overview provider
# (config_recentsComponentName); Lawnchair 14 has no A13 QuickStep build, so it
# provides HOME only. The HOME role is seeded once at boot by the .rc below
# (no clean static-overlay path for the HOME role default holder in A13).
PRODUCT_PACKAGES += \
    Lawnchair

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/lawnchair-default-home.rc:$(TARGET_COPY_OUT_VENDOR)/etc/init/lawnchair-default-home.rc \

# Health HAL — the Q6A is a wall-powered SBC with no battery, so the stock
# example service reports 0%. This service subclasses it to report full AC power
# and `overrides` the example (single IHealth/default instance).
PRODUCT_PACKAGES += \
    android.hardware.health-service.dragon_q6a

# Orientation base policy — ignore app orientation requests on the panel
# (uniqueId local:0) so apps can't hijack rotation; the user picks rotation from
# the on-screen control (no accelerometer on this board → manual, not auto).
# SettingsProvider defaults (user_rotation=0, accelerometer_rotation=false) are
# already correct.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/display_settings.xml:$(TARGET_COPY_OUT_VENDOR)/etc/display_settings.xml \

# ScreenRotate — built-in manual rotation control (Quick Settings tile + drawer
# app). Platform-signed so it can call IWindowManager.freezeRotation()
# (SET_ORIENTATION). Lets any user pick orientation from the UI without adb.
PRODUCT_PACKAGES += \
    ScreenRotate

# Bluetooth profiles (2026-07-09) — the Q6A shipped NO explicit BT profile config, so
# it fell back to compile-time defaults that left A2DP SOURCE off: the board couldn't
# connect to BT speakers ("connect" did nothing) and advertised itself as A2DP SINK, so
# phones saw it as "headphones". Enable the standard SOURCE-device profile set (verified
# live: A2DP Source -> Enabled, Sink -> Disabled). Mirrors what real devices (gs201) set.
PRODUCT_PRODUCT_PROPERTIES += \
    bluetooth.profile.a2dp.source.enabled?=true \
    bluetooth.profile.avrcp.target.enabled?=true \
    bluetooth.profile.gatt.enabled?=true \
    bluetooth.profile.hfp.ag.enabled?=true \
    bluetooth.profile.hid.host.enabled?=true \
    bluetooth.profile.map.server.enabled?=true \
    bluetooth.profile.opp.enabled?=true \
    bluetooth.profile.pan.nap.enabled?=true \
    bluetooth.profile.pan.panu.enabled?=true \
    bluetooth.profile.pbap.server.enabled?=true

# RebootRecovery — one-tap "Reboot to Recovery" app (com.q6a.rebootrecovery).
# Sets sys.powerctl=reboot,recovery -> patched embloader reads the Android BCB from
# misc -> boots TWRP. On-device way into recovery (no PC needed). (A power-menu
# "Recovery" option via config_showAdvancedReboot was tried but dropped — it forces a
# heavy framework-res overlay recompile and is unreliable in GlobalActionsDialogLite.)
PRODUCT_PACKAGES += \
    RebootRecovery

# WifiAdapterNotifier — surfaces plug-and-play USB Wi-Fi dongles in the UI. The onboard
# AIC8800 owns wlan0; a dongle comes up as wlan1 which stock Settings never shows. This
# persistent system app watches /sys/class/net and, on a non-aic8800 wlan iface, posts a
# notification with an "Activate" action that points the Wi-Fi STA at the dongle
# (wifi.interface) and cycles Wi-Fi — done in-process via WifiManager (no init script; the
# app is android.uid.system, platform-signed, permissive device). Pairs with the
# /vendor/firmware/{rtlwifi,mediatek,brcm,rtw88} blobs so the dongle creates an interface
# in the first place.
PRODUCT_PACKAGES += \
    WifiAdapterNotifier
