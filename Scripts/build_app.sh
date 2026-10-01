#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/app"
APP_NAME="Vesila"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "Building release binary..."
swift build --package-path "$ROOT_DIR" -c release

BIN_PATH="$(swift build --package-path "$ROOT_DIR" -c release --show-bin-path)"

echo "Assembling $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

VERSION_FILE="$ROOT_DIR/VERSION"
BUILD_NUMBER_FILE="$ROOT_DIR/BUILD_NUMBER"
APP_VERSION="$( [ -f "$VERSION_FILE" ] && tr -d '[:space:]' < "$VERSION_FILE" || echo "0.0.0" )"
APP_BUILD_NUMBER="$( [ -f "$BUILD_NUMBER_FILE" ] && tr -d '[:space:]' < "$BUILD_NUMBER_FILE" || echo "1" )"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"
echo "Stamped Info.plist: CFBundleShortVersionString=$APP_VERSION CFBundleVersion=$APP_BUILD_NUMBER"

# Holds the status bar icons. Without it Vesila can't load them (Bundle.module traps at launch).
RESOURCE_BUNDLE="$BIN_PATH/${APP_NAME}_${APP_NAME}.bundle"
if [ ! -d "$RESOURCE_BUNDLE" ]; then
  echo "Resource bundle not found at $RESOURCE_BUNDLE; refusing to package an app that would crash at launch." >&2
  exit 1
fi
cp -R "$RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"

ICON_SOURCE="$ROOT_DIR/app-icon.png"
if [ -f "$ICON_SOURCE" ]; then
  echo "Generating application icon..."
  ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  for SIZE in 16 32 128 256 512; do
    sips -z "$SIZE" "$SIZE" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}.png" >/dev/null
    DOUBLE=$((SIZE * 2))
    sips -z "$DOUBLE" "$DOUBLE" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
  done

  iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/$APP_NAME.icns"
else
  echo "Warning: $ICON_SOURCE not found, skipping application icon generation." >&2
fi

echo "App bundle created at: $APP_BUNDLE"
echo ""
echo "For signed, notarized releases, use the maintainer release tooling kept outside this repository."
