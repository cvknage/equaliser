#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
EXECUTABLE_NAME="Equaliser"
APP_NAME="Equaliser"
RELEASE_DIR="$ROOT_DIR/Release"
APP_BUNDLE="$RELEASE_DIR/${APP_NAME}.app"
INFO_PLIST_SRC="$ROOT_DIR/Sources/App/Info.plist"
ENTITLEMENTS="$ROOT_DIR/Equaliser.entitlements"
ICON_SVG="$ROOT_DIR/Resources/AppIcon.svg"
ICONSET_DIR="$ROOT_DIR/.build/AppIcon.iconset"

if [[ ! -f "$ROOT_DIR/Package.swift" ]]; then
    echo "\nError: bundle.sh must run from repo root containing Package.swift" >&2
    exit 1
fi

swift build -c release

echo "\nCreating app bundle at $APP_BUNDLE"
rm -rf "$RELEASE_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp "$INFO_PLIST_SRC" "$APP_BUNDLE/Contents/Info.plist"

# --- Icon Generation ---
if [[ ! -f "$ICON_SVG" ]]; then
    echo "Warning: Icon SVG not found at $ICON_SVG"
    echo "Skipping icon generation."
elif ! command -v rsvg-convert &> /dev/null; then
    echo "Warning: rsvg-convert not found. Install with: brew install librsvg"
    echo "Skipping icon generation."
else
    echo "Generating app icon..."
    rm -rf "$ICONSET_DIR"
    mkdir -p "$ICONSET_DIR"
    
    # Generate all required sizes for macOS app icon
    for size in 16 32 128 256 512; do
        rsvg-convert -w $size -h $size "$ICON_SVG" -o "$ICONSET_DIR/icon_${size}x${size}.png"
        rsvg-convert -w $((size*2)) -h $((size*2)) "$ICON_SVG" -o "$ICONSET_DIR/icon_${size}x${size}@2x.png"
    done
    
    # Convert iconset to icns
    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    
    echo "App icon generated and installed"
fi

codesign --force --sign - --options runtime \
    --entitlements "$ENTITLEMENTS" \
    "$APP_BUNDLE"

echo "\nBundle created: $APP_BUNDLE"
echo "You can now copy it to /Applications to run Equaliser normally."
