#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Match the versioning and artifact names used by the signed release script.
if [[ ! "${RELEASE_TAG:-}" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo 'Release tags must be vMAJOR.MINOR.PATCH (for example v0.1.0).' >&2
  exit 1
fi
version="${RELEASE_TAG#v}"
if [[ ! "${RELEASE_BUILD_NUMBER:-}" =~ ^[1-9][0-9]*$ ]]; then
  echo 'RELEASE_BUILD_NUMBER must be a positive integer.' >&2
  exit 1
fi

work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/screentext-release-unsigned.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# Ad-hoc signing preserves the app/helper entitlements without an Apple account.
# This is not a Developer ID signature, and the download is not notarized.
xcodebuild -project ScreenText.xcodeproj -scheme ScreenText -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$work/build" \
  -disableAutomaticPackageResolution ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$RELEASE_BUILD_NUMBER" build

app="$work/build/Build/Products/Release/ScreenText.app"
codesign --verify --deep --strict --verbose=2 "$app"
for architecture in arm64 x86_64; do
  lipo "$app/Contents/MacOS/ScreenText" -verify_arch "$architecture"
  lipo "$app/Contents/MacOS/AccurateOCRHelper" -verify_arch "$architecture"
done

mkdir -p dist "$work/dmg"
ditto "$app" "$work/dmg/ScreenText.app"
ln -s /Applications "$work/dmg/Applications"
dmg="dist/ScreenText-${RELEASE_TAG}-universal.dmg"
hdiutil create -volname "ScreenText $version" -srcfolder "$work/dmg" \
  -ov -format UDZO "$dmg"
(cd dist && shasum -a 256 "$(basename "$dmg")" > SHA256SUMS)
