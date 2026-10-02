<div align="center">

<img src="app-icon.png" width="128" height="128" alt="Vesila app icon">

# Vesila

**Stay present. Stay awake.**

A native macOS menu bar utility that helps collaboration apps keep your status active while you're at your Mac, and can prevent idle system sleep when you need it.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?style=flat-square&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-F05138?style=flat-square&logo=swift&logoColor=white)
![AppKit](https://img.shields.io/badge/UI-AppKit-0A84FF?style=flat-square)
![Sparkle 2](https://img.shields.io/badge/updater-Sparkle_2-30D158?style=flat-square)

[Download latest release](https://github.com/szryldrm/vesila-mac/releases/latest)

</div>

## What Vesila does

Vesila lives entirely in the menu bar and gives you a few focused controls:

| Feature | What it does |
| --- | --- |
| **Presence** | Helps prevent apps from marking you Away while you're idle at your Mac |
| **System Awake** | Prevents idle system sleep |
| **Stay Active When Locked** | Keeps an active session running while the screen is locked when System Awake is enabled |
| **Scheduled activation** | Runs Vesila automatically on selected days and times |
| **Start on Launch** | Launches Vesila automatically when you sign in to macOS |

You can also use the main Vesila switch to turn the current session on or off, or right-click the menu bar icon for a quick toggle.

## Activation

Vesila supports two activation modes.

### Manual

Choose how long Vesila should stay active:

- 30 minutes
- 1 hour
- 2 hours
- 3 hours
- 5 hours
- Until turned off

Presence and System Awake share the same session timer.

### Scheduled

Choose the weekdays and start/end times directly in the menu bar.

Vesila evaluates the schedule when it launches and when your Mac wakes or resumes. If you manually change the active state during a scheduled window, that override applies only to the current window; the next scheduled window starts fresh.

## Presence

Presence waits until you've been genuinely idle before doing anything.

After about **4 minutes** without real keyboard or mouse input, Vesila posts a small synthetic mouse-move event at the cursor's current position. The cursor does not visibly move. While you remain idle, Vesila repeats the pulse about every **3 minutes**.

Vesila does not click, scroll, type, or read your keystrokes.

Presence requires macOS **Accessibility** permission.

## System Awake

System Awake prevents idle system sleep while it is enabled.

It uses macOS power assertions directly through IOKit. It does not prevent explicit Sleep, lid close, or user switching.

No additional permission is required.

## Stay Active When Locked

This option is available when **System Awake** is enabled.

When active, locking the screen can keep the current Vesila session running. Sleep, lid close, user switching, and session expiration still end the session.

## Installation

Download the latest signed and notarized release from:

**[GitHub Releases](https://github.com/szryldrm/vesila-mac/releases/latest)**

Open the DMG and copy **Vesila.app** to Applications.

On first launch:

1. Open Vesila from Applications.
2. Look for the cup icon in the menu bar.
3. Grant Accessibility permission if you want to use Presence.
4. Enable the features or schedule you want.

Vesila uses Sparkle for secure in-app updates. You can also check manually from **About Vesila → Check for Updates…**.

## Permissions & privacy

| Permission | Needed? | Why |
| --- | --- | --- |
| **Accessibility** | Presence only | Allows Vesila to post the harmless activity pulse |
| **Input Monitoring** | No | Vesila does not read keystrokes |
| **Screen Recording** | No | Vesila does not inspect your screen |

Vesila runs locally and does not use accounts, analytics, or telemetry.

Its network traffic is limited to update checks and update downloads through Sparkle.

## Menu bar icon

The cup shows what's active:

- **Fill** → Presence
- **Steam** → System Awake
- **Fill + steam** → both
- **Empty cup** → inactive

Stay Active When Locked does not change the icon.

## Building from source

Requirements:

- macOS 14 or later
- Swift 6
- Xcode 16 or later, or Command Line Tools

Build the app bundle from the repository root:

```sh
VESILA_ALLOW_NO_UPDATE_KEY=1 ./Scripts/build_app.sh
open .build/app/Vesila.app
```

For quick development:

```sh
swift build
swift run
```

There is no Xcode project; Vesila builds with Swift Package Manager.

## Tests

Run the full test suite with:

```sh
./Scripts/test.sh
```

To run a focused subset:

```sh
./Scripts/test.sh --filter Presence
```

## Tech

Vesila is built with:

- Swift and AppKit
- CoreGraphics for Presence
- IOKit for power assertions and lid state
- UserDefaults for preferences
- Sparkle 2 for updates
- Swift Testing

The app is menu-bar-only and has no main application window.

For maintainer update and release details, see [docs/UPDATES.md](docs/UPDATES.md).

## Requirements

- macOS 14 Sonoma or later
- Accessibility permission only if you use Presence

## License

All rights reserved. See [LICENSE](LICENSE).

## Disclaimer

Vesila is an independent project and is not affiliated with or endorsed by Microsoft. Microsoft Teams is a trademark of the Microsoft group of companies.

Vesila is intended to keep your status accurate while you're genuinely at your Mac. Use it in accordance with your organization's policies.
