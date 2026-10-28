#!/usr/bin/env bash
# Builds a macOS installer package that puts Dustpan.app in /Applications.
# Usage: ./pkg.sh [version]        (default: $DUSTPAN_VERSION, else bundle.sh's default)
# Set DUSTPAN_INSTALLER_IDENTITY="Developer ID Installer: …" to sign it; unsigned otherwise.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-${DUSTPAN_VERSION:-}}"
BUNDLE_ID="com.local.dustpan"
WORK="build/pkg"

if [[ -n "$VERSION" ]]; then
  DUSTPAN_VERSION="$VERSION" ./bundle.sh release
else
  ./bundle.sh release
  VERSION="$(defaults read "$PWD/build/Dustpan.app/Contents/Info" CFBundleShortVersionString)"
fi
PKG="build/Dustpan-${VERSION}-macOS.pkg"

rm -rf "$WORK" "$PKG"
mkdir -p "$WORK/root"
# ditto keeps the code signature and bundle metadata intact.
ditto build/Dustpan.app "$WORK/root/Dustpan.app"

# Without this, Installer "relocates" the install to any other copy of the app it finds
# (e.g. build/Dustpan.app) instead of writing to /Applications.
pkgbuild --analyze --root "$WORK/root" "$WORK/component.plist" >/dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/component.plist"

pkgbuild --root "$WORK/root" \
  --component-plist "$WORK/component.plist" \
  --identifier "$BUNDLE_ID" \
  --version "$VERSION" \
  --install-location /Applications \
  "$WORK/Dustpan-component.pkg" >/dev/null

productbuild --synthesize --package "$WORK/Dustpan-component.pkg" "$WORK/distribution.xml" >/dev/null
# Installer window title, macOS 14 minimum (matches LSMinimumSystemVersion) and Apple Silicon only.
sed -i '' -e 's#<installer-gui-script minSpecVersion="[0-9]*">#&\
    <title>Dustpan</title>\
    <allowed-os-versions><os-version min="14.0"/></allowed-os-versions>#' \
  -e "s#hostArchitectures=\"[^\"]*\"#hostArchitectures=\"$(lipo -archs build/Dustpan.app/Contents/MacOS/Dustpan | tr ' ' ',')\"#" \
  "$WORK/distribution.xml"

SIGN_ARGS=()
[[ -n "${DUSTPAN_INSTALLER_IDENTITY:-}" ]] && SIGN_ARGS=(--sign "$DUSTPAN_INSTALLER_IDENTITY")
productbuild --distribution "$WORK/distribution.xml" --package-path "$WORK" ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} "$PKG" >/dev/null

rm -rf "$WORK"
echo "Built $PKG"
