Radxa MIPI-DSI displays (Display 8HD / 10FHD) on Dragon Q6A
===========================================================

By default this image boots to HDMI instantly (loader.conf: timeout 0).
The MIPI-DSI panels are OPT-IN so HDMI users are never slowed down.

If you have a Radxa Display 8HD (or 10FHD) connected to the MIPI-DSI FPC:

  1. Mount this ESP/boot partition (the small FAT partition, "ESP") on any PC.
  2. Edit  loader/loader.conf  and change ONLY the default line:

        timeout 0
        default android-dsi8hd            <-- was: android   (NOTE: no ".conf" suffix!
                                             the loader matches the entry name with .conf
                                             stripped. Use android-dsi10fhd for the 10" FHD)

  3. Save, put the card back, boot. It now boots the DSI panel instantly and
     persistently. To go back to HDMI, set  default android  again.

This mirrors Radxa's rsetup overlay model: a display is a persistent hardware
choice, set once — not a per-boot menu (which would cost every user a delay).

Notes
-----
- Recovery (TWRP) is reached via BCB, not a menu:  adb reboot recovery.
- 8HD is fully driver-supported (jadard JD9365DA-H3 panel + Goodix GT911 touch).
- 10FHD panel (radxa,display-10fhd-ad003) needs a panel driver not yet in this
  build; the DTB + entry are shipped so it can be finished/validated by the
  community. Please report results.
- The DSI DTBs were merged 1:1 from Radxa's official Q6A overlays and validated
  structurally (fdtoverlay), but NOT yet confirmed on physical panels.

Extra entries in this build (select the same way: edit loader.conf "default")
----------------------------------------------------------------------------
android-dsi8hd-alt   8HD panel, but the Goodix GT911 touch controller is
                     declared at I2C address 0x5D instead of 0x14.
                     TRY THIS IF: the 8HD panel lights up but TOUCH DOES NOT
                     WORK. GT911 picks its address from the INT pin level during
                     reset, and the mainline driver does not probe both. The DTB
                     differs from the normal one by exactly two lines
                     (touchscreen@14 -> @5d, reg 0x14 -> 0x5d); everything else
                     is byte-identical. UART logging is on in this entry, so a
                     serial adapter will show the driver's probe messages.
                     If touch still fails, the address is NOT the cause — the
                     next suspect is touch power: the driver logs "Failed to get
                     AVDD28 regulator" / "VDDIO" and our DT declares neither.
                     Please report either result.

android-120hz        HDMI at 1280x768@120 instead of the display's preferred
                     mode, via the new androidboot.hwc.force_mode=WxH@R option
                     (drm_hwcomposer otherwise always takes the EDID-preferred
                     mode; the kernel's video= parameter does NOT work here).
                     Use it as a template for any non-standard screen: only
                     modes the connector itself reports can be selected, so a
                     wrong value falls back to the preferred mode rather than
                     blanking the display.
                     NOTE: Android separately caps refresh at 60 Hz. To actually
                     get more you also need:
                         settings put system peak_refresh_rate 120
                     MEASURED WARNING: with an HDMI->MIPI bridge that scales
                     (e.g. Macrosilicon MS1861), the pipeline really does run at
                     120 Hz but the panel shows no difference — such bridges
                     drive the panel at their own fixed rate. There you only
                     lose resolution. Verify with an A/B test before keeping it.
