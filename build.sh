#!/bin/bash
# Builds Remind Me and packages it as a signed .dmg (Apple Silicon only).
# Run this on your Mac: ./build.sh
#
# Signing identity: ad-hoc ("-") by default, which satisfies Gatekeeper only
# on the Mac that built it. To produce a .dmg you can hand to someone else
# without a Gatekeeper warning, you need a paid Apple Developer Program
# membership and a "Developer ID Application" certificate in your keychain,
# then:
#   export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#   ./build.sh
# Even then, a downloaded .dmg needs notarization to avoid the warning —
# that's not scripted here since it needs your Apple ID / API key:
#   xcrun notarytool submit "dist/Remind Me.dmg" --keychain-profile "<profile>" --wait
#   xcrun stapler staple "dist/Remind Me.dmg"
set -euo pipefail

cd "$(dirname "$0")"

ARCH="$(uname -m)"
if [ "$ARCH" != "arm64" ]; then
    # The app itself is still Apple Silicon only: --arch arm64 below
    # cross-compiles it. (CI uses an Intel runner when Apple Silicon runners
    # are out of capacity.)
    echo "note: building on $ARCH — cross-compiling for Apple Silicon (arm64)."
fi

APP_NAME="RemindMe"
DISPLAY_NAME="Remind Me"
APP_DIR="dist/${DISPLAY_NAME}.app"
DMG_STAGING="dist/dmg-staging"
DMG_PATH="dist/${DISPLAY_NAME}.dmg"
IDENTITY="${CODESIGN_IDENTITY:--}"

echo "-> Building release binary (arm64)..."
swift build -c release --arch arm64
# Ask SwiftPM where it put the binary — the folder layout differs between
# Swift versions, so never hardcode .build/release.
BUILD_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

echo "-> Assembling ${DISPLAY_NAME}.app..."
rm -rf "dist"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
# Smaller app: drop debug and local symbols from the release binary (it's
# already built with -O and whole-module optimisation by -c release).
BEFORE=$(stat -f%z "${APP_DIR}/Contents/MacOS/${APP_NAME}" 2>/dev/null || echo 0)
strip -Sx "${APP_DIR}/Contents/MacOS/${APP_NAME}"
AFTER=$(stat -f%z "${APP_DIR}/Contents/MacOS/${APP_NAME}" 2>/dev/null || echo 0)
echo "   binary: ${BEFORE} -> ${AFTER} bytes"
cp "Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

echo "-> Signing app (identity: ${IDENTITY})..."
codesign --force --deep --options runtime --entitlements "Resources/RemindMe.entitlements" \
    --sign "${IDENTITY}" "${APP_DIR}"
codesign --verify --verbose "${APP_DIR}"

echo "-> Building disk image..."
rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"
cp -R "${APP_DIR}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

rm -f "${DMG_PATH}"
# ULFO = LZFSE compression: smaller and faster to open than the old UDZO.
# hdiutil occasionally fails with "Resource busy" (common on CI Macs) —
# retry a few times before giving up.
for attempt in 1 2 3; do
    if hdiutil create -volname "${DISPLAY_NAME}" -srcfolder "${DMG_STAGING}" \
        -fs HFS+ -ov -format ULFO "${DMG_PATH}"; then
        break
    fi
    if [ "$attempt" = 3 ]; then
        echo "error: hdiutil failed 3 times." >&2
        exit 1
    fi
    echo "   hdiutil failed (attempt ${attempt}), retrying in 5s..."
    sleep 5
done
rm -rf "${DMG_STAGING}"

echo "-> Signing disk image..."
codesign --force --sign "${IDENTITY}" "${DMG_PATH}"
codesign --verify --verbose "${DMG_PATH}"

echo "-> Done: ${DMG_PATH}"
echo "   Open it, then drag Remind Me into Applications."

if [ "${IDENTITY}" = "-" ]; then
    echo
    echo "NOTE: ad-hoc signed — no Developer ID. Gatekeeper allows this on"
    echo "THIS Mac without complaint. On any OTHER Mac it will show an"
    echo "'unidentified developer' warning (right-click > Open bypasses it"
    echo "once). See the comment at the top of this script for what a real"
    echo "signed + notarized build needs."
fi
