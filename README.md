# Clipity

Clipity is a local clipboard library for iPhone and iPad. It saves text, links,
images, and files in a shared on-device database, then makes them available to
the app, widgets, Shortcuts, a share extension, and an optional keyboard.

The current app targets iOS 26 and is written in Swift 6 with SwiftUI, App
Intents, WidgetKit, Vision, Foundation Models, and SQLite. It has no third-party
runtime dependencies.

> [!IMPORTANT]
> Clipity is a personal/developer project, not an App Store-ready clipboard
> service. Its optional background listener calls a private pasteboard selector
> after checking that it exists at runtime. Apple may change or remove that
> behavior at any time, and private API use is unsuitable for App Store release.

## Features

- Captures clipboard text, web links, and images while the app can read them.
- Saves files and content sent through the share extension or Shortcuts.
- Searches clipping text, titles, filenames, and locally generated labels.
- Keeps selected clippings permanently and organizes them into folders.
- Provides authenticated App Intents for adding, finding, copying, and opening
  clippings.
- Includes privacy-safe Home Screen and Lock Screen widgets that open Clipity
  without caching clipping contents.
- Offers an optional keyboard for inserting saved text clippings.
- Generates titles and labels on device when Apple Intelligence is available.

History defaults to 500 unsaved items. Individual payloads are limited to 10 MB,
and a share batch is limited to 20 items or 20 MB. Permanent clippings are not
removed by history pruning.

## Privacy and platform limits

Clipity stores its library in the shared App Group container with complete file
protection and makes no network requests. It rejects recognized concealed or
transient pasteboard types and uses conservative checks for likely credentials,
private keys, access tokens, verification codes, credential-bearing URLs, and
payment card numbers. These checks can produce false positives and cannot detect
every unmarked sensitive value.

iOS does not provide a public clipboard-history API or a reliable source-app
identity. Foreground reads may show the system paste permission prompt.
Background monitoring uses a visible Core Location background activity session
to keep the process eligible to run; Clipity does not retain coordinates. This
does not guarantee background clipboard access. iOS can suspend or terminate the
app, and force-quitting stops monitoring.

When iOS reports a background clipboard change but withholds its contents,
Clipity posts at most one content-free notification for each new pasteboard
token. Expanding that notification lets the notification extension save the
clipboard value that is current at that moment. Copies made in between can no
longer be recovered. When contents are available, Clipity compares a persisted
SHA-256 fingerprint of the ordered payload and only sends a capture notification
when that payload actually changed; the comparison buffer never stores another
raw copy of the clipboard.

## Requirements

- Xcode 26 or later
- iOS 26 or later
- XcodeGen 2.46 or later when regenerating the project
- An Apple Development team and App Group for device builds

Simulator builds do not require a signing team. On a device, select your team in
Xcode and replace the `de.thamo.clipity` bundle identifiers and
`group.de.thamo.clipity` App Group in `project.yml` with identifiers registered
to your account. Every target must use the same App Group or it will see a
different library.

## Build and test

[![Build unsigned IPA](https://github.com/thamok/clipity/actions/workflows/build-unsigned-ipa.yml/badge.svg)](https://github.com/thamok/clipity/actions/workflows/build-unsigned-ipa.yml)

The generated Xcode project is checked in, so a fresh clone can be opened
directly:

```sh
open Clipity.xcodeproj
```

`project.yml` is the source of truth for targets and build settings. Regenerate
the project after changing it:

```sh
xcodegen generate
```

List available simulator destinations, then run the tests with one of the shown
destination IDs:

```sh
xcodebuild -project Clipity.xcodeproj -scheme Clipity -showdestinations
xcodebuild -project Clipity.xcodeproj -scheme Clipity \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' test
```

The unit suite covers storage, privacy checks, capture receipts, pruning, and
title behavior. UI tests cover the primary app interactions and App Intents.
`BackgroundCaptureTests` skips the simulator because it exercises a real
out-of-process clipboard change and notification extension on a physical device.
`ClipityTestSource` is a standalone helper app for that test; it is never
embedded in Clipity.

## Distribution artifacts

The scripts in `Scripts/` create local IPA files in the repository root. These
outputs and their build directories are ignored by Git.

```sh
./Scripts/build-signed-ipa.sh
./Scripts/build-unsigned-ipa.sh
```

The signed script uses the signing configuration selected in Xcode. The unsigned
archive is intended for a separate signing workflow, which must sign the app and
every extension with matching App Group entitlements.

GitHub Actions also builds the unsigned archive for pushes to `main`, pull
requests, and manual runs. Each run retains the IPA artifact for 14 days.

## Project layout

| Path | Purpose |
| --- | --- |
| `App/` | SwiftUI app, navigation, clipboard monitor, App Intents, and on-device intelligence |
| `Core/` | Shared models, privacy checks, content loading, notifications, and SQLite storage |
| `Keyboard/` | Optional custom keyboard extension |
| `Notification/` | Notification content extension for explicit background saves |
| `Share/` | Share extension for incoming content |
| `Widgets/` | Content-free launch widgets |
| `Resources/` | App icon and shared asset catalog |
| `Tests/` | Unit tests |
| `UITests/` | UI, App Intent, and physical-device integration tests |
| `TestSupport/` | Standalone clipboard-source app used by the device integration test |
| `project.yml` | XcodeGen project definition and shared build configuration |

`ClipStore` serializes every read-modify-write operation through SQLite so the
app and extensions cannot overwrite one another's changes. Metadata snapshots
store large image and file payloads by SHA-256 identifier; clients hydrate a
payload only when they need it. Capture receipts are committed in the same
transaction as their clippings, preventing the app, notification extension, and
Shortcuts from saving the same clipboard event more than once. The persisted
clipboard fingerprint and last observed token also coalesce repeated OS change
signals across process launches.

## License

Clipity is released under the [MIT License](LICENSE).
