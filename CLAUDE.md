# Neck Practice (internal name: Guitar Man)

SwiftUI iOS app for guitar fretboard practice, shipped on the App Store as **Neck Practice**.
The Xcode project, target, and folder are still named "Guitar Man" — don't rename them; it would break signing and App Store continuity.

## Layout
- `Guitar Man.xcodeproj` — single app target `Guitar Man`. Uses Xcode 16+ **file-system synchronized groups**: any `.swift` file placed in `Guitar Man/` is compiled automatically; never hand-edit `project.pbxproj` to add files.
- `Guitar Man/` — all source, flat (no subfolders). Files are prefixed by layer instead:
  - `NeckPracticeModels*.swift` — data + session logic (`@Observable` classes, SwiftData `@Model`s)
  - `NeckPracticeServices*.swift` — audio, pitch detection, metronome, looper, notifications
  - `NeckPracticeViews*.swift` — SwiftUI screens
  Follow this naming for new files.
- `docs/index.html` — Support & Privacy Policy page, served by GitHub Pages at https://jojolom.github.io/Neck-Practice/ (the App Store listing's support/privacy URL). Keep it accurate when the app's data handling changes.
- `NeckPracticeApp.swift` — entry point; SwiftData container for `PracticeSessionLog`, injects `AudioSettings` via `.environment`.

## Stack
Swift 5, SwiftUI, Observation (`@Observable`), SwiftData, AVFoundation, Accelerate (pitch detection), UserNotifications. iOS deployment target 26.2. No third-party dependencies.

## Build & run
```bash
xcodebuild -project "Guitar Man.xcodeproj" -scheme "Guitar Man" -destination 'generic/platform=iOS Simulator' build
```
Requires `xcode-select` to point at Xcode.app (not CommandLineTools).

## Release
- Bump `MARKETING_VERSION` (user-facing) and `CURRENT_PROJECT_VERSION` (build number) in the target's build settings before each App Store upload.
- Archive/upload is done from Xcode (Product → Archive).
- Do not change `PRODUCT_BUNDLE_IDENTIFIER` or `DEVELOPMENT_TEAM` — the live App Store listing depends on them.

## Conventions
- Prefer small, focused diffs; build after changes.
- Commit to `main` only when asked; remote is `github.com/jojolom/Neck-Practice`.
