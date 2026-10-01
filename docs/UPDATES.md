# Updates and release operations

Vesila uses Sparkle 2.10.0. Packaged builds check in the background about daily after launch
setup. About → **Check for Updates…** requests an immediate check. Installation needs user
confirmation; an up-to-date manual check reports “You're up to date”. Development runs and
explicit builds without a public key show an explanation instead of starting the updater.

The only app network requests are the HTTPS appcast and the requested update archive (including
GitHub's HTTPS asset redirects). No telemetry, accounts, analytics or system profile is sent.
Release notes for the What’s New window are bundled in the app; they make no network requests.
This feed has no external release-note links. Sparkle retains update settings and the last-check
date locally. Automatic checks do not change Presence, System Awake or onboarding state.

The stable feed is:
`https://github.com/szryldrm/vesila-mac/releases/latest/download/appcast.xml`.
GitHub excludes drafts and prereleases from `latest`. Each enclosure points to a **version-specific**
asset, never `latest`, so changing the stable feed cannot change the bytes of an advertised update.
Only stable versions belong in the production appcast. Build numbers, not marketing versions,
determine update ordering; never reuse or decrease `BUILD_NUMBER`.

## One-time upgrade from 1.0.2

**1.0.2 has no updater.** Download the first updater-enabled stable release from GitHub manually,
quit Vesila, and replace `/Applications/Vesila.app`. Open the new copy; subsequent releases can be
installed using Sparkle. If macOS requests Accessibility again, remove the old entry and grant it
to the new copy. Do not promise that 1.0.2 will display an update notification.

Include this wording in the first updater-enabled release notes:

> This release adds secure automatic update checks and About → Check for Updates. If you use
> Vesila 1.0.2, download and install this release manually once: quit Vesila and replace the app in
> Applications. Future stable updates will be offered inside Vesila.

## One-time maintainer setup

Use macOS 14+, Xcode 16+/Swift 6, Python 3, a Developer ID Application identity in the Keychain,
and a configured `notarytool` Keychain profile. Download the official Sparkle **2.10.0 release
archive**, unpack it outside the repository, and set its tools directory:

```sh
export SPARKLE_BIN="$HOME/Tools/Sparkle-2.10.0/bin"
"$SPARKLE_BIN/generate_keys"
"$SPARKLE_BIN/generate_keys" -p > Packaging/SparklePublicEDKey
# Back up outside the repository to protected offline storage; never upload this file.
umask 077
mkdir -p "$HOME/PrivateBackups/Vesila"
"$SPARKLE_BIN/generate_keys" -x "$HOME/PrivateBackups/Vesila/sparkle-private-key"
git add Packaging/SparklePublicEDKey
```

`generate_keys` stores the private EdDSA key in the login Keychain (default account `ed25519`).
Commit only the one-line base64 **public** key in `Packaging/SparklePublicEDKey`; the tracked
placeholder deliberately prevents release builds. `SPARKLE_PUBLIC_ED_KEY` overrides that public
input for test builds. For a separate account use `generate_keys --account ACCOUNT` and export
`SPARKLE_KEYCHAIN_ACCOUNT=ACCOUNT` when signing. Verify backup restoration on a separate test
Keychain/machine using `generate_keys -f /protected/backup/path` and compare `generate_keys -p`
with the committed public key. Never delete the production Keychain item to test restoration.

If the private key is lost, restore the backup. Do not simply replace the public key: installed
apps trust the old key. Without a recoverable key, arrange a reviewed key migration following
Sparkle's security documentation or require another manual install. Never disable verification.

`make_appcast.sh` uses the Keychain by default. Alternatives are
`SPARKLE_PRIVATE_ED_KEY_FILE=/protected/path` or an injected `SPARKLE_PRIVATE_ED_KEY` environment
value. The environment input is piped to `sign_update --ed-key-file -`, never put in argv. Choose
one source. Do not paste keys into shell history, run with tracing, or put them in `.env` files
in the repository. Sparkle diagnostics are suppressed on signing failure because malformed-key
errors can include their input. No private credential is required by the tracked code itself.

## Ordered stable-release checklist

External, untracked `Scripts/release.sh` / `Scripts/deploy_github.sh` remain the owners of
version bumps, notarization credentials, DMG creation, checksums and deployment. Add the following
tracked calls at the specified points; do not inspect, replace or commit those local scripts.
Before building each release, add its version and user-facing notes to
`Sources/Vesila/Resources/ReleaseNotes.json`. Keep earlier entries to cover skipped updates.
A version without an entry has no release notes of its own; the What’s New window is skipped
when no entries match the update.

Commands below are run from the repo root. Set identities/profile names locally, for example:

```sh
set -euo pipefail
export DEVELOPER_ID_APPLICATION='Developer ID Application: YOUR NAME (TEAMID)'
export NOTARY_PROFILE='your-existing-notarytool-keychain-profile'
export SPARKLE_BIN="$HOME/Tools/Sparkle-2.10.0/bin"
./Scripts/test.sh
# External tooling bumps VERSION and BUILD_NUMBER here, before building.
VERSION_VALUE="$(tr -d '[:space:]' < VERSION)"
BUILD_VALUE="$(tr -d '[:space:]' < BUILD_NUMBER)"
./Scripts/build_app.sh
./Scripts/sign_app.sh
APP='.build/app/Vesila.app'
mkdir -p Releases
# This submission ZIP is temporary; it does not yet contain a staple.
ditto -c -k --sequesterRsrc --keepParent "$APP" Releases/notary-submit.zip
xcrun notarytool submit Releases/notary-submit.zip --keychain-profile "$NOTARY_PROFILE" --wait
# Require Accepted; on failure use notarytool log SUBMISSION_ID with the same profile.
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose=2 "$APP"
# Retain existing external DMG creation, signing, notarization, stapling, verification and SHA-256.
# Produce a separate update ZIP from the final stapled app, after every bundle mutation.
ARCHIVE="Releases/Vesila-${VERSION_VALUE}.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
./Scripts/make_appcast.sh "$ARCHIVE" "$VERSION_VALUE" "$BUILD_VALUE" Releases/appcast.xml
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
python3 -c 'import xml.etree.ElementTree as E; E.parse("Releases/appcast.xml")'
# Prepare release-notes.md outside tracked source (include the 1.0.2 notice for the first release).
gh release create "v$VERSION_VALUE" "$ARCHIVE" Releases/appcast.xml "$ARCHIVE.sha256" \
  --repo szryldrm/vesila-mac --verify-tag --latest \
  --title "Vesila $VERSION_VALUE" --notes-file /path/to/release-notes.md
curl --fail --location https://github.com/szryldrm/vesila-mac/releases/latest/download/appcast.xml \
  --output Releases/published-appcast.xml
cmp Releases/appcast.xml Releases/published-appcast.xml
```

Create/push the version tag using the existing release tooling before `gh --verify-tag`. Attach the
existing verified DMG and its checksum too. When external deployment already creates the Release,
pass these assets to that creation step, or use `gh release upload "v$VERSION_VALUE" "$ARCHIVE"
Releases/appcast.xml --repo szryldrm/vesila-mac` before promoting it to latest. A draft can stage
all assets, then be published as stable; the final release must be non-draft and non-prerelease.

`sign_app.sh` takes `DEVELOPER_ID_APPLICATION` or one positional identity and defaults to
`.build/app/Vesila.app` (`APP_BUNDLE` overrides the path). It signs XPC services → Autoupdate →
Updater.app → Sparkle.framework → app, using Hardened Runtime and timestamps, then verifies each
component strictly. Only the outer app receives `Packaging/Vesila.entitlements`. It never signs
with `--deep`. Gatekeeper assessment occurs **after** notarization/stapling, since an otherwise
valid new Developer ID signature is not yet notarized. Do not re-sign or edit the app after stapling.

The update format is `ditto -c -k --sequesterRsrc --keepParent` ZIP of **Vesila.app**, preserving
framework symlinks, resources and the staple. The existing DMG remains the manual installer.
ZIP isolates updating from DMG presentation and keeps the external DMG flow intact.
`make_appcast.sh ARCHIVE VERSION [BUILD_NUMBER] [OUTPUT]` defaults to the tracked build number and
`appcast.xml` beside the archive. It checks metadata **inside the ZIP**, rejects placeholder or
mismatched public keys and versions, validates the unpacked app's signature/staple/Gatekeeper
acceptance, invokes Sparkle `sign_update`, independently verifies the signature with CryptoKit
against the bundled public key, and atomically writes valid XML. Python 3 and the Swift toolchain
are needed. `Scripts/appcast.py render` is the internal XML-only helper, not a release signing step.

If a stable release goes out without `appcast.xml`, the stable endpoint fails and installed apps
cannot discover updates (they do not infer a version from the Release page). Generate the feed
from the **exact published ZIP** and upload it to that release; do not rebuild under the same asset
name. Verify the stable URL again. If the ZIP itself is wrong, publish a corrected higher build
rather than silently replacing signed release bytes.

## Security model

HTTPS protects transport. Ed25519/EdDSA authenticates the archive bytes against the public key
shipped in the installed app; verification before extraction is enabled. Sparkle also validates
Developer ID code signatures when installing. Modifying bytes or substituting an unrelated signing
key invalidates the archive signature, so the installed app remains unchanged. Developer ID,
Hardened Runtime and notarization add macOS validation; they do not replace the EdDSA signature.
Private signing keys and Apple credentials stay in the maintainer's Keychain or protected inputs.

References: [Sparkle publishing](https://sparkle-project.org/documentation/publishing/),
[Sparkle security](https://sparkle-project.org/documentation/security/),
[2.10.0 tools](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0).

## macOS E2E runbook (maintainer / Sentinel)

These commands and UI observations **must run on macOS**. Linux lint and XML tests do not prove
signing, notarization, installation or launch behavior. Record each outcome, version/build before
and after, and relevant log lines. Use a disposable macOS user with no production Vesila running:
the test apps share its bundle identifier. The local procedure uses throwaway EdDSA keys but real
Developer ID signing/notarization so it exercises the same security path as a stable release.
Never publish these test artifacts to the production feed.

### Local HTTPS setup without GitHub

Install Python 3 and `mkcert` (for example `brew install python mkcert`). Use a fresh disposable
user; `mkcert -install` changes that user's trust store. Begin at the repository root after this
change is committed:

```sh
set -euo pipefail
export LAB="$(mktemp -d "${TMPDIR:-/tmp}/vesila-update-e2e.XXXXXX")"
export SOURCE_REPO="$PWD"
git worktree add --detach "$LAB/source" HEAD
export SPARKLE_BIN="$HOME/Tools/Sparkle-2.10.0/bin"
export SPARKLE_KEYCHAIN_ACCOUNT="vesila-e2e-$(date +%s)"
"$SPARKLE_BIN/generate_keys" --account "$SPARKLE_KEYCHAIN_ACCOUNT"
export SPARKLE_PUBLIC_ED_KEY="$("$SPARKLE_BIN/generate_keys" --account "$SPARKLE_KEYCHAIN_ACCOUNT" -p)"
export DEVELOPER_ID_APPLICATION='Developer ID Application: YOUR NAME (TEAMID)'
export NOTARY_PROFILE='your-existing-notarytool-keychain-profile'
export TEST_FEED_URL="https://localhost:8443/appcast.xml"
mkdir -p "$LAB/feed" "$LAB/older" "$LAB/newer" "$LAB/installed"
mkcert -install
mkcert -cert-file "$LAB/localhost.pem" -key-file "$LAB/localhost-key.pem" localhost 127.0.0.1
# Build in the disposable worktree; production VERSION/key files stay untouched.
cd "$LAB/source"
swift package resolve
./Scripts/test.sh
build_test_app() {
  printf '%s\n' "$1" > VERSION
  printf '%s\n' "$2" > BUILD_NUMBER
  ./Scripts/build_app.sh
  # TEST ONLY: override feed in the copied plist BEFORE Developer ID signing.
  /usr/libexec/PlistBuddy -c "Set :SUFeedURL $TEST_FEED_URL" .build/app/Vesila.app/Contents/Info.plist
  ./Scripts/sign_app.sh
  ditto -c -k --sequesterRsrc --keepParent .build/app/Vesila.app "$LAB/notary-$2.zip"
  xcrun notarytool submit "$LAB/notary-$2.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple .build/app/Vesila.app
  xcrun stapler validate .build/app/Vesila.app
  codesign --verify --strict --verbose=2 .build/app/Vesila.app
  spctl --assess --type execute --verbose=2 .build/app/Vesila.app
  ditto .build/app/Vesila.app "$3/Vesila.app"
}
build_test_app 1.0.3-test 10000 "$LAB/older"
build_test_app 1.0.4-test 10001 "$LAB/newer"
ditto -c -k --sequesterRsrc --keepParent "$LAB/newer/Vesila.app" "$LAB/feed/Vesila-1.0.4-test.zip"
./Scripts/make_appcast.sh "$LAB/feed/Vesila-1.0.4-test.zip" 1.0.4-test 10001 "$LAB/feed/appcast.xml"
# Replace ONLY the enclosure URL for the local experiment; preserve signature/length/build.
python3 - <<'PY'
import os, xml.etree.ElementTree as E
from pathlib import Path
p = Path(os.environ['LAB']) / 'feed/appcast.xml'
t = E.parse(p)
t.find('./channel/item/enclosure').set('url', 'https://localhost:8443/Vesila-1.0.4-test.zip')
t.write(p, encoding='utf-8', xml_declaration=True)
PY
cp "$LAB/feed/appcast.xml" "$LAB/good-appcast.xml"
cp "$LAB/feed/Vesila-1.0.4-test.zip" "$LAB/good-update.zip"
cat > "$LAB/serve.py" <<'PY'
import http.server, os, ssl
from functools import partial
lab = os.environ['LAB']
server = http.server.ThreadingHTTPServer(('127.0.0.1', 8443),
    partial(http.server.SimpleHTTPRequestHandler, directory=lab + '/feed'))
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(lab + '/localhost.pem', lab + '/localhost-key.pem')
server.socket = context.wrap_socket(server.socket, server_side=True)
server.serve_forever()
PY
python3 -u "$LAB/serve.py" > "$LAB/https.log" 2>&1 &
export HTTPS_PID=$!
curl --fail https://localhost:8443/appcast.xml
# Do not use curl -k or weaken App Transport Security.
# Keep background checks off while testing the manual cases.
defaults write com.sezeryildirim.vesila SUEnableAutomaticChecks -bool false
ditto "$LAB/older/Vesila.app" "$LAB/installed/Vesila.app"
open "$LAB/installed/Vesila.app"
```

The feed override is a **test-only packaged-plist mutation before signing**, not an assumed
`defaults SUFeedURL` override. `UpdateConfiguration` requires HTTPS; HTTP won't start the updater.
No production code or tracked plist change is needed. Run `log stream --level debug --predicate
'process == "Vesila" OR subsystem BEGINSWITH "org.sparkle-project"'` in another terminal.

### (a) Older build → newer, install and relaunch

In the installed 1.0.3-test app finish onboarding, then select About → Check for Updates. Expect
1.0.4-test offered; choose the update, then install/relaunch. Expect exactly one relaunch, normal
menu operation, both activity features initially off, and About showing 1.0.4-test. Verify:

```sh
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$LAB/installed/Vesila.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$LAB/installed/Vesila.app/Contents/Info.plist"
codesign --verify --strict --verbose=2 "$LAB/installed/Vesila.app"
xcrun stapler validate "$LAB/installed/Vesila.app"
grep 'GET' "$LAB/https.log"
```

Expected: `1.0.4-test`, `10001`, successful verification, GET for appcast and ZIP. Confirm the running
process is the installed copy with `pgrep -fl Vesila.app/Contents/MacOS/Vesila`.

### (b) No-update

With that same build 10001 running and the unchanged good feed, select About → Check for Updates
again. Expect “You're up to date”, no installation/relaunch, build still `10001`. A feed GET should
appear but no new ZIP GET. Verify the build with the PlistBuddy command above.

### (c) Tampered archive rejection

Quit via Vesila's menu. Restore the older app; remove the installed test copy first so `ditto`
doesn't merge files from different versions. Keep the good feed's signature but modify a ZIP
byte after signing (same length, new URL avoids a previously cached download):

```sh
rm -rf "$LAB/installed/Vesila.app"
ditto "$LAB/older/Vesila.app" "$LAB/installed/Vesila.app"
python3 - <<'PY'
import os, xml.etree.ElementTree as E
from pathlib import Path
lab = Path(os.environ['LAB'])
data = bytearray((lab / 'good-update.zip').read_bytes())
data[len(data) // 2] ^= 1
(lab / 'feed/tampered.zip').write_bytes(data)
t = E.parse(lab / 'good-appcast.xml')
t.find('./channel/item/enclosure').set('url', 'https://localhost:8443/tampered.zip')
t.write(lab / 'feed/appcast.xml', encoding='utf-8', xml_declaration=True)
PY
shasum -a 256 "$LAB/installed/Vesila.app/Contents/MacOS/Vesila" > "$LAB/before.sha256"
open "$LAB/installed/Vesila.app"
```

Check manually, select the offered update and attempt downloading/installing. Expect Sparkle's
invalid/corrupt update error and signature failure in logs, no successful install or relaunch.
The HTTPS log must show a GET for `tampered.zip` (otherwise the rejection was not exercised).

```sh
shasum -a 256 -c "$LAB/before.sha256"
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$LAB/installed/Vesila.app/Contents/Info.plist"
cp "$LAB/good-appcast.xml" "$LAB/feed/appcast.xml"
```

Expected: checksum `OK`, build `10000`, app still launches. Do not regenerate/sign the modified ZIP.

### (d) Automatic background check without disrupting launch/onboarding

Quit the app. Keep the older app installed and restore the good feed. Enable checks and clear the
last-check timestamp so the daily interval is already overdue; Sparkle enforces a minimum interval,
so setting a tiny `SUScheduledCheckInterval` is not a reliable acceleration technique.

```sh
defaults write com.sezeryildirim.vesila SUEnableAutomaticChecks -bool true
defaults delete com.sezeryildirim.vesila SULastCheckTime 2>/dev/null || true
# For the onboarding variant run this before opening (fresh disposable user only):
# defaults delete com.sezeryildirim.vesila onboardingCompleted
open "$LAB/installed/Vesila.app"
tail -f "$LAB/https.log"
```

Do not click Check for Updates. Expect a feed GET shortly after updater launch setup, a responsive
menu with no Dock icon, no activity feature switched on, and a gentle update reminder rather than
blocked startup. Decline installation. Repeat after resetting onboarding
with `defaults delete com.sezeryildirim.vesila onboardingCompleted`; leave the welcome window open while the check
runs, then Continue. Expect onboarding to remain usable, no overlapping blocking startup prompts,
and a visible update reminder when appropriate. Record any disruption as a failure; this runbook
does not claim it has been observed. Restore the saved onboarding preference or discard the test user.

### (e) Drafts and prereleases excluded (GitHub-hosted variant)

GitHub exclusion must be exercised on an **isolated test repository**, not the production release
stream. Quit the local test app first. Continue in the same shell (with `build_test_app` defined),
set `TEST_REPO` to a disposable repository you own, and build another pair with that HTTPS feed.
The commands re-sign/notarize/staple before archiving; no signed bundle is edited later:

```sh
export TEST_REPO='OWNER/DISPOSABLE-REPO'
export TEST_FEED_URL="https://github.com/$TEST_REPO/releases/latest/download/appcast.xml"
defaults write com.sezeryildirim.vesila SUEnableAutomaticChecks -bool false
rm -rf "$LAB/older/Vesila.app" "$LAB/newer/Vesila.app" "$LAB/installed/Vesila.app"
build_test_app 1.0.3-test 10000 "$LAB/older"
build_test_app 1.0.4-test 10001 "$LAB/newer"
ditto -c -k --sequesterRsrc --keepParent "$LAB/newer/Vesila.app" "$LAB/feed/Vesila-1.0.4-test.zip"
./Scripts/make_appcast.sh "$LAB/feed/Vesila-1.0.4-test.zip" 1.0.4-test 10001 "$LAB/feed/appcast.xml"
python3 - <<'PYTHON'
import os, xml.etree.ElementTree as E
from pathlib import Path
p = Path(os.environ['LAB']) / 'feed/appcast.xml'
t = E.parse(p)
t.find('./channel/item/enclosure').set('url',
    'https://github.com/' + os.environ['TEST_REPO'] + '/releases/download/v1.0.4-test/Vesila-1.0.4-test.zip')
t.write(p, encoding='utf-8', xml_declaration=True)
PYTHON
# Use the isolated repo feed and its good ZIP; stable appcast advertises build 10001.
# --target names a commit that exists in that test repository.
gh release create v1.0.4-test "$LAB/feed/Vesila-1.0.4-test.zip" "$LAB/feed/appcast.xml" \
  --repo "$TEST_REPO" --target main --latest --title 'Stable E2E' --notes 'Test only'
curl --fail --location "https://github.com/$TEST_REPO/releases/latest/download/appcast.xml" -o "$LAB/stable.xml"
# Candidate artifacts can advertise build 10002; neither may change stable.xml.
# Copy before upload so the asset is named appcast.xml, not candidate.xml.
mkdir -p "$LAB/candidate"
python3 - <<'PY'
import os, xml.etree.ElementTree as E
from pathlib import Path
lab = Path(os.environ['LAB'])
t = E.parse(lab / 'stable.xml')
t.find('./channel/item/{http://www.andymatuschak.org/xml-namespaces/sparkle}version').text = '10002'
t.write(lab / 'candidate/appcast.xml', encoding='utf-8', xml_declaration=True)
PY
gh release create v1.0.5-beta "$LAB/candidate/appcast.xml" \
  --repo "$TEST_REPO" --target main --prerelease --title 'Prerelease E2E' --notes 'Test only'
gh release create v1.0.6-draft "$LAB/candidate/appcast.xml" \
  --repo "$TEST_REPO" --target main --draft --title 'Draft E2E' --notes 'Test only'
curl --fail --location "https://github.com/$TEST_REPO/releases/latest/download/appcast.xml" -o "$LAB/after-candidates.xml"
cmp "$LAB/stable.xml" "$LAB/after-candidates.xml"
gh api "repos/$TEST_REPO/releases/latest" --jq '[.tag_name,.draft,.prerelease]'
```

Expected: identical stable XML, `v1.0.4-test`, `false`, `false`. Run the isolated-repo older app:

```sh
ditto "$LAB/older/Vesila.app" "$LAB/installed/Vesila.app"
open "$LAB/installed/Vesila.app"
```

Use About → Check for Updates; expect only stable build 10001, install and relaunch as in (a).
Check manually again; installed build 10001 must report up to date and never offer 10002. No local server
can prove GitHub's `latest` behavior; the local run proves installation and signature enforcement.
Delete test releases/tags only in the disposable repo after recording results.

### Cleanup

Quit Vesila first. Remove the installed test copy, stop the HTTPS server, restore any preferences
changed in the disposable user and remove the test worktree. This procedure never sets a defaults
feed override; if earlier experiments did, delete that override too:

```sh
kill "$HTTPS_PID"
defaults delete com.sezeryildirim.vesila SUFeedURL 2>/dev/null || true
defaults delete com.sezeryildirim.vesila SUEnableAutomaticChecks 2>/dev/null || true
defaults delete com.sezeryildirim.vesila SULastCheckTime 2>/dev/null || true
# Remove only the throwaway Keychain account, never the production ed25519 item.
security delete-generic-password -s https://sparkle-project.org -a "$SPARKLE_KEYCHAIN_ACCOUNT"
cd "$SOURCE_REPO"
git worktree remove --force "$LAB/source"
rm -rf "$LAB"
unset SPARKLE_PUBLIC_ED_KEY SPARKLE_KEYCHAIN_ACCOUNT LAB HTTPS_PID TEST_FEED_URL TEST_REPO
mkcert -uninstall
```

Discard the disposable user (or restore its saved app preferences). Launch the production signed
app and inspect its bundled `SUFeedURL` to confirm the stable GitHub endpoint is back in use.

## Deterministic checks on Linux

```sh
for script in Scripts/*.sh; do bash -n "$script" || exit; done
shellcheck Scripts/*.sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Scripts/tests -v
git diff --check
```

The tests generate a sample feed using the same renderer with a dummy archive and dummy signature,
parse it with ElementTree, assert every required field, reject mismatched versions and keys, and
check signing order with mocked macOS tools. These fixtures are not valid release signatures.
Sparkle tools are Mach-O macOS executables and cannot execute on this Linux runner; no signing
identity, Xcode, `codesign`, `notarytool`, or macOS host is provided. macOS commands above are
maintainer-pending until recorded as executed.

If GitHub credentials are unavailable, the maintainer can deliver this branch with:

```sh
git push -u origin feature/sparkle-updates
gh pr create --repo szryldrm/vesila-mac --base main --head feature/sparkle-updates \
  --title 'Add Sparkle updates and release tooling' --body-file /path/to/reviewed-pr-description.md
```
