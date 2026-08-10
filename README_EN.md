<p align="center">
  <img src="logo.png" width="128" alt="DropNest">
</p>

<h1 align="center">DropNest 🪺</h1>

<p align="center">
  📖 English · <a href="README.md">中文</a>
</p>

<p align="center">
  Turn your MacBook's notch into a "second desktop".<br/>
  File staging · Floating nests · Clipboard history · Media control · System HUD — all above the notch.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="License"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-black" alt="Platform">
  <img src="https://img.shields.io/badge/Swift-5.0-FA7343" alt="Swift">
  <img src="https://img.shields.io/badge/version-1.0-green" alt="Version">
  <a href="https://github.com/LuckyOneTwoThree/DropNest/actions"><img src="https://github.com/LuckyOneTwoThree/DropNest/actions/workflows/build.yml/badge.svg" alt="Build"></a>
</p>

> ⚠️ **License**: This project is derived from [boring.notch](https://github.com/TheBoredTeam/boring.notch) (GPL-3.0). Under the GPL "derivative work" clause, DropNest is likewise released under **GPL-3.0** and must retain the original license and copyright notices. See [`LICENSE`](LICENSE) and [`THIRD_PARTY_LICENSES`](THIRD_PARTY_LICENSES) for details.

---

## Core Features

### 🪺 Floating Nest

Extend file staging from the notch across the whole desktop. Each collection can independently expand into a floating nest — drag, stash, and move things around in one fluid motion.

- **Empty-nest embryo drop zone**: While dragging a file, a compact capsule-style drop indicator appears near the cursor; release to hatch it into a real nest — like "planting" a file nest on your desktop.
- **Shake to summon**: While dragging, shake the mouse horizontally and an empty nest embryo instantly appears near the pointer. Pointer-driven only, no keyboard shortcut needed.
- **Collection nests**: Files dropped in bulk auto-group into a collection; each collection can independently expand into a desktop floating nest with remembered position, ready whenever you need it.
- **Three-layer gesture separation**:
  - **Drag the title bar** → move the window
  - **Drag the empty area** → drag out all files (Finder's standard copy/move semantics)
  - **Drag a single item** → drag out only that file
- **One-click flow**: Expand all collections into desktop nests with one click, or retract them back to the notch — collection data is always preserved in the Shelf.

### 📦 Shelf

A floating storage area inside the notch — drop in to store, grab whenever you need.

- **Drop to store**: Files/folders/text/links dragged onto the notch area auto-expand and get stored.
- **Secure bookmark persistence**: Uses security-scoped bookmarks so file references survive restarts.
- **Automatic bookmark re-resolution**: Cache with a 30s TTL; automatically re-resolves after a file is renamed/moved, so stale paths are never shown.
- **Collection management**: Multiple files can be grouped into a collection; the collection card shows a count badge and supports in-place expand, dissolve, and delete.
- **Smooth batch operations**: Batch delete and clear operations run in the background, so the UI never stutters; batch removal triggers only a single UI refresh.
- **Copy vs. move**: Dragging out defaults to copy (keeps the original); toggle it off in Settings to switch to move semantics.
- **Rich context menu**: Open / Quick Look / Reveal in Finder / Share / Copy / Rename / Remove.
- **Image processing**: Remove background (cutout) / convert image format / create PDF.
- **Folder operations**: Right-click to compress directly into a zip.

### 📋 Clipboard History

A clipboard manager inside the notch that records every copy and lets you paste it back anytime.

- **Multi-type payload**: Text, RTF, HTML, images, and file URLs from a single copy are all saved; pasting back behaves identically to the original.
- **Global quick panel**: Press `⌃⌥V` to summon the quick panel at the cursor — filter by typing, navigate with arrow keys, paste with Enter, all without leaving the keyboard.
- **Optional auto-paste**: Automatically injects `⌘V` into the current app after pasting back (requires Accessibility permission).
- **Privacy guardrails**: Auto-detects one-time secrets from password managers and file-promise types; supports a configurable ignore-app list.
- **Capacity and retention**: Configure max item count, retention days, whether to save images/files, and max item size.
- **Expiry auto-cleanup**: A background scan every 10 minutes removes expired items, so long-running use doesn't accumulate junk.
- **Small-size optimization**: RTF/HTML under 4KB is stored inline, avoiding a flood of fragmented blob files for formatted text.

### 🎵 Now Playing

Expands on both sides of the notch, showing album art and a live spectrum.

- Supports any player (Apple Music, Spotify, web players, etc.) via the system-level media interface.
- Auto-collapses to a thin bar after pausing, so it never blocks screen content.
- Smart tab switching: Auto-switches the default tab based on recent activity (file staging / clipboard copy).

### 🎛️ System HUD Replacement

Replace the system-native volume/brightness/keyboard-backlight indicators with the notch HUD.

- **Three independent toggles**: Volume, screen brightness, and keyboard backlight are each controlled independently; you can mix "notch HUD + native bezel".
- **Multiple display styles**: Collapsed inline HUD (on the sides of the notch) / expanded draggable progress bar / progress bar below the notch.
- **Option-key enhancement**: Hold Option + media key for custom behavior (open Settings / show HUD / no-op).
- **CGEvent Tap interception**: Precisely intercepts media key events and suppresses the system-native bezel; requires Accessibility permission (granted at runtime).
- **Tap self-recovery**: When the system silently disables a tap after a callback timeout, DropNest detects and re-enables it immediately, plus a health check every 30s — so the "volume-key HUD suddenly stops working and needs a restart" issue never appears during long runs.
- **Audio device follow**: After switching the default output device (headphones/speakers/Bluetooth), listeners re-register automatically; volume control and HUD always follow the current device.
- **Event ordering**: The async processing path is serialized, so rapid consecutive key presses never execute out of order.

### 🔋 Battery Indicator

A battery bar inside the notch, with color that changes by state.

- Low battery red / Low power yellow / Charging green / Normal white.
- Can show percentage and charging/plugged-in icons.
- Low-battery notification (20% threshold, triggered once).

---

## Interactions

| Action | Effect |
|--------|--------|
| Hover mouse over the notch | Auto-expand the panel |
| Trackpad pinch (two fingers) | Expand / collapse the control panel |
| Drag a file onto the notch | Expand the Shelf and store it |
| Shake the mouse while dragging | Summon an empty nest embryo near the pointer |
| `⌃⌥V` | Open the clipboard quick panel |
| Media keys | Volume/brightness/keyboard-backlight adjust + HUD |
| `Esc` | Close floating nest / quick panel |

The sensing area, sensitivity, and animation duration of all interactions can be fine-tuned in Settings.

---

## Architecture Highlights

### XPC Helper Architecture

The main app stays sandboxed and calls privileged capabilities through a separate XPC Helper (non-sandboxed):

- **Screen brightness**: DisplayServices + private IOKit APIs
- **Keyboard backlight**: CoreBrightness private framework (dynamically loads `KeyboardBrightnessClient`)
- **Accessibility authorization**: XPC side checks and requests Accessibility permission

XPC communication is wrapped with `withCheckedContinuation` into async/await, with error handling to avoid permanent hangs.

### Performance & Stability

DropNest has been through two rounds of deep code review and optimization, and is stable over long runs:

- **Zero file I/O on the main thread**: All FileManager operations (deleting collections / clearing the Shelf / removing items / resolving bookmarks / clipboard image ingest) run on background threads, so dragging and scrolling never stutter.
- **Bookmark resolution cache**: `ShelfItemResolutionCache` with a 30s TTL and NSLock protection, avoiding repeated bookmark resolution and disk I/O on the main thread for `displayName`/`icon`/`identityKey`.
- **Thumbnail NSCache**: 100 entries / 256MB cap, keyed by file mtime so it rebuilds automatically after a file changes; `clearCache(for:)` matches by path prefix precisely.
- **Media-key robustness**: CGEvent tap timeout auto-recovery + 30s health check + event serialization, preventing "HUD stops working after long runtime".
- **Audio device switching**: VolumeManager listens for default output device changes, automatically unregistering old listeners and re-registering on the new device.
- **Clipboard backgrounding**: TIFF→PNG conversion, SHA256, and blob writes all run in the background; expired items auto-cleaned every 10 minutes.
- **Strict concurrency**: `SWIFT_STRICT_CONCURRENCY = targeted`, 7 UI state classes uniformly isolated with `@MainActor`, while the model layer is de-MainActor'd to support background batch encode/decode.

### Window System

- Creates borderless windows that hug the notch shape using [SkyLightWindow](https://github.com/Lakr233/SkyLightWindow), shown across Spaces.
- Floating nests use an independent NSPanel system, fully isolated from the notch window and excluded from NotchSpaceManager.
- Multi-display support: automatically detects and adapts to each screen's notch position.

### Security & Permissions

| Capability | Mechanism | Permission needed |
|------------|-----------|-------------------|
| File staging | security-scoped bookmark | None extra (within sandbox) |
| Volume read/write | CoreAudio | None extra (within sandbox) |
| Battery monitoring | IOKit.ps | None extra (within sandbox) |
| Media key interception | CGEvent Tap | Accessibility (granted at runtime) |
| Screen brightness | XPC Helper | None extra (called from XPC side) |
| Clipboard hotkey | Carbon RegisterEventHotKey | None extra |
| Auto-paste | CGEvent injection | Accessibility (optional) |

> DropNest does not require high-risk permissions like "Full Disk Access". File access goes through secure bookmarks, and the system HUD goes through Accessibility permission (granted on demand at runtime).

---

## System Requirements

| Item | Requirement |
|------|-------------|
| OS | macOS 14 Sonoma or later |
| Chip | Apple Silicon or Intel Mac |
| Build tool | Xcode 15+ (needs Swift strict concurrency support) |
| Runtime form | Sandboxed app, no SIP disabling required |

---

## Installation

### Option 1: Download the installer

Head to [Releases](https://github.com/LuckyOneTwoThree/DropNest/releases) to download the latest `.dmg`, mount it, and drag `DropNest.app` into `Applications`. Pushing a `v*` tag automatically triggers a GitHub Actions build and release.

### Option 2: Build from source

```bash
# Clone the repo
git clone https://github.com/LuckyOneTwoThree/DropNest.git
cd DropNest

# Open with Xcode and build
open DropNest.xcodeproj
# Press ⌘R to run, or ⌘B to build in Xcode
```

The build output `DropNest.app` can be taken from Xcode's `Products` group via right-click → **Show in Finder**.

### Command-line build

```bash
xcodebuild \
  -project DropNest.xcodeproj \
  -scheme DropNest \
  -configuration Release \
  -destination 'platform=macOS' \
  build
```

> First, open the project in Xcode once to generate the local Scheme.

### Build the DMG installer

```bash
cd Configuration/dmg
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python3 dmgbuild_settings.py
```

---

## User Guide

### First Launch

1. Launch **DropNest** from `Applications` (macOS may block it the first time — right-click → Open).
2. It's recommended to enable "Launch at login" in Settings.
3. If you want the system HUD replacement, enable it in Settings and grant Accessibility permission when prompted.

### File Staging

- **Drop in**: Drag a file to the notch area at the top of the screen; the panel auto-expands and stores it.
- **Bulk grouping**: Dropping multiple files at once auto-groups them into a collection.
- **Floating nest**: Click a collection card's right-click → "Show as floating nest", or click the top-bar nest button to expand all at once.
- **Retrieve**: Drag out from the Shelf = copy (default); drag the empty area from a floating nest = drag out everything.
- **Persistence**: Stored file references are recorded by secure bookmarks and remain usable after restart.

### Clipboard History

- Switch to the "Clipboard" tab in the notch panel to browse history.
- Press `⌃⌥V` anywhere to summon the quick panel — filter by typing, navigate with arrow keys, paste with Enter.
- Configure ignored apps, max item count, retention days, etc. in Settings.

### System HUD

- Open Settings → HUD, enable the master switch, and check volume/brightness/keyboard backlight as needed.
- The notch shows the HUD when you press a media key, replacing the system-native bezel.
- Turn off any category you don't need; the key is passed through to the system.

### Settings

The Settings window contains 8 pages:

| Page | Content |
|------|---------|
| General | Launch at login, menu bar icon, multi-display, screen recording hiding |
| Appearance | Notch style, shadow, corner radius, accent color |
| Media | Album art, spectrum, expand wait duration |
| Shelf | Capacity, copy/move semantics, auto-remove, drag detection area |
| Clipboard | Toggle, capacity, retention, ignored apps, hotkey, auto-paste |
| Battery | Battery bar, percentage, charging icon, low-battery notification |
| HUD | Master switch, independent volume/brightness/backlight switches, display style, Option-key behavior |
| About | Version and license |

---

## Directory Structure

```
DropNest/
├── App/                              # Main app source
│   ├── DropNestApp.swift             # @main entry + AppDelegate
│   ├── NotchViewCoordinator.swift    # Notch view coordinator
│   ├── DropNest.entitlements         # Sandbox entitlement declarations
│   ├── components/
│   │   ├── Notch/                    # Notch window, shape, spectrum, header
│   │   ├── Shelf/                    # Shelf + floating nest groups
│   │   │   ├── Models/               # ShelfItem, Bookmark
│   │   │   ├── Services/             # Drag-drop / persistence / thumbnails / image processing
│   │   │   ├── ViewModels/           # State / selection / loading
│   │   │   ├── Views/                # ShelfView, FloatingNestPanel, NestGroupCardView
│   │   │   └── FloatingNestManager.swift
│   │   ├── Clipboard/                # Clipboard history (Models/Services/ViewModels/Views)
│   │   ├── HUD/                      # System HUD (expanded / collapsed / event indicator)
│   │   ├── Battery/                  # Battery indicator view
│   │   └── Settings/                 # 8-page Settings window
│   ├── managers/                     # Volume/Brightness/Battery/Music/NotchSpace
│   ├── MediaControllers/             # NowPlaying abstraction layer
│   ├── observers/                    # DragDetector/MediaKeyInterceptor/ShakeGestureDetector
│   ├── XPCHelperClient/              # XPC client (async/await wrapper)
│   ├── models/                       # Constants, NotchViewModel, BatteryStatusViewModel
│   └── sizing/ extensions/ helpers/  # Utilities
├── DropNestXPCHelper/                # XPC Helper target (non-sandboxed)
│   ├── DropNestXPCHelper.swift       # Brightness / backlight / accessibility authorization
│   └── DropNestXPCHelper.entitlements
├── mediaremote-adapter/              # Media listener submodule
├── Configuration/dmg/                # DMG packaging config
├── DropNestTests/                    # Unit tests
└── DropNest.xcodeproj/
```

---

## Tech Stack

- **Language**: Swift 5 (strict concurrency `SWIFT_STRICT_CONCURRENCY = targeted`) + SwiftUI
- **Window**: [SkyLightWindow](https://github.com/Lakr233/SkyLightWindow) (native window that hugs the notch)
- **Media**: [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (system-level Now Playing)
- **Preferences**: [Defaults](https://github.com/sindresorhus/Defaults)
- **Launch at login**: [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern)
- **Syntax**: [swift-syntax](https://github.com/swiftlang/swift-syntax)
- **Privileged capabilities**: XPC Helper architecture (screen brightness / keyboard backlight / accessibility)
- **Media key interception**: CGEvent Tap
- **Clipboard hotkey**: Carbon RegisterEventHotKey
- **Battery monitoring**: IOKit.ps
- **Volume control**: CoreAudio

---

## FAQ

**Q: "Unable to verify developer" on launch?**
A: Right-click the app → "Open", confirm in the dialog; or click "Open Anyway" in "System Settings → Privacy & Security". Self-built versions won't hit this.

**Q: System HUD not working?**
A: HUD replacement requires Accessibility permission. After enabling it in Settings → HUD, the system will prompt for authorization; go to "System Settings → Privacy & Security → Accessibility" and allow DropNest.

**Q: Floating nest shake-summon not sensitive enough?**
A: Adjust "Shake sensitivity" and "Minimum amplitude" in Settings. Higher sensitivity means a smaller amplitude is needed.

**Q: Clipboard quick panel not showing?**
A: Confirm the hotkey is enabled in Settings → Clipboard. `⌃⌥V` may conflict with other apps; check the system shortcut settings.

**Q: Files in the Shelf won't open after restart?**
A: In rare cases a secure bookmark can become invalid (file moved/deleted). Just drag the file back in.

**Q: Volume-key HUD stops showing after long runtime?**
A: DropNest already implements CGEvent tap timeout self-recovery and a 30s health check, so this should not happen under normal conditions. If it does, confirm Accessibility permission wasn't revoked, and check whether another app is hijacking media key interception.

**Q: Volume adjustment misbehaves after switching headphones/speakers?**
A: DropNest auto-follows the default output device and re-registers listeners. If it still misbehaves, restart the app to recover.

---

## Uninstall

1. Quit DropNest (menu bar icon → Quit).
2. Drag `Applications/DropNest.app` into the Trash.
3. (Optional) Delete the preferences folder: `~/Library/Containers/com.dropnest.app/`.
4. If launch-at-login is enabled, remove DropNest from "System Settings → General → Login Items".
5. If Accessibility permission was granted, remove it from "System Settings → Privacy & Security → Accessibility".

---

## Contributing

Contributions to DropNest's development and improvement are welcome!

- 📘 **Contributing guide**: [CONTRIBUTING.md](CONTRIBUTING.md)
- 🐛 **Report issues**: [Bug Report template](.github/ISSUE_TEMPLATE/bug_report.yml)
- 💡 **Feature suggestions**: [Feature Request template](.github/ISSUE_TEMPLATE/feature_request.yml)
- 🤝 **Code of conduct**: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- 🔒 **Security vulnerabilities**: Report privately per [SECURITY.md](SECURITY.md)

---

## License

This project is released under the **GNU General Public License v3.0 (GPL-3.0)**.

- The full license text is in [`LICENSE`](LICENSE).
- A summary of third-party dependency licenses is in [`THIRD_PARTY_LICENSES`](THIRD_PARTY_LICENSES).
- Because this project is derived from the GPL-3.0 boring.notch, **you must use, modify, and distribute this software under this license**; any redistribution must include the corresponding source.

---

## Acknowledgements

- [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) — the complete concept and implementation foundation of the notch window.
- [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) — system-level media status retrieval.
- [Lakr233/SkyLightWindow](https://github.com/Lakr233/SkyLightWindow) — the native window solution that hugs the notch.
- [sindresorhus/Defaults](https://github.com/sindresorhus/Defaults) · [LaunchAtLogin-Modern](https://github.com/sindresorhus/LaunchAtLogin-Modern) — preferences storage and launch-at-login.
- [swiftlang/swift-syntax](https://github.com/swiftlang/swift-syntax) — Swift syntax support.
