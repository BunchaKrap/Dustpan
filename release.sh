#!/usr/bin/env bash
# Publishes a Dustpan release that the in-app updater picks up.
# Usage: ./release.sh 0.3.0      (needs the GitHub CLI: brew install gh && gh auth login)
# The release notes come from the "## 0.3.0" section of CHANGELOG.md; write that first.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: ./release.sh <version>}"
swift build -c release --product dustpan-cli >/dev/null
# Fails (and stops the release) if CHANGELOG.md has no section for this version.
NOTES="$("$(swift build -c release --show-bin-path)/dustpan-cli" release-notes "$VERSION")"
REPO="${DUSTPAN_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
ZIP="build/Dustpan-${VERSION}-macOS.zip"
PKG="build/Dustpan-${VERSION}-macOS.pkg"

# pkg.sh runs bundle.sh, so the zipped app and the installer's app are the same build.
DUSTPAN_REPO="$REPO" ./pkg.sh "$VERSION"
rm -f "$ZIP"
# ditto keeps the code signature and bundle metadata intact.
ditto -c -k --sequesterRsrc --keepParent build/Dustpan.app "$ZIP"

# The in-app updater uses the .zip; the .pkg is for first-time installs.
# --target tags the commit that was built (it must already be pushed).
gh release create "v${VERSION}" "$ZIP" "$PKG" --repo "$REPO" --target "$(git rev-parse HEAD)" \
  --title "Dustpan ${VERSION}" --notes "$NOTES"
echo "Published v${VERSION} to https://github.com/${REPO}/releases"
