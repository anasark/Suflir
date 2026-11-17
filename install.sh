#!/bin/bash
# Builds Suflir and installs it into /Applications, replacing any older copy.
# Needs only the Xcode command line tools.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Suflir.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

swiftc -O -swift-version 5 -target arm64-apple-macos14.0 \
    Sources/*.swift -o "$APP/Contents/MacOS/Suflir"
codesign --force --sign - "$APP"

# The zip is what gets uploaded to a GitHub release.
rm -f build/Suflir.zip
ditto -c -k --keepParent "$APP" build/Suflir.zip

# Quit the running copy first so the new one can take its place.
pkill -x Suflir 2>/dev/null || true
sleep 1

rm -rf /Applications/Suflir.app
ditto "$APP" /Applications/Suflir.app
open /Applications/Suflir.app
echo "Installed /Applications/Suflir.app"
echo "Release file: build/Suflir.zip"
