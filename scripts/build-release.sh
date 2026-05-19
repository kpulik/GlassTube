#!/usr/bin/env bash
# Build an unsigned GlassTube.app locally and zip it for a GitHub Release.
#
# Use this if GitHub Actions can't build (e.g. the runner doesn't yet have
# Xcode 26 / macOS 26 SDK).
#
# Usage:
#   scripts/build-release.sh v0.1.0
#   gh release create v0.1.0 GlassTube-v0.1.0.zip GlassTube-v0.1.0.zip.sha256 \
#     --title "GlassTube v0.1.0" --generate-notes

set -euo pipefail

TAG="${1:-}"
if [ -z "$TAG" ]; then
  echo "usage: $0 <tag>   e.g. $0 v0.1.0" >&2
  exit 1
fi
VERSION="${TAG#v}"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "==> Building GlassTube $TAG (version $VERSION)"

xcodebuild \
  -project GlassTube.xcodeproj \
  -scheme GlassTube \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath build \
  MARKETING_VERSION="$VERSION" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  DEVELOPMENT_TEAM="" \
  clean build

APP="build/Build/Products/Release/GlassTube.app"
test -d "$APP" || { echo "missing $APP" >&2; exit 1; }

ZIP="GlassTube-${TAG}.zip"
rm -f "$ZIP" "$ZIP.sha256"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
shasum -a 256 "$ZIP" | tee "$ZIP.sha256"

echo
echo "==> Artifact: $ZIP"
echo "==> Next: gh release create $TAG $ZIP $ZIP.sha256 --title 'GlassTube $TAG' --generate-notes"
