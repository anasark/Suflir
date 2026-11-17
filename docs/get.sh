#!/bin/bash
# Downloads the latest Suflir release and installs it into /Applications.
#
#   curl -fsSL https://suflir.anasabdur.com/get.sh | bash
#
set -euo pipefail

URL="${SUFLIR_ZIP_URL:-https://github.com/anasark/suflir/releases/latest/download/Suflir.zip}"

fail() { echo "Suflir: $1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "this app only runs on macOS."
[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ] || fail "this build needs a Mac with Apple silicon (M1 or newer)."
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MAJOR" -ge 14 ] || fail "macOS 14 or later is required (this Mac has $(sw_vers -productVersion))."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Suflir…"
curl -fsSL "$URL" -o "$TMP/Suflir.zip" || fail "the download failed. Check your internet connection and try again."
ditto -x -k "$TMP/Suflir.zip" "$TMP"
[ -d "$TMP/Suflir.app" ] || fail "the download did not contain Suflir.app."

# Quit a running copy so the new one can replace it.
pkill -x Suflir 2>/dev/null || true
sleep 1

rm -rf /Applications/Suflir.app
ditto "$TMP/Suflir.app" /Applications/Suflir.app
open /Applications/Suflir.app

echo "Suflir is installed in /Applications and running."
echo "Look for the speech bubble icon in the menu bar."
