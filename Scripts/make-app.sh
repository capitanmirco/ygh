#!/bin/bash
# Assembles YGODeckManager.app around the SwiftPM executable.
#
# SwiftPM builds a bare binary; macOS needs a bundle before it will show an
# icon in the Dock, accept a double click, or let the window carry a name.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-debug}"
APP="$ROOT/.build/$CONFIG/YGODeckManager.app"

swift build -c "$CONFIG" --product YGODeckManager

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/$CONFIG/YGODeckManager" "$APP/Contents/MacOS/"
cp "$ROOT/Resources/icon/AppIcon.icns" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>YGO Deck Manager</string>
    <key>CFBundleDisplayName</key><string>YGO Deck Manager</string>
    <key>CFBundleIdentifier</key><string>io.github.capitanmirco.ygodeckmanager</string>
    <key>CFBundleExecutable</key><string>YGODeckManager</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>27.0</string>
    <!-- Without this the binary runs with no menu bar and no Dock presence. -->
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough for the icon and the Dock locally, and it keeps
# Gatekeeper from complaining on this machine.
codesign --force --sign - "$APP" 2>/dev/null || true

echo "$APP"
