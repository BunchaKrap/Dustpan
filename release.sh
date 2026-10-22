#!/usr/bin/env bash
# Publishes a Dustpan release that the in-app updater picks up.
# Usage: ./release.sh 0.3.0 ["What changed"]      (needs the GitHub CLI: brew install gh && gh auth login)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: ./release.sh <version> [notes]}"
NOTES="${2:-Dustpan $VERSION}"
REPO="${DUSTPAN_REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
ZIP="build/Dustpan-${VERSION}-macOS.zip"

DUSTPAN_VERSION="$VERSION" DUSTPAN_REPO="$REPO" ./bundle.sh release
rm -f "$ZIP"
# ditto keeps the code signature and bundle metadata intact.
ditto -c -k --sequesterRsrc --keepParent build/Dustpan.app "$ZIP"

gh release create "v${VERSION}" "$ZIP" --repo "$REPO" --title "Dustpan ${VERSION}" --notes "$NOTES"
echo "Published v${VERSION} to https://github.com/${REPO}/releases"
