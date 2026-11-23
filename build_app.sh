#!/bin/bash
# Builds Calendesk.app into ./build
set -euo pipefail
cd "$(dirname "$0")"
APP=build/Calendesk.app
swift build -c release
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Calendesk "$APP/Contents/MacOS/Calendesk"

# Icon
TMP=$(mktemp -d)
swift scripts/make_icon.swift "$TMP/icon.png"
ICONSET="$TMP/AppIcon.iconset"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$TMP"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Calendesk</string>
  <key>CFBundleDisplayName</key><string>Calendesk</string>
  <key>CFBundleIdentifier</key><string>app.calendesk.calendar</string>
  <key>CFBundleExecutable</key><string>Calendesk</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCalendarsFullAccessUsageDescription</key><string>Calendesk shows your events on the calendar widget and lets you add new ones.</string>
  <key>NSCalendarsUsageDescription</key><string>Calendesk shows your events on the calendar widget.</string>
</dict></plist>
PLIST
codesign --force --deep -s - "$APP"
echo "Built $APP"
