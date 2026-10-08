# Guitar Man

SwiftUI iOS app for guitar fretboard practice. On the device and in the app it is called **Guitar Man**.
The App Store name is **Guitar Man: Fretboard Trainer** (set on the 1.1 draft; 1.0 was published as "Neck Practice"). The bare name "Guitar Man" is already taken on the App Store, so the store name needs the descriptor while the home-screen name stays "Guitar Man" (`CFBundleDisplayName`).
Source files keep their `NeckPractice*` prefix, and the Xcode project, target, and folder are named "Guitar Man" — don't rename them; it would break signing and App Store continuity.

## Layout
- `Guitar Man.xcodeproj` — app target `Guitar Man` plus three Screen Time extension targets (below). Uses Xcode 16+ **file-system synchronized groups**: any `.swift` file placed in `Guitar Man/` is compiled automatically; never hand-edit `project.pbxproj` to add files.
- `Guitar Man/` — all source, flat (no subfolders). Files are prefixed by layer instead:
  - `NeckPracticeModels*.swift` — data + session logic (`@Observable` classes, SwiftData `@Model`s)
  - `NeckPracticeServices*.swift` — audio, pitch detection, metronome, looper, notifications
  - `NeckPracticeViews*.swift` — SwiftUI screens
  Follow this naming for new files.
- Staff notation: `NeckPracticeModelsNotation.swift` (`SpelledPitch`, `KeySignature`, `Interval`, `NoteValue`) and `NeckPracticeViewsStaffView.swift` (shared treble staff in guitar notation, written an octave above concert). Use these for anything shown on a staff; spell notes by letter, not `Note` (which can't tell F♯ from G♭).
- Compose (`NeckPracticeModelsComposition.swift`): chords are `PlacedChord`s (start beat, length 1–4 quarter beats) in 4/4 or 3/4; `place` shortens to fit before the next chord/barline, gaps are `rests(inMeasure:)`, and every measure must add up (fuzzed in `chord-check`). It decodes the old one-note-value `slots` format.
- Compose has hidden Playback settings: in the Compose editor, tap the "Key" label 5 times quickly to show them in its settings card ("Hear Compositions" toggle + Together/Arpeggio; `CompositionPlayer` keys in UserDefaults). The toggle adds a speaker button next to Play Along. Keep it out of the changelog and store text.
- Note playback: `AudioPlayer` (`NeckPracticeServicesAudioPlayer.swift`) schedules every note on one sample-accurate timeline (`play([ScheduledNote])`). Voices: the recorded nylon guitar (`NeckPracticeServicesGuitarSamples.swift`, files in `Guitar Man/GuitarSamples/`, preloaded at launch) and the synthesized string fallback (`NeckPracticeServicesPluckedString.swift`). The recordings are the FreePats Spanish Classical Guitar (CC0, credited in About), rebuilt with `scripts/build-guitar-samples.swift` (trims, levels, measures each note's tuning into `nylon-guitar.json`); don't hand-edit the `.caf` files.
- `scripts/*-check.swift` — offline logic checks (theory, tuner, metronome, looper library, chords, note synth, guitar samples, scale study). Each file's header has the `swiftc` command; model/analyzer files they compile must stay free of SwiftUI/UIKit.
- Screen Time ("Block apps until I practice") — needs the Family Controls entitlement and the App Group `group.test.Guitar-Man`:
  - `DeviceActivityMonitor/`, `ShieldConfiguration/`, `ShieldAction/` — one extension target each (`test.Guitar-Man.<Name>`), embedded in the app. Each folder holds its Swift file, `Info.plist` (excluded from the target's sources), and `.entitlements`.
  - `ScreenTimeShared/ScreenTimeShared.swift` — compiled into the app **and** all three extensions: App Group state, shield apply/clear, the 15-min unlock (2/day). Keep it plain, `nonisolated` code (the app target defaults to MainActor, the extensions don't). `appName` there is the name shown on the shield.
  - App side: `NeckPracticeServicesScreenTime.swift` (`ScreenTimeBlocker`) and `NeckPracticeViewsBlockAppsView.swift`. Screen Time only works on a real device, not the Simulator.
- `docs/index.html` — Support & Privacy Policy page, served by GitHub Pages at https://jojolom.github.io/Neck-Practice/ (the App Store listing's support/privacy URL). Keep it accurate when the app's data handling changes.
- `NeckPracticeApp.swift` — entry point; SwiftData container for `PracticeSessionLog`, injects `AudioSettings` via `.environment`.

## Stack
Swift 5, SwiftUI, Observation (`@Observable`), SwiftData, AVFoundation, Accelerate (pitch detection), UserNotifications. iOS deployment target 26.2. One third-party dependency: TelemetryDeck (Swift package, anonymous usage analytics), used only through `Analytics` in `NeckPracticeServicesAnalytics.swift`; its App ID lives there. If what's sent changes, update the privacy policy in `docs/index.html` and the App Store privacy label.

## Build & run
```bash
xcodebuild -project "Guitar Man.xcodeproj" -scheme "Guitar Man" -destination 'generic/platform=iOS Simulator' build
```
Requires `xcode-select` to point at Xcode.app (not CommandLineTools).

## Release
- Add an entry at the top of `Changelog.entries` (`NeckPracticeModelsChangelog.swift`) for each new version — it drives the post-update "What's New" sheet and About ▸ Version History.
- Bump `MARKETING_VERSION` (user-facing version) in the target's build settings for each new App Store version; the build number is set automatically by the upload script.
- Upload to TestFlight with `scripts/upload-testflight.sh` (archives, signs via App Store Connect API key, uploads; build number = timestamp). API key config lives outside the repo in `~/.appstoreconnect/` — never copy it into the project or print it.
- Export signing is manual (`scripts/ExportOptions.plist`): the "Apple Distribution" certificate in Joe's login keychain plus four App Store profiles named "Guitar Man … App Store" (app + 3 extensions). The API key can't use Apple's cloud-managed certificate, so don't switch back to automatic. Certificate and profiles expire 2027-10-05; recreate the profiles with `scripts/asc.py POST /v1/profiles`. A new extension target needs its own profile in that plist.
- Uploading, submitting for App Review, and releasing are outward-facing: confirm with Joe before each one.
- Do not change `PRODUCT_BUNDLE_IDENTIFIER` or `DEVELOPMENT_TEAM` — the live App Store listing depends on them.

## Conventions
- Prefer small, focused diffs; build after changes.
- Commit to `main` only when asked; remote is `github.com/jojolom/Neck-Practice`.
