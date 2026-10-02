#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Only stable three-component versions are published by this workflow.
if [[ ! "${RELEASE_TAG:-}" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo 'Release tags must be vMAJOR.MINOR.PATCH (for example v0.1.0).' >&2
  exit 1
fi
version="${RELEASE_TAG#v}"
for name in DEVELOPER_ID_CERTIFICATE_BASE64 DEVELOPER_ID_CERTIFICATE_PASSWORD \
  DEVELOPER_ID_APPLICATION APPLE_TEAM_ID APPLE_ID APPLE_APP_SPECIFIC_PASSWORD RELEASE_BUILD_NUMBER; do
  if [[ -z "${!name:-}" ]]; then
    echo "Missing release credential or setting: $name" >&2
    exit 1
  fi
done
[[ "$DEVELOPER_ID_APPLICATION" == "Developer ID Application: "* ]] || {
  echo 'DEVELOPER_ID_APPLICATION must name a Developer ID Application identity.' >&2; exit 1;
}
[[ "$RELEASE_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || {
  echo 'RELEASE_BUILD_NUMBER must be a positive integer.' >&2; exit 1;
}

work="$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/screentext-release.XXXXXX")"
keychain="$work/signing.keychain-db"
keychain_password="$(openssl rand -hex 32)"
original_keychains=()
while IFS= read -r path; do
  original_keychains+=("$path")
done < <(security list-keychains -d user | sed -E 's/^[[:space:]]*"(.*)"$/\1/')
cleanup() {
  security list-keychains -d user -s "${original_keychains[@]}" || true
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

printf '%s' "$DEVELOPER_ID_CERTIFICATE_BASE64" | /usr/bin/base64 --decode > "$work/certificate.p12"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$work/certificate.p12" -k "$keychain" \
  -P "$DEVELOPER_ID_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
security list-keychains -d user -s "$keychain" "${original_keychains[@]}"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "$keychain_password" "$keychain" >/dev/null
rm "$work/certificate.p12"
xcrun notarytool store-credentials ScreenTextRelease --keychain "$keychain" \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD"

xcodebuild -project ScreenText.xcodeproj -scheme ScreenText -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$work/build" \
  -disableAutomaticPackageResolution ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp --keychain $keychain" \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$RELEASE_BUILD_NUMBER" build

app="$work/build/Build/Products/Release/ScreenText.app"
codesign --verify --deep --strict --verbose=2 "$app"
for architecture in arm64 x86_64; do
  lipo "$app/Contents/MacOS/ScreenText" -verify_arch "$architecture"
done
# Staple the app itself before packaging so the installed copy works offline.
ditto -c -k --keepParent "$app" "$work/ScreenText.zip"
xcrun notarytool submit "$work/ScreenText.zip" --keychain-profile ScreenTextRelease \
  --keychain "$keychain" --wait --timeout 20m
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

mkdir -p dist "$work/dmg"
ditto "$app" "$work/dmg/ScreenText.app"
ln -s /Applications "$work/dmg/Applications"
dmg="dist/ScreenText-${RELEASE_TAG}-universal.dmg"
hdiutil create -volname "ScreenText $version" -srcfolder "$work/dmg" \
  -ov -format UDZO "$dmg"
codesign --sign "$DEVELOPER_ID_APPLICATION" --keychain "$keychain" --timestamp "$dmg"
codesign --verify --strict --verbose=2 "$dmg"
xcrun notarytool submit "$dmg" --keychain-profile ScreenTextRelease \
  --keychain "$keychain" --wait --timeout 20m
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
(cd dist && shasum -a 256 "$(basename "$dmg")" > SHA256SUMS)
