#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/app"
APP_NAME="Vesila"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# Public-only input. Validate before spending time building or touching an existing app.
UPDATE_KEY="${SPARKLE_PUBLIC_ED_KEY-}"
if [ "${SPARKLE_PUBLIC_ED_KEY+x}" != x ] && [ -f "$ROOT_DIR/Packaging/SparklePublicEDKey" ]; then
  UPDATE_KEY="$(cat "$ROOT_DIR/Packaging/SparklePublicEDKey")"
fi
if [[ ! "$UPDATE_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
  if [ "${VESILA_ALLOW_NO_UPDATE_KEY:-0}" != 1 ]; then
    echo "Missing, placeholder, or invalid Sparkle public EdDSA key. Set Packaging/SparklePublicEDKey to one base64 line (32 bytes), or use SPARKLE_PUBLIC_ED_KEY." >&2
    echo "For a local build with updates disabled only, set VESILA_ALLOW_NO_UPDATE_KEY=1." >&2
    exit 1
  fi
  echo "Warning: explicit local opt-out; this build will have updates disabled." >&2
  UPDATE_KEY=""
fi

echo "Building release binary..."
swift build --package-path "$ROOT_DIR" -c release

BIN_PATH="$(swift build --package-path "$ROOT_DIR" -c release --show-bin-path)"

echo "Assembling $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

cp "$BIN_PATH/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Packaging/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [ -n "$UPDATE_KEY" ]; then
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $UPDATE_KEY" "$APP_BUNDLE/Contents/Info.plist"
else
  /usr/libexec/PlistBuddy -c "Set :SUEnableAutomaticChecks false" "$APP_BUNDLE/Contents/Info.plist"
fi

SPARKLE_SOURCE="$BIN_PATH/Sparkle.framework"
if [ ! -d "$SPARKLE_SOURCE" ]; then
  echo "Sparkle.framework not found at $SPARKLE_SOURCE; refusing to package an app with a missing dependency." >&2
  exit 1
fi
# Preserve Sparkle's versioned framework symlinks and nested helper bundles.
ditto "$SPARKLE_SOURCE" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"

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

# Package.swift supplies @executable_path/../Frameworks; sign only after all mutations.
# Sign nested code inside-out, never with --deep (which can hide incorrectly signed helpers).
SPARKLE_FRAMEWORK="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
SPARKLE_VERSION="$SPARKLE_FRAMEWORK/Versions/Current"
for SERVICE in "$SPARKLE_VERSION"/XPCServices/*.xpc; do
  [ -d "$SERVICE" ] || { echo "Sparkle XPC services missing." >&2; exit 1; }
  codesign --force --sign - --timestamp=none "$SERVICE"
done
codesign --force --sign - --timestamp=none "$SPARKLE_VERSION/Autoupdate"
codesign --force --sign - --timestamp=none "$SPARKLE_VERSION/Updater.app"
codesign --force --sign - --timestamp=none "$SPARKLE_FRAMEWORK"
codesign --force --sign - --timestamp=none --entitlements "$ROOT_DIR/Packaging/Vesila.entitlements" "$APP_BUNDLE"

echo "App bundle created at: $APP_BUNDLE"
echo ""
echo "For signed, notarized releases, use the maintainer release tooling kept outside this repository."
