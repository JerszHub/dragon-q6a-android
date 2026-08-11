#!/bin/bash
#
# Fetch the Lawnchair launcher APK referenced by
#   device/glodroid/dragon_q6a/apps/Lawnchair/Android.bp
#
# The binary itself is NOT committed to this repository — Lawnchair is a
# third-party GPL-3.0 application with its own trademark. This script downloads
# the exact release used by the device tree and verifies its checksum. Run it
# once before building (see "Building" in the README).
#
# Lawnchair source: https://github.com/LawnchairLauncher/lawnchair
#
set -euo pipefail

VERSION="v14.0.0-beta3"
URL="https://github.com/LawnchairLauncher/lawnchair/releases/download/${VERSION}/Lawnchair.14.0.0.Beta.3.apk"
SHA256="b1cc5bc468bbc5fc26a0107e348149dac349fd0247dca40f290bfd11b78957db"

DST="$(cd "$(dirname "$0")/.." && pwd)/device/glodroid/dragon_q6a/apps/Lawnchair/Lawnchair.apk"

echo "Fetching Lawnchair ${VERSION}"
echo "  -> ${DST}"
curl -fL --retry 3 -o "${DST}" "${URL}"

echo "${SHA256}  ${DST}" | sha256sum -c -
echo "Lawnchair APK ready."
