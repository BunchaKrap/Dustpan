#!/usr/bin/env bash
# Builds Dustpan.app from SwiftPM output. Usage: ./bundle.sh [release|debug] [--open]
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="Dustpan"
BUNDLE_ID="com.local.dustpan"
VERSION="${DUSTPAN_VERSION:-0.2.0}"
# GitHub repo the in-app updater checks (owner/name). Must be public. Empty disables updates.
UPDATE_REPO="${DUSTPAN_REPO:-}"
APP="build/${APP_NAME}.app"
ICON_STYLE="${DUSTPAN_ICON:-sweep}"   # Finder icon: sweep | paper | catch | mark

swift build -c "$CONFIG" --product "$APP_NAME"
swift build -c "$CONFIG" --product dustpan-cli
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# SwiftPM resource bundles, if any target adds resources later.
for bundle in "$BIN_DIR"/*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
"$BIN_DIR/dustpan-cli" export-iconset "$ICON_STYLE" "$ICONSET" >/dev/null
iconutil -c icns -o "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>DustpanUpdateRepo</key><string>${UPDATE_REPO}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so Gatekeeper/TCC treat it as a stable local app.
codesign --force --sign - "$APP" >/dev/null

echo "Built $APP"
if [[ "${2:-}" == "--open" ]]; then open "$APP"; fi
