#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
case "${1:-}" in
  format)
    swiftformat ScreenText ScreenTextTests Scripts --config .swiftformat --lint --strict --cache ignore
    ;;
  lint)
    swiftlint lint --config .swiftlint.yml --strict --no-cache
    ;;
  build|test)
    action="$1"
    configuration=Release
    [[ "$action" == test ]] && configuration=Debug
    xcodebuild -project ScreenText.xcodeproj -scheme ScreenText \
      -configuration "$configuration" -destination 'platform=macOS' \
      -derivedDataPath build -disableAutomaticPackageResolution \
      CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- \
      "${action}" "${@:2}"
    ;;
  *) echo "Usage: $0 {format|lint|build|test} [xcodebuild arguments]" >&2; exit 2 ;;
esac
