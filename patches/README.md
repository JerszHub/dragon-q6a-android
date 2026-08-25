# Out-of-tree patches

Three fixes in this port change files that belong to GloDroid or AOSP rather than to the
device tree, so they cannot be shipped as part of `device/glodroid/dragon_q6a/`. They are
kept here and applied with `scripts/apply-patches.sh <glodroid-tree>`.

A build without them still boots and has working audio at start-up, but it will lack HDMI
in the audio output list, headphone jack detection, and display mode forcing.

| Patch | Target | What it fixes |
|---|---|---|
| `0001-audio-policy-attach-aux-digital.patch` | `device/glodroid/common/audio/audio_policy_configuration.xml` | Lists `Aux Digital` as an attached device so HDMI audio is offered at all |
| `0002-wired-accessory-handle-all-switch-combinations.patch` | `frameworks/base/services/core/java/com/android/server/WiredAccessoryManager.java` | Handles all eight combinations of the three jack switches |
| `0003-drm-hwcomposer-force-display-mode.patch` | `vendor/drm_hwcomposer/hwc2_device/HwcDisplay.{h,cpp}` | Adds `hwc.force_mode`, allowing a boot entry to request a display mode |

## Why each one is needed

**0001 — HDMI audio never appears.** The audio policy only offers devices listed as
attached, or ones the framework is told about at runtime. This kernel exposes neither the
legacy `switch/hdmi_audio` uevent nor a jack event that `WiredAccessoryManager` maps to
HDMI, so nothing ever reports that an HDMI sink exists — the sink's ELD is read correctly
and the DisplayPort audio path works, but Android never learns about it. Listing
`Aux Digital` unconditionally is the smallest fix that makes the output selectable.

**0002 — the headphone jack is not detected.** The WCD938x codec's impedance-based
detection reports `SW_HEADPHONE_INSERT`, `SW_MICROPHONE_INSERT` and `SW_LINEOUT_INSERT`
simultaneously for some headsets (measured: `SwitchValues=84`, reproducible on every
insertion). Stock AOSP has cases for five of the eight possible combinations and falls
through to "nothing connected" for the rest, so those headsets were never detected. The
patch adds the three missing cases.

**0003 — the display mode cannot be chosen.** `drm_hwcomposer` always selects the mode
flagged `DRM_MODE_TYPE_PREFERRED`, and the kernel's `video=<connector>:WxH@R` parameter
does not change that flag on this board — verified: the command line is passed through and
the connector's mode list is unchanged. The patch reads `vendor.hwc.drm.force_mode` or
`ro.boot.hwc.force_mode` and selects a matching mode from those the connector reports.
Timings are never invented, so an unmatched request falls back to the preferred mode
rather than blanking the display.

## Applying and refreshing

The patches are plain unified diffs against a GloDroid Android 13 tree at the revision
this port was built from. If they no longer apply after a resync, they are small enough to
port by hand — each one is a few dozen lines and the surrounding code is quoted in the
diff context.
