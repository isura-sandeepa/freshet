#!/bin/bash
# Builds a release binary and wraps it in build/Freshet.app with the Info.plist that
# registers magnet links and .torrent files. Ad-hoc signed for local use.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product Freshet
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/Freshet.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Freshet" "$APP/Contents/MacOS/Freshet"
cp Scripts/Info.plist "$APP/Contents/Info.plist"
cp Scripts/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Resources SwiftPM bundled for the app target (the DB-IP country database, its licence and the
# third-party notices, which must ship with the app).
find "$BIN_DIR/Freshet_FreshetApp.bundle" -type f \( -name 'countries.fcdb' -o -name 'DBIP-LICENSE.txt' -o -name 'THIRD_PARTY_NOTICES.txt' \) \
  -exec cp {} "$APP/Contents/Resources/" \;
codesign --force --sign - --timestamp=none "$APP"
echo "Built $(pwd)/$APP"
echo "Open it with: open \"$(pwd)/$APP\""
