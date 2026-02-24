#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PACKAGE_DIR="$ROOT_DIR/EqualizerApp"
BUILD_DIR="$PACKAGE_DIR/.build/release"
EXECUTABLE_NAME="EqualizerApp"
APP_NAME="Equaliser"
APP_BUNDLE="$ROOT_DIR/${APP_NAME}.app"
INFO_PLIST_SRC="$PACKAGE_DIR/Sources/EqualizerApp/Info.plist"
ENTITLEMENTS="$PACKAGE_DIR/EqualizerApp.entitlements"

if [[ ! -f "$PACKAGE_DIR/Package.swift" ]]; then
    echo "\nError: bundle.sh must run from repo root containing EqualizerApp/Package.swift" >&2
    exit 1
fi

pushd "$PACKAGE_DIR" >/dev/null
swift build -c release
popd >/dev/null

echo "\nCreating app bundle at $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp "$INFO_PLIST_SRC" "$APP_BUNDLE/Contents/Info.plist"
cp "$ENTITLEMENTS" "$APP_BUNDLE/Contents/EqualizerApp.entitlements"

codesign --force --sign - --options runtime \
    --entitlements "$APP_BUNDLE/Contents/EqualizerApp.entitlements" \
    "$APP_BUNDLE"

echo "\nBundle created: $APP_BUNDLE"
echo "You can now copy it to /Applications to run Equaliser normally."
