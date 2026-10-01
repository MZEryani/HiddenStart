#!/usr/bin/env bash
set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_ROOT}"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d "/Applications/Xcode-27.0.0.app" ]; then
    export DEVELOPER_DIR="/Applications/Xcode-27.0.0.app/Contents/Developer"
fi

VERSION="${1:-$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" HiddenStart/Info.plist 2>/dev/null || echo "0.9.0")}"
DIST_DIR="${PROJECT_ROOT}/dist"
APP_NAME="HiddenStart"
VOL_NAME="${APP_NAME}"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
FINAL_DMG="${DIST_DIR}/${DMG_NAME}"
STAGING_DIR="${DIST_DIR}/staging"
TEMP_DMG="${DIST_DIR}/temp.dmg"

echo "==> Building ${APP_NAME} v${VERSION} for Release (arm64)..."
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}" "${STAGING_DIR}"

# 1. Regenerate Xcode project if xcodegen is available
if command -v xcodegen >/dev/null 2>&1; then
    echo "==> Generating Xcode project with xcodegen..."
    xcodegen generate
fi

# 2. Build Release configuration
DERIVED_DATA="${PROJECT_ROOT}/.build/derivedData"
xcodebuild -project "${APP_NAME}.xcodeproj" \
    -scheme "${APP_NAME}" \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "${DERIVED_DATA}" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    clean build

BUILT_APP="${DERIVED_DATA}/Build/Products/Release/${APP_NAME}.app"
if [ ! -d "${BUILT_APP}" ]; then
    echo "Error: Built application not found at ${BUILT_APP}" >&2
    exit 1
fi

# 3. Code Sign Application Bundle
if [ -n "${APPLE_DEVELOPER_IDENTITY:-}" ]; then
    echo "==> Signing app bundle with Developer ID: ${APPLE_DEVELOPER_IDENTITY}..."
    codesign --force --deep --options runtime --timestamp \
        --entitlements "HiddenStart/HiddenStart.entitlements" \
        --sign "${APPLE_DEVELOPER_IDENTITY}" "${BUILT_APP}"
else
    echo "==> No APPLE_DEVELOPER_IDENTITY specified; signing ad-hoc with Hardened Runtime..."
    codesign --force --deep --options runtime \
        --entitlements "HiddenStart/HiddenStart.entitlements" \
        --sign - "${BUILT_APP}"
fi

# 4. Prepare Staging Directory
echo "==> Preparing DMG staging area..."
cp -R "${BUILT_APP}" "${STAGING_DIR}/${APP_NAME}.app"
ln -s /Applications "${STAGING_DIR}/Applications"

mkdir -p "${STAGING_DIR}/.background"
if [ -f "docs/assets/dmg-background.png" ]; then
    cp "docs/assets/dmg-background.png" "${STAGING_DIR}/.background/background.png"
fi

# 5. Create Writable Disk Image
echo "==> Creating temporary disk image..."
rm -f "${TEMP_DMG}" "${FINAL_DMG}"
hdiutil create -srcfolder "${STAGING_DIR}" -volname "${VOL_NAME}" -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" -format UDRW -size 120m "${TEMP_DMG}"

# 6. Mount and Configure Finder View
echo "==> Mounting image to configure Finder layout..."
MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "${TEMP_DMG}")
DEVICE=$(echo "${MOUNT_OUTPUT}" | awk 'NR==1 {print $1}')
MOUNT_DIR=$(echo "${MOUNT_OUTPUT}" | grep '/Volumes/' | awk -F'\t' '{print $NF}')

if [ -z "${MOUNT_DIR}" ]; then
    MOUNT_DIR="/Volumes/${VOL_NAME}"
fi

echo "Mounted on ${MOUNT_DIR} via ${DEVICE}"

# Configure Finder visual properties via AppleScript
osascript <<EOF || true
tell application "Finder"
    tell disk "${VOL_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 740, 480}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 84
        set text size of viewOptions to 12
        if exists file ".background:background.png" then
            set background picture of viewOptions to file ".background:background.png"
        end if
        set position of item "${APP_NAME}.app" of container window to {140, 160}
        set position of item "Applications" of container window to {400, 160}
        close
        open
        delay 1
    end tell
end tell
EOF

# Clean up any stray clipping or system files and hide .background
rm -f "${MOUNT_DIR}"/*.textClipping 2>/dev/null || true
rm -rf "${MOUNT_DIR}/.Trashes" "${MOUNT_DIR}/.fseventsd" 2>/dev/null || true
chflags hidden "${MOUNT_DIR}/.background" 2>/dev/null || true

# Sync and unmount
sync
echo "==> Detaching disk image..."
if ! hdiutil detach "${DEVICE}" -force 2>/dev/null; then
    sleep 2
    hdiutil detach "${DEVICE}" -force 2>/dev/null || true
fi

# 7. Convert to Compressed Read-Only DMG
echo "==> Compressing final DMG..."
hdiutil convert "${TEMP_DMG}" -format UDZO -imagekey zlib-level=9 -o "${FINAL_DMG}"
rm -f "${TEMP_DMG}"
rm -rf "${STAGING_DIR}"

# 8. Sign DMG and Notarize if Credentials Exist
if [ -n "${APPLE_DEVELOPER_IDENTITY:-}" ]; then
    echo "==> Signing DMG with Developer ID: ${APPLE_DEVELOPER_IDENTITY}..."
    codesign --sign "${APPLE_DEVELOPER_IDENTITY}" --timestamp "${FINAL_DMG}"

    if [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
        echo "==> Submitting DMG for Apple Notarization..."
        xcrun notarytool submit "${FINAL_DMG}" \
            --apple-id "${APPLE_ID}" \
            --password "${APPLE_PASSWORD}" \
            --team-id "${APPLE_TEAM_ID}" \
            --wait

        echo "==> Stapling notarization ticket to DMG..."
        xcrun stapler staple "${FINAL_DMG}"
    elif [ -n "${APPLE_API_KEY_PATH:-}" ] && [ -n "${APPLE_API_KEY_ID:-}" ] && [ -n "${APPLE_API_ISSUER:-}" ]; then
        echo "==> Submitting DMG for Apple Notarization via API Key..."
        xcrun notarytool submit "${FINAL_DMG}" \
            --key "${APPLE_API_KEY_PATH}" \
            --key-id "${APPLE_API_KEY_ID}" \
            --issuer "${APPLE_API_ISSUER}" \
            --wait

        echo "==> Stapling notarization ticket to DMG..."
        xcrun stapler staple "${FINAL_DMG}"
    else
        echo "==> Notice: No Apple Notarization credentials provided. Skipping notarytool."
    fi
else
    echo "==> Ad-hoc DMG generated (unsigned). Gatekeeper instructions included in DMG footnote."
fi

# 9. Compute Checksum
echo "==> Computing SHA256 checksum..."
(cd "${DIST_DIR}" && shasum -a 256 "${DMG_NAME}" > "${DMG_NAME}.sha256")

echo ""
echo "============================================================"
echo " Packaging Complete!"
echo " DMG:      ${FINAL_DMG}"
echo " Size:     $(du -h "${FINAL_DMG}" | cut -f1)"
echo " SHA256:   $(cat "${FINAL_DMG}.sha256" | cut -d' ' -f1)"
echo "============================================================"
