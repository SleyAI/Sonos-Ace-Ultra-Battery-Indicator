#!/bin/bash
# Installs Sonos Ace Battery, a menu bar battery indicator for Sonos Ace headphones.
#
#   curl -fsSL https://raw.githubusercontent.com/SleyAI/Sonos-Ace-Ultra-Battery-Indicator/main/install.sh | bash
#
# Options (when piping, pass them as: ... | bash -s -- --from-source):
#   --from-source       build with the local Swift toolchain instead of downloading a release
#   --version v1.2.3    install that release instead of the latest one
#   --no-login-item     don't register the app to launch at login on a fresh install
set -euo pipefail

REPO="SleyAI/Sonos-Ace-Ultra-Battery-Indicator"
APP_NAME="Sonos Ace Battery"
ASSET="SonosAceBattery.zip"

FROM_SOURCE=0
VERSION=""
LOGIN_ITEM=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-source)   FROM_SOURCE=1 ;;
    --version)       VERSION="${2:?--version needs a tag, e.g. v1.0.0}"; shift ;;
    --no-login-item) LOGIN_ITEM=0 ;;
    -h|--help)       sed -n '2,11p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)               echo "Unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31mError:\033[0m %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == Darwin ]] || fail "this app only runs on macOS."
macos_major="$(sw_vers -productVersion | cut -d. -f1)"
(( macos_major >= 13 )) || fail "macOS 13 Ventura or newer is required (found $(sw_vers -productVersion))."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# When run from a checkout (./install.sh) rather than piped, we can build that checkout.
SCRIPT_DIR=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

if (( FROM_SOURCE )); then
  command -v swift >/dev/null || fail "Swift not found. Install the Xcode command line tools with: xcode-select --install"
  if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/Package.swift" ]]; then
    SRC="$SCRIPT_DIR"
  else
    command -v git >/dev/null || fail "git not found. Install the Xcode command line tools with: xcode-select --install"
    bold "Cloning $REPO…"
    git clone --quiet --depth 1 ${VERSION:+--branch "$VERSION"} "https://github.com/$REPO.git" "$TMP/src"
    SRC="$TMP/src"
  fi
  bold "Building from source (this takes a minute)…"
  "$SRC/build.sh"
  NEW_APP="$SRC/build/$APP_NAME.app"
else
  if [[ -n "$VERSION" ]]; then
    URL="https://github.com/$REPO/releases/download/$VERSION/$ASSET"
  else
    URL="https://github.com/$REPO/releases/latest/download/$ASSET"
  fi
  bold "Downloading ${VERSION:-latest release}…"
  curl -fL --progress-bar -o "$TMP/$ASSET" "$URL" \
    || fail "download failed ($URL). Try again later, or install with --from-source."
  if curl -fsL -o "$TMP/$ASSET.sha256" "$URL.sha256"; then
    (cd "$TMP" && shasum -a 256 -c "$ASSET.sha256" >/dev/null) || fail "checksum mismatch, refusing to install."
  fi
  ditto -x -k "$TMP/$ASSET" "$TMP/unpacked"
  NEW_APP="$TMP/unpacked/$APP_NAME.app"
fi
[[ -d "$NEW_APP" ]] || fail "the build did not produce $APP_NAME.app."

# /Applications is writable for admin users; otherwise fall back to ~/Applications.
DEST_DIR="/Applications"
[[ -w "$DEST_DIR" ]] || { DEST_DIR="$HOME/Applications"; mkdir -p "$DEST_DIR"; }
DEST="$DEST_DIR/$APP_NAME.app"
FRESH_INSTALL=1
[[ -d "$DEST" ]] && FRESH_INSTALL=0

pkill -x SonosAceBattery 2>/dev/null && sleep 1 || true
rm -rf "$DEST"
ditto "$NEW_APP" "$DEST"
# The app is ad-hoc signed, not notarized. Clearing quarantine keeps Gatekeeper from blocking it.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

if (( FRESH_INSTALL && LOGIN_ITEM )); then
  open "$DEST" --args --launch-at-login
else
  open "$DEST"
fi

echo
bold "Installed $DEST"
echo "Look for the headphones icon in your menu bar."
if (( FRESH_INSTALL )); then
  echo "macOS will ask for Bluetooth access once: click Allow, otherwise the app can't see your headphones."
  (( LOGIN_ITEM )) && echo "The app starts automatically at login; turn that off from its menu if you prefer."
fi
