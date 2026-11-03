#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP="CherryRemap.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -R Resources/*.lproj Resources/AppIcon.icns "$APP/Contents/Resources/"
swiftc -O -parse-as-library CherryRemap.swift Lighting.swift -o "$APP/Contents/MacOS/CherryRemap"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>nl</string></array>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>nl.bongers.cherryremap</string>
<key>CFBundleName</key><string>Cherry Remap</string>
<key>CFBundleExecutable</key><string>CherryRemap</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
# A stable identity keeps the macOS privacy permissions valid across rebuilds; fall back to ad-hoc.
IDENTITY="CherryRemap Local Signing"
if security find-identity -p codesigning | grep -q "$IDENTITY"; then
  codesign --force --sign "$IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "Built: $PWD/$APP"
