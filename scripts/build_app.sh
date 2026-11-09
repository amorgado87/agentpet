#!/bin/bash
# Builds AgentPet.app into ./build (no Xcode project needed, only the Swift toolchain).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN=".build/release/AgentPet"
APP="build/AgentPet.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/AgentPet"

# App icon, rendered by the app itself from the pixel sprite
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 64 128 256 512 1024; do
  "$BIN" --icon $s "$ICONSET/tmp_$s.png"
done
cp "$ICONSET/tmp_16.png"   "$ICONSET/icon_16x16.png"
cp "$ICONSET/tmp_32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$ICONSET/tmp_32.png"   "$ICONSET/icon_32x32.png"
cp "$ICONSET/tmp_64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$ICONSET/tmp_128.png"  "$ICONSET/icon_128x128.png"
cp "$ICONSET/tmp_256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$ICONSET/tmp_256.png"  "$ICONSET/icon_256x256.png"
cp "$ICONSET/tmp_512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$ICONSET/tmp_512.png"  "$ICONSET/icon_512x512.png"
cp "$ICONSET/tmp_1024.png" "$ICONSET/icon_512x512@2x.png"
rm "$ICONSET"/tmp_*.png
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.agentpet.app</string>
  <key>CFBundleName</key><string>AgentPet</string>
  <key>CFBundleDisplayName</key><string>AgentPet</string>
  <key>CFBundleExecutable</key><string>AgentPet</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "✅ $APP"
