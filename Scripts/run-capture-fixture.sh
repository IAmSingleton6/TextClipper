#!/bin/zsh
set -eu

script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp/}screentext-capture-fixture.XXXXXX")"
fixture_app="$fixture_root/ScreenTextCaptureFixture.app"
mkdir -p "$fixture_app/Contents/MacOS"
swiftc -swift-version 6 -module-cache-path "$fixture_root/module-cache" \
    "$script_dir/CaptureFixture.swift" -o "$fixture_app/Contents/MacOS/CaptureFixture"
cat > "$fixture_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.screentext.CaptureFixture</string>
<key>CFBundleName</key><string>ScreenText Capture Fixture</string>
<key>CFBundleExecutable</key><string>CaptureFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST

"$fixture_app/Contents/MacOS/CaptureFixture" &
fixture_pid=$!
trap 'kill "$fixture_pid" 2>/dev/null || true' EXIT
trap 'exit 0' INT TERM
wait "$fixture_pid"
