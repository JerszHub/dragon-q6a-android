# Input Device Configuration for the Goodix GT911 capacitive touchscreen on the
# Radxa MIPI-DSI panels (8HD / 10FHD). The kernel driver (mainline goodix.c) names
# the input device "Goodix Capacitive TouchScreen", hence this filename.
#
# WHY THIS FILE EXISTS (2026-08-24)
# A community member got the 8HD DSI panel lighting up on our release, but touch
# did not work (a USB mouse on the same device DID work, so input in general was
# fine). We could not obtain logs from that device, so this is one of two
# no-risk shots taken blind; the other is the alternate-I2C-address boot entry
# (android-dsi8hd-alt.conf, GT911 at 0x5D instead of 0x14).
#
# Static analysis showed nothing wrong: the DT node touchscreen@14 is complete
# (compatible goodix,gt911, reset-gpios=tlmm105, irq-gpios=tlmm81, both backed by
# matching pinctrl states), the i2c@a94000 bus is status="okay", and goodix_ts.ko
# is present in the ramdisk at position 14 of modules.load with no dependencies.
# `modinfo` confirms the alias of:N*T*Cgoodix,gt911, so the driver does match.
#
# Mainline goodix.c calls input_mt_init_slots(..., INPUT_MT_DIRECT), which sets
# INPUT_PROP_DIRECT — Android SHOULD therefore classify it as a touchscreen on
# its own and this file should be redundant. It is included anyway because it
# costs nothing, cannot regress a working setup, and we hit exactly this class of
# bug before on the WaveShare USB panel (see Vendor_0eef_Product_0005.idc), where
# Android defaulted a touch device to POINTER mode.
touch.deviceType = touchScreen

# Multi-touch panel; report against the display and follow its rotation.
touch.orientationAware = 1
