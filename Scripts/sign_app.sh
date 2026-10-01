#!/bin/bash
# Developer ID step for external release tooling; run after build_app.sh.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${APP_BUNDLE:-$ROOT_DIR/.build/app/Vesila.app}"
IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
[ "$#" -le 1 ] || { echo 'Usage: sign_app.sh [DEVELOPER_ID_APPLICATION]' >&2; exit 1; }
if [ "$#" = 1 ]; then IDENTITY="$1"; fi
[[ -n "$IDENTITY" && "$IDENTITY" != '-' ]] || { echo 'Set DEVELOPER_ID_APPLICATION or pass a Developer ID Application identity.' >&2; exit 1; }
for TOOL in codesign python3; do
  command -v "$TOOL" >/dev/null || { echo "Missing macOS tool: $TOOL" >&2; exit 1; }
done
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
VERSION="$FRAMEWORK/Versions/Current"
# Preflight every required component before changing any signature.
[[ -f "$APP/Contents/Info.plist" && -f "$ROOT_DIR/Packaging/Vesila.entitlements" ]] || { echo 'App or entitlements missing.' >&2; exit 1; }
python3 - "$ROOT_DIR/Scripts" "$APP/Contents/Info.plist" <<'PYTHON'
import plistlib, sys
sys.path.insert(0, sys.argv[1])
from appcast import public_key
try:
    with open(sys.argv[2], 'rb') as file:
        public_key(plistlib.load(file).get('SUPublicEDKey'))
except (ValueError, OSError, plistlib.InvalidFileException) as error:
    sys.exit(f'Cannot sign updater release: {error}')
PYTHON
COMPONENTS=()
for SERVICE in "$VERSION"/XPCServices/*.xpc; do
  [ -d "$SERVICE" ] || { echo 'Sparkle XPC services missing.' >&2; exit 1; }
  COMPONENTS+=("$SERVICE")
done
for COMPONENT in "$VERSION/Autoupdate" "$VERSION/Updater.app" "$FRAMEWORK"; do
  [ -e "$COMPONENT" ] || { echo "Missing Sparkle component: $COMPONENT" >&2; exit 1; }
  COMPONENTS+=("$COMPONENT")
done
for COMPONENT in "${COMPONENTS[@]}"; do
  codesign --force --sign "$IDENTITY" --options runtime --timestamp "$COMPONENT"
done
codesign --force --sign "$IDENTITY" --options runtime --timestamp --entitlements "$ROOT_DIR/Packaging/Vesila.entitlements" "$APP"
for COMPONENT in "${COMPONENTS[@]}" "$APP"; do
  codesign --verify --strict --verbose=2 "$COMPONENT"
done
# Gatekeeper acceptance requires notarization; assess only after stapling.
echo 'Signatures verified. After notarization/stapling run: spctl --assess --type execute --verbose=2 on the app.'
