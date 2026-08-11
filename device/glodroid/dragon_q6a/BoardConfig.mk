# SPDX-License-Identifier: Apache-2.0
#
# Board config for Radxa Dragon Q6A (QCS6490, UEFI boot)

# Disable subsystems not present or deferred on Q6A.
# WiFi (AIC8800D80 on USB, fullmac cfg80211) re-enabled 2026-06-11: kernel driver
# verified up to ieee80211 phy0; this gate was silently dropping wpa_supplicant
# (board.mk sets WPA_SUPPLICANT_VERSION — without it the module doesn't exist).
# Bluetooth re-enabled 2026-06-13: AIC8800D80 BT = standard USB transport, hci0
# confirmed live (HCIDEVUP ok, BD_ADDR f4:ab:5c:..); RT abort-loop disarmed via
# rt_group_sched=0 cmdline. Pulls in bluetooth/board.mk (manifest + sepolicy).
GD_NO_DEFAULT_CAMERA := true
GD_NO_DEFAULT_MODEM := true

include device/glodroid/common/board-common.mk

# Enlarge super (overrides common/base/board.mk's 1800MB). The dynamic-partition
# group is ~100% full at 1800MB; we need headroom for (a) audio kernel modules in
# vendor_dlkm (~50MB, the QCS6490 LPASS/AudioReach stack — see audio/BRINGUP_NOTES.md)
# and (b) MindTheGapps flashed later into /product via TWRP from a USB stick (TWRP
# cannot grow super itself, so the free space must exist in the group now).
# 2560MB super -> 2550MB group leaves ~1GB free after current contents + modules.
# gensdimg auto-sizes the super GPT partition from super.img, so the 8GB image still
# fits (super 2.5G + others ~0.5G + userdata fills the rest; grow-on-flash unchanged).
# NOTE: GLODROID_DYNAMIC_PARTITIONS_SIZE is computed with := from the OLD super size
# in base/board.mk, so BOTH must be overridden here (after the include).
BOARD_SUPER_PARTITION_SIZE := $(shell echo $$(( 2560 * 1024 * 1024 )))
BOARD_GLODROID_DYNAMIC_PARTITIONS_SIZE := $(shell echo $$(( $(BOARD_SUPER_PARTITION_SIZE) - (10 * 1024 * 1024) )))

# --- GApps-flashable via TWRP (2026-07-11) ---
# Disable dm-verity so a TWRP-modified /system|/product|/system_ext still boots.
# --flags 2 = AVB VERIFICATION_DISABLED on the top-level vbmeta; first-stage init's
# libavb then skips ALL hashtree/verification (incl. the chained vbmeta_system). vbmeta
# stays present so the boot chain is intact, just disarmed. (Verify: avbtool info_image
# --image vbmeta.img -> "Flags: 2".) Needed because MindTheGapps rewrites system files.
BOARD_AVB_MAKE_VBMETA_IMAGE_ARGS += --flags 2

# Reserve free space INSIDE the read-only system partitions so MindTheGapps can extract
# without any TWRP resize step (TWRP can't grow super). Group glodroid_dynamic_partitions_a
# max=2550MiB, currently ~1503MiB used -> ~1047MiB free; we claim ~700MiB, ~347MiB margin.
# MindTheGapps-13-arm64 installs mostly into /product (+ /system_ext, a little /system).
# Disable ext4 block dedup (shared_blocks). A shared_blocks ext4 is READ-ONLY at the
# kernel level (mount -o rw is refused), so MindTheGapps' `mount -o rw ... /mnt/system`
# fails ("Could not mount /mnt/system! Aborting") even though liblp attr is `none` and
# the mapper device exists. Overrides common/base/board.mk's `:= true`. Costs a little
# image size (dedup savings lost) but makes system/product/system_ext writable in TWRP.
BOARD_EXT4_SHARE_DUP_BLOCKS := false

BOARD_PRODUCTIMAGE_PARTITION_RESERVED_SIZE := 471859200      # 450 MiB
BOARD_SYSTEM_EXTIMAGE_PARTITION_RESERVED_SIZE := 157286400   # 150 MiB
BOARD_SYSTEMIMAGE_PARTITION_RESERVED_SIZE := 104857600       # 100 MiB

# Allow the prebuilt audio kernel modules (.ko = ELF) to be shipped via
# PRODUCT_COPY_FILES (device.mk audio block). AOSP normally rejects ELF in
# PRODUCT_COPY_FILES (wants cc_prebuilt_*), but these are prebuilt Radxa-kernel .ko
# loaded by audio-modules.rc at a controlled time (on post-fs, after /vendor mounts) —
# NOT the buildtime vendor_dlkm/depmod path. This downgrades that error.
BUILD_BROKEN_ELF_PREBUILT_PRODUCT_COPY_FILES := true

# Device sepolicy — labels the renamed health HAL binary as hal_health_default_exec
# so init can start it (a 'class hal' service with no domain transition is refused
# even in permissive mode).
BOARD_VENDOR_SEPOLICY_DIRS += device/glodroid/dragon_q6a/sepolicy/vendor

# GPU — Mesa Freedreno (Turnip Vulkan, Freedreno GLES)
BOARD_MESA3D_GALLIUM_DRIVERS := freedreno
BOARD_MESA3D_VULKAN_DRIVERS := freedreno

# Kernel base address — QCS6490 DRAM starts at 0x80000000
BOARD_KERNEL_BASE := 0x80000000

# Android kernel cmdline (goes into boot.img; also used as reference for systemd-boot entry).
# PRODUCTION: no serial console. Measured 2026-07-31: ~65s of a ~120s boot was spent BLOCKING
# on printk writes to console=ttyMSM0,115200 (~87us/char; 53% of log lines land in the 5-50ms
# UART-write window). Dropping the UART console (+ ignore_loglevel/loglevel=8/printk.devkmsg=on,
# see esp/loader/entries/android.conf) roughly HALVES boot. The verbose serial cmdline lives in
# esp/loader/entries/android-debug.conf for troubleshooting. console=tty0 (fbcon) is kept — it
# writes to the framebuffer, not the 115200 UART, so it is not a bottleneck.
BOARD_KERNEL_CMDLINE += loglevel=3 coherent_pool=2M
# Adreno firmware lives at /vendor/firmware/qcom/ — prebuilt kernel only searches
# /lib/firmware by default, so point the firmware loader at vendor explicitly.
BOARD_KERNEL_CMDLINE += firmware_class.path=/vendor/firmware
BOARD_KERNEL_CMDLINE += irqchip.gicv3_pseudo_nmi=0
BOARD_KERNEL_CMDLINE += selinux=1 androidboot.selinux=permissive
BOARD_KERNEL_CMDLINE += lsm=landlock,lockdown,yama,integrity,selinux,bpf

# DTB for boot.img — use our prebuilt directory
BOARD_PREBUILT_DTBIMAGE_DIR := device/glodroid/dragon_q6a/prebuilt

# Prebuilt kernel — no kernel.mk, no DTBO generation
BOARD_INCLUDE_RECOVERY_DTBO :=
BOARD_PREBUILT_DTBOIMAGE := device/glodroid/platform/kernel/dummy.dtb

# --- Reproducible first-stage kernel modules (2026-07-13, upstream prep) ---
# Replaces the hand-baked cpio post-process. The prebuilt .ko (Radxa 6.18.2-4-qcom)
# go into the vendor_ramdisk; BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD is the exact
# first-stage load order recovered from the working ramdisk + verified against live dmesg.
# (kernel.mk skips all module install for TARGET_PREBUILT_KERNEL, hence this device-local
# path.) NOTE: needs on-hardware boot validation before shipping.
# 2026-07-28: panel-jadard-jd9365da-h3.ko + goodix_ts.ko added here (were post-fs in
# usb-modules.rc = far too late). When a DSI boot entry (android-dsi8hd) enables dsi@ae94000
# + panel@0, the DSI encoder becomes a REQUIRED component of the msm DRM aggregate; if the
# panel driver isn't registered before msm binds, the aggregate never assembles -> no card0
# -> SurfaceFlinger SIGABRT-loop -> no boot (blacks out HDMI too, since one card0 drives both
# encoders). Loading the drm_panel first-stage fixes it AND lets the aggregate bind even with
# no physical DSI panel (dsi8hd then falls back gracefully to HDMI). On HDMI boots the DSI
# node is disabled so both drivers sit idle = harmless. Deps empty (DRM core =y).
# 2026-07-28 (2): also added led-class-multicolor.ko + leds-qcom-lpg.ko BEFORE the panel.
# The 8HD panel node references a pwm-backlight whose PWM provider is qcom,pm8350c-pwm =
# the leds-qcom-lpg driver (depends led-class-multicolor; led-class itself is =y). Without
# it: "pwm-backlight: unable to request PWM" -> backlight-dsi deferred -> panel-jadard
# deferred forever -> msm DRM aggregate never binds -> no card0 (same black-screen failure).
# Confirmed on UART: panel probe blocked on "supplier backlight-dsi not ready" until these load.
BOARD_VENDOR_RAMDISK_KERNEL_MODULES := $(wildcard device/glodroid/dragon_q6a/modules/vendor_ramdisk/*.ko)
BOARD_VENDOR_RAMDISK_KERNEL_MODULES_LOAD := \
    dm-mod.ko \
    dm-bufio.ko \
    dm-snapshot.ko \
    reed_solomon.ko \
    dm-verity.ko \
    loop.ko \
    quota_tree.ko \
    quota_v2.ko \
    aux-bridge.ko \
    phy-qcom-qmp-combo.ko \
    led-class-multicolor.ko \
    leds-qcom-lpg.ko \
    panel-jadard-jd9365da-h3.ko \
    goodix_ts.ko \
    phy-qcom-qmp-pcie.ko \
    fuse.ko \
    nf_socket_ipv4.ko \
    crc-ccitt.ko \
    ipv6.ko \
    nf_socket_ipv6.ko \
    x_tables.ko \
    nf_defrag_ipv6.ko \
    nf_defrag_ipv4.ko \
    xt_socket.ko \
    xt_comment.ko \
    xt_length.ko \
    xt_bpf.ko \
    ip6_tables.ko \
    ip6table_filter.ko \
    ip_tables.ko \
    iptable_filter.ko \
    ip6table_raw.ko \
    nf_conntrack.ko \
    nf_nat.ko \
    xt_nat.ko \
    ip6table_nat.ko \
    nf_reject_ipv4.ko \
    xt_state.ko \
    xt_multiport.ko \
    nf_tproxy_ipv4.ko \
    xt_hl.ko \
    xt_recent.ko \
    xt_REDIRECT.ko \
    xt_pkttype.ko \
    xt_dscp.ko \
    xt_MASQUERADE.ko \
    xt_policy.ko \
    xt_CT.ko \
    ip6table_mangle.ko \
    nf_tproxy_ipv6.ko \
    xt_TPROXY.ko \
    nf_reject_ipv6.ko \
    iptable_mangle.ko \
    xt_LOG.ko \
    xt_ecn.ko \
    xt_DSCP.ko \
    xt_conntrack.ko \
    xt_owner.ko \
    xt_string.ko \
    ip6t_REJECT.ko \
    xt_mark.ko \
    xt_IDLETIMER.ko \
    xt_u32.ko \
    xt_quota.ko \
    xt_TCPMSS.ko \
    xt_connmark.ko \
    xt_HL.ko \
    xt_tcpudp.ko \
    xt_addrtype.ko \
    ip6table_security.ko \
    iptable_raw.ko \
    ipt_REJECT.ko \
    nfnetlink.ko \
    xt_limit.ko \
    iptable_security.ko \
    iptable_nat.ko \
    xt_tcpmss.ko \
    hid-multitouch.ko \
    dwc3-qcom.ko \
    rfkill.ko \
    cfg80211.ko \
    aic_load_fw_usb.ko \
    aic8800_fdrv_usb.ko \
    bluetooth.ko \
    aic_btusb_usb.ko \
    r8169.ko
