#!/bin/bash
#
# Applies the out-of-tree patches to a GloDroid (Android 13) checkout.
#
#   scripts/apply-patches.sh /path/to/glodroid
#
# Three fixes in this port change files owned by GloDroid or AOSP rather than by
# the device tree, so they ship as patches. See patches/README.md for what each
# one does and why it cannot live in device/glodroid/dragon_q6a/.
#
# The script is safe to re-run: a patch that is already applied is reported and
# skipped rather than applied twice.

set -u

TREE=${1:-}
if [ -z "$TREE" ] || [ ! -d "$TREE" ]; then
    echo "usage: $0 <path-to-glodroid-tree>" >&2
    exit 1
fi

HERE=$(cd "$(dirname "$0")/.." && pwd)
PATCHES=$HERE/patches

# apply <patch-file> <dir> [alternative dir ...]
#
# A patch applies inside the project that owns the file, not at the tree root,
# because the diffs are relative to that project. GloDroid keeps its own forks
# under glodroid/, so drm_hwcomposer may be at either glodroid/vendor/... or
# vendor/... depending on how the tree was synced — hence the alternatives.
apply() {
    local file=$1; shift
    local path="$PATCHES/$file"
    [ -f "$path" ] || { echo "  MISSING  $file"; return 1; }

    local dir="" candidate
    for candidate in "$@"; do
        if [ -d "$TREE/$candidate" ]; then dir=$candidate; break; fi
    done
    if [ -z "$dir" ]; then
        echo "  NO DIR   $* (skipping $file)"
        return 1
    fi
    local target="$TREE/$dir"

    if git -C "$target" apply --check --reverse "$path" 2>/dev/null; then
        echo "  ALREADY  $file"
        return 0
    fi
    if git -C "$target" apply --check "$path" 2>/dev/null; then
        git -C "$target" apply "$path" && echo "  APPLIED  $file"
        return 0
    fi
    echo "  FAILED   $file — does not apply cleanly in $dir"
    return 1
}

echo "Applying out-of-tree patches to $TREE"
RC=0
apply 0001-audio-policy-attach-aux-digital.patch  .                    || RC=1
apply 0002-wired-accessory-handle-all-switch-combinations.patch  frameworks/base || RC=1
apply 0003-drm-hwcomposer-force-display-mode.patch \
      glodroid/vendor/drm_hwcomposer vendor/drm_hwcomposer external/drm_hwcomposer || RC=1

echo
if [ $RC -eq 0 ]; then
    echo "All patches are in place."
else
    echo "One or more patches did not apply. See patches/README.md — each is small"
    echo "enough to port by hand if the tree has moved on."
fi
exit $RC
