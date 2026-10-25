#!/bin/zsh
# Builds "Sonos Ace Battery.app" into ./build.
#   ./build.sh            build only
#   ./build.sh --run      build and launch
#   ./build.sh --install  build, copy to /Applications and launch
#   ./build.sh --dist     universal (arm64 + x86_64) build, packaged as .zip and .dmg in ./dist
# Set VERSION=1.2.3 to stamp the bundle's version (the release workflow does this from the tag).
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Sonos Ace Battery"
APP="build/$APP_NAME.app"
MODE="${1:-}"

if [[ "$MODE" == --dist ]]; then
  BIN=".build/universal/SonosAceBattery"
  mkdir -p "${BIN:h}"
  # Build each slice separately (works with just the command line tools), then merge.
  for arch in arm64 x86_64; do
    swift build -c release --arch "$arch" 2>&1 | grep -v "^\[" || true
    cp "$(swift build -c release --arch "$arch" --show-bin-path)/SonosAceBattery" "$BIN-$arch"
  done
  lipo -create -output "$BIN" "$BIN-arm64" "$BIN-x86_64"
else
  swift build -c release 2>&1 | grep -v "^\[" || true
  BIN=".build/release/SonosAceBattery"
fi
[[ -x "$BIN" ]] || { echo "build failed: $BIN not found"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SonosAceBattery"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION#v}" "$APP/Contents/Info.plist"
fi
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
echo -n "APPL????" > "$APP/Contents/PkgInfo"
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Built $APP"

case "$MODE" in
  --run)
    pkill -x SonosAceBattery 2>/dev/null || true
    open "$APP"
    ;;
  --install)
    pkill -x SonosAceBattery 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/$APP_NAME.app"
    echo "Installed /Applications/$APP_NAME.app"
    open "/Applications/$APP_NAME.app"
    ;;
  --dist)
    rm -rf dist && mkdir -p dist/dmg
    ditto -c -k --keepParent "$APP" dist/SonosAceBattery.zip
    cp -R "$APP" dist/dmg/
    ln -s /Applications dist/dmg/Applications
    hdiutil create -quiet -volname "$APP_NAME" -srcfolder dist/dmg -ov -format UDZO dist/SonosAceBattery.dmg
    rm -rf dist/dmg
    (cd dist && shasum -a 256 SonosAceBattery.zip > SonosAceBattery.zip.sha256 \
             && shasum -a 256 SonosAceBattery.dmg > SonosAceBattery.dmg.sha256)
    echo "Packaged dist/SonosAceBattery.zip and dist/SonosAceBattery.dmg"
    ;;
esac
