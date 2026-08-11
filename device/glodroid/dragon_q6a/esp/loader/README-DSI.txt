Radxa MIPI-DSI displays on the Dragon Q6A
=========================================

This image boots to HDMI by default. MIPI-DSI panels are opt-in, selected by
making their boot entry the default.

There is no interactive boot menu: the loader is configured with "timeout 0" and
boots the default entry immediately.

Selecting a panel
-----------------

  1. Power off and mount this ESP partition (the small FAT partition) on a computer.
  2. Edit loader/loader.conf and change only the "default" line:

        timeout 0
        default android-dsi8hd

     Use android-dsi10fhd for the 10" FHD panel. Entry names are matched with the
     ".conf" suffix stripped, so the value must not include it.

  3. Save, reinsert the card and boot. To return to HDMI, set "default android".

Available entries
-----------------

  android                 HDMI (default), quiet console
  android-dsi8hd          Radxa Display 8HD
  android-dsi8hd-debug    Radxa Display 8HD, verbose serial console
  android-dsi10fhd        Radxa Display 10FHD
  twrp                    TWRP recovery

Panel support
-------------

  Display 8HD  — Jadard JD9365DA-H3 panel and Goodix GT911 touch drivers are
                 included. DSI support is experimental.
  Display 10FHD — the panel driver (radxa,display-10fhd-ad003) is not present in
                 this kernel. The device tree and entry are shipped so the panel
                 can be brought up, but it may not initialise as-is.

The DSI device trees are derived from Radxa's overlays for this board and were
validated structurally with fdtoverlay.

Recovery is entered through the Android boot control block rather than this menu:
use "adb reboot recovery" or the bundled Reboot to Recovery application.
