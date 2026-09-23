#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
identity="${SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | sed -nE 's/^[[:space:]]*[0-9]+\) ([A-F0-9]{40}) .*/\1/p' | head -n 1)}"
if [[ -z "$identity" ]]; then
    echo "An Apple code-signing identity is required for the privileged helper." >&2
    exit 1
fi
swift build -c release
app="$(pwd)/dist/WireGuard Menu.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Library/LaunchDaemons"
cp .build/release/WireGuardMenu "$app/Contents/MacOS/WireGuardMenu"
cp .build/release/WireGuardHelper "$app/Contents/MacOS/WireGuardHelper"
cp Resources/se.mnilsson.wireguard-menu.helper.plist "$app/Contents/Library/LaunchDaemons/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>se.mnilsson.wireguard-menu</string>
<key>CFBundleName</key><string>WireGuard Menu</string>
<key>CFBundleExecutable</key><string>WireGuardMenu</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --options runtime --sign "$identity" --identifier se.mnilsson.wireguard-menu.helper "$app/Contents/MacOS/WireGuardHelper"
codesign --force --options runtime --sign "$identity" "$app"
codesign --verify --deep --strict "$app"
printf 'Built %s\n' "$app"
