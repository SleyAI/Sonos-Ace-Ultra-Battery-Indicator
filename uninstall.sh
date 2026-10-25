#!/bin/bash
# Removes Sonos Ace Battery, its login item, settings, log file and Bluetooth permission.
#
#   curl -fsSL https://raw.githubusercontent.com/SleyAI/Sonos-Ace-Ultra-Battery-Indicator/main/uninstall.sh | bash
set -euo pipefail

APP_NAME="Sonos Ace Battery"
BUNDLE_ID="com.buens.SonosAceBattery"

pkill -x SonosAceBattery 2>/dev/null && sleep 1 || true

for dir in /Applications "$HOME/Applications"; do
  app="$dir/$APP_NAME.app"
  [[ -d "$app" ]] || continue
  # Only the app itself can unregister its login item, so start it once to do that.
  open -g "$app" --args --no-launch-at-login && sleep 2 || true
  pkill -x SonosAceBattery 2>/dev/null || true
  rm -rf "$app"
  echo "Removed $app"
done

defaults delete "$BUNDLE_ID" 2>/dev/null || true
rm -f "$HOME/Library/Logs/SonosAceBattery.log"
tccutil reset BluetoothAlways "$BUNDLE_ID" >/dev/null 2>&1 || true

echo "Sonos Ace Battery has been uninstalled."
