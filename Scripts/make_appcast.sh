#!/bin/bash
# Usage: make_appcast.sh ARCHIVE.zip VERSION [BUILD_NUMBER] [OUTPUT.xml]
# SPARKLE_BIN: bin directory from Sparkle 2.10.0's release distribution.
set -euo pipefail
set +x # Private input must never be logged by shell tracing.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$#" -ge 2 && "$#" -le 4 ]] || { echo 'Usage: make_appcast.sh ARCHIVE.zip VERSION [BUILD_NUMBER] [OUTPUT.xml]' >&2; exit 1; }
ARCHIVE="$1"
VERSION="$2"
BUILD="${3:-$(tr -d '[:space:]' < "$ROOT_DIR/BUILD_NUMBER")}"
OUTPUT="${4:-$(dirname "$ARCHIVE")/appcast.xml}"
[[ -f "$ARCHIVE" && "$ARCHIVE" = *.zip ]] || { echo 'Expected a ZIP of the notarized, stapled Vesila.app.' >&2; exit 1; }
command -v python3 >/dev/null || { echo 'python3 required.' >&2; exit 1; }
# Metadata validation is portable and happens before signing or accessing credentials.
PUBLIC_KEY="$(python3 "$ROOT_DIR/Scripts/appcast.py" metadata "$ARCHIVE" "$VERSION" "$BUILD" "$ROOT_DIR")"
[[ -n "${SPARKLE_BIN:-}" && -x "$SPARKLE_BIN/sign_update" ]] || { echo 'Set SPARKLE_BIN to the Sparkle distribution bin directory.' >&2; exit 1; }
for TOOL in swift ditto codesign spctl xcrun; do
  command -v "$TOOL" >/dev/null || { echo "Missing macOS tool: $TOOL" >&2; exit 1; }
done
WORK="$(mktemp -d "${TMPDIR:-/tmp}/vesila-appcast.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# Verify the shipped bundle, not a possibly different local build.
ditto -x -k "$ARCHIVE" "$WORK/unpacked"
APP="$WORK/unpacked/Vesila.app"
codesign --verify --strict --verbose=2 "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
KEY_ARGS=()
if [ -n "${SPARKLE_PRIVATE_ED_KEY_FILE:-}" ] && [ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]; then
  echo 'Choose private key file OR private key environment input, not both.' >&2; exit 1
fi
if [ -n "${SPARKLE_PRIVATE_ED_KEY_FILE:-}" ]; then
  [ -r "$SPARKLE_PRIVATE_ED_KEY_FILE" ] || { echo 'Private key file is unreadable.' >&2; exit 1; }
  KEY_ARGS=(--ed-key-file "$SPARKLE_PRIVATE_ED_KEY_FILE")
elif [ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]; then
  KEY_ARGS=(--ed-key-file -)
else
  KEY_ARGS=(--account "${SPARKLE_KEYCHAIN_ACCOUNT:-ed25519}")
fi
# Sparkle errors may echo malformed key input; capture them in private temporary files.
umask 077
if [ -n "${SPARKLE_PRIVATE_ED_KEY:-}" ]; then
  if ! printf '%s\n' "$SPARKLE_PRIVATE_ED_KEY" | "$SPARKLE_BIN/sign_update" "${KEY_ARGS[@]}" -p "$ARCHIVE" > "$WORK/signature" 2> "$WORK/sign-error"; then
    echo 'Sparkle signing failed; check private key input and Keychain access.' >&2; exit 1
  fi
else
  if ! "$SPARKLE_BIN/sign_update" "${KEY_ARGS[@]}" -p "$ARCHIVE" > "$WORK/signature" 2> "$WORK/sign-error"; then
    echo 'Sparkle signing failed; check private key input and Keychain access.' >&2; exit 1
  fi
fi
SIGNATURE="$(cat "$WORK/signature")"
# CryptoKit verification enforces that the signing key matches the public key shipped in the app.
swift "$ROOT_DIR/Scripts/verify_update.swift" "$ARCHIVE" "$PUBLIC_KEY" "$SIGNATURE"
python3 "$ROOT_DIR/Scripts/appcast.py" render "$ARCHIVE" "$VERSION" "$BUILD" "$SIGNATURE" "$OUTPUT"
echo "Validated appcast created: $OUTPUT"
