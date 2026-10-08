#!/bin/sh
# Builds build/Tuloy.app with nothing but the Swift that comes with Xcode.
# Run it from anywhere: ./scripts/make-app.sh   (or: make app)
set -eu
cd "$(dirname "$0")/.."

swift build -c release
binary="$(swift build -c release --show-bin-path)/Tuloy"

app=build/Tuloy.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$binary" "$app/Contents/MacOS/Tuloy"
cp Support/Info.plist "$app/Contents/Info.plist"

# Signed to run on this Mac. To share builds, sign with your Developer ID instead.
codesign --force --sign - --options runtime "$app"

echo "Built $app"
