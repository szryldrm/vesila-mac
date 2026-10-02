# Updates and releases

Vesila uses Sparkle 2.10.0 for in-app updates.

Production feed:

`https://github.com/szryldrm/vesila-mac/releases/latest/download/appcast.xml`

Stable releases must be non-draft and non-prerelease. Sparkle uses `BUILD_NUMBER` for update ordering, so it must always increase.

## Release notes

Before creating a release, add the new version and user-facing changes to:

`Sources/Vesila/Resources/ReleaseNotes.json`

Keep older entries. Vesila can show multiple entries when a user skips versions.

Commit and push the release notes before running the release tooling. Do not manually bump `VERSION`, `BUILD_NUMBER`, or create the release tag first.

## Maintainer setup

Release work requires:

- macOS 14+
- Xcode 16+ / Swift 6
- Developer ID Application certificate and private key in Keychain
- a configured `notarytool` Keychain profile
- Sparkle 2.10.0 tools, with `SPARKLE_BIN` pointing to its `bin` directory

`Packaging/SparklePublicEDKey` contains the production Sparkle **public** key and is intentionally tracked.

The matching private EdDSA key, Developer ID private key, Apple credentials, tokens, and notarization credentials must stay outside the repository. Sparkle signing uses the Keychain by default.

## Normal release flow

Local maintainer scripts are intentionally untracked:

- `Scripts/release.sh`
- `Scripts/deploy_github.sh`

Use this order:

1. Start from a clean, up-to-date `main`.
2. Update and commit `ReleaseNotes.json`.
3. Run the local `release.sh`. It owns the version/build bump, tests, build, signing, notarization, DMG creation, Sparkle ZIP signing, and appcast generation.
4. Verify the generated artifacts.
5. Run the local `deploy_github.sh`. It owns the release commit, tag, push, and GitHub Release publication.
6. Verify the published GitHub Release and stable appcast URL.

Expected release assets:

- `Vesila-X.Y.Z.dmg`
- `Vesila-X.Y.Z.dmg.sha256`
- `Vesila-X.Y.Z.zip`
- `appcast.xml`

The update ZIP must be created from the final signed, notarized, and stapled app. Do not modify or re-sign the app after stapling.

## Tracked release helpers

These files are safe to keep in the public repository and contain no private credentials:

- `Scripts/build_app.sh` — builds and assembles the app bundle
- `Scripts/sign_app.sh` — applies Developer ID signatures
- `Scripts/make_appcast.sh` — validates the final app and signs the update archive
- `Scripts/appcast.py` — validates metadata and renders the appcast
- `Scripts/verify_update.swift` — verifies the EdDSA archive signature
- `Scripts/test.sh` — runs the test suite

Run tests directly with:

```sh
./Scripts/test.sh
```

## Verification

After publishing a release, confirm:

```sh
curl --fail --location \
  https://github.com/szryldrm/vesila-mac/releases/latest/download/appcast.xml
```

Also confirm that the latest GitHub Release is stable and contains all expected assets.

If a published ZIP or appcast is wrong, publish a corrected higher build/version. Do not silently replace already advertised signed update bytes.

## Security rules

- Never commit private signing keys, certificates, passwords, tokens, or notarization credentials.
- Keep `BUILD_NUMBER` strictly increasing.
- Keep the production Sparkle public key stable unless performing a deliberate key migration.
- Sign → notarize → staple → archive.
- Release only artifacts produced from the final verified app.
- Never disable Sparkle signature verification to recover from a release problem.

References:

- [Sparkle publishing](https://sparkle-project.org/documentation/publishing/)
- [Sparkle security](https://sparkle-project.org/documentation/security/)
- [Sparkle 2.10.0](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0)
