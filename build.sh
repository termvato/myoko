#!/bin/zsh
# Builds Moko.app next to this script.
set -euo pipefail
cd "$(dirname "$0")"

app=Moko.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"

swiftc -O Sources/*.swift -o "$app/Contents/MacOS/Moko"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Moko</string>
  <key>CFBundleIdentifier</key><string>local.moko.menubar</string>
  <key>CFBundleExecutable</key><string>Moko</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$app"
echo "built $PWD/$app"
