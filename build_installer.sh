#!/bin/bash
# Builds Calendesk.app, then packages it as:
#   dist/Calendesk-<version>.dmg  (drag-to-Applications disk image)
#   dist/Calendesk-<version>.pkg  (standard macOS Installer package)
#   dist/Calendesk-<version>.zip  (the .pkg + How to Install.txt)
#   dist/How to Install.txt   (also inside the .dmg and the .zip)
set -euo pipefail
cd "$(dirname "$0")"

./build_app.sh
APP=build/Calendesk.app
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP/Contents/Info.plist")
mkdir -p dist
rm -f "dist/Calendesk-$VERSION.dmg" "dist/Calendesk-$VERSION.pkg" "dist/Calendesk-$VERSION.zip"
GUIDE="Installer/How to Install.txt"

# ---- DMG ----
STAGE=$(mktemp -d)
ditto "$APP" "$STAGE/Calendesk.app"
ln -s /Applications "$STAGE/Applications"
cp "$GUIDE" "$STAGE/"
cp "$APP/Contents/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
hdiutil create -volname "Calendesk" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$STAGE.rw.dmg" >/dev/null
# Give the mounted volume the app's icon.
MNT=$(hdiutil attach -nobrowse -noautoopen "$STAGE.rw.dmg" | awk -F'\t' '/\/Volumes\//{print $NF}')
SetFile -a C "$MNT" 2>/dev/null || true
hdiutil detach "$MNT" -quiet
hdiutil convert "$STAGE.rw.dmg" -format UDZO -imagekey zlib-level=9 -o "dist/Calendesk-$VERSION.dmg" >/dev/null
rm -rf "$STAGE" "$STAGE.rw.dmg"
codesign --force -s - "dist/Calendesk-$VERSION.dmg"

# ---- PKG ----
ROOT=$(mktemp -d)
mkdir -p "$ROOT/Applications"
ditto "$APP" "$ROOT/Applications/Calendesk.app"
# Always install to /Applications (don't "relocate" to another copy found on disk).
pkgbuild --analyze --root "$ROOT" "$ROOT.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$ROOT.plist"
pkgbuild --root "$ROOT" \
         --component-plist "$ROOT.plist" \
         --identifier app.calendesk.calendar.pkg \
         --version "$VERSION" \
         --install-location / \
         "dist/Calendesk-$VERSION.pkg" >/dev/null
rm -rf "$ROOT" "$ROOT.plist"

# ---- ZIP (pkg + install guide) and loose guide ----
cp "$GUIDE" "dist/How to Install.txt"
ZIPDIR="$(mktemp -d)/Calendesk-$VERSION"
mkdir -p "$ZIPDIR"
cp "dist/Calendesk-$VERSION.pkg" "$GUIDE" "$ZIPDIR/"
ditto -c -k --norsrc --noextattr --keepParent "$ZIPDIR" "dist/Calendesk-$VERSION.zip"
rm -rf "$(dirname "$ZIPDIR")"

echo "Installers:"
ls -lh dist/
