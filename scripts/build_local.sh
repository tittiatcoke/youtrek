#!/bin/zsh
# Builds an ad-hoc signed YouTrek without app groups or keychain access groups.
# Needs no provisioning profile, so it never expires. Usage: scripts/build_local.sh [--install]
set -euo pipefail
cd "${0:A:h}/.."
OUT="$PWD/build/local"

xcodebuild -project YouTrek.xcodeproj -scheme YouTrek -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$OUT" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= \
  CODE_SIGN_ENTITLEMENTS="$PWD/YouTrekLocal.entitlements" \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) LOCAL_BUILD' \
  build

APP="$OUT/Build/Products/Release/YouTrek.app"
codesign --force --deep --sign - --options runtime \
  --entitlements YouTrekLocal.entitlements "$APP"
codesign -dvv "$APP" 2>&1 | grep -E "Signature|TeamIdentifier"
echo "Built: $APP"

if [[ "${1:-}" == "--install" ]]; then
  osascript -e 'quit app "YouTrek"' 2>/dev/null || true
  rm -rf /Applications/YouTrek.app
  cp -R "$APP" /Applications/YouTrek.app
  echo "Installed to /Applications/YouTrek.app"
fi
