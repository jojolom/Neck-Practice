//
//  Changelog.swift
//  Neck Practice
//
//  The high-level changelog shown in About ▸ Version History, and the "What's New" sheet that
//  appears once after an update. To ship a new version, add an entry at the TOP of
//  `Changelog.entries` (newest first) with the same version as `MARKETING_VERSION`.
//

import Foundation

// MARK: - Data

struct ChangelogItem: Identifiable {
    /// SF Symbol name.
    let symbol: String
    let title: String
    let detail: String

    var id: String { title }
}

struct ChangelogEntry: Identifiable {
    let version: String
    /// Shown to people, e.g. "October 2026".
    let released: String
    /// When it shipped, used to tell existing users from fresh installs (see `WhatsNewTracker`).
    let releasedOn: DateComponents
    let items: [ChangelogItem]

    var id: String { version }
}

enum Changelog {

    /// Newest first.
    static let entries: [ChangelogEntry] = [
        ChangelogEntry(
            version: "1.5",
            released: "October 2026",
            releasedOn: DateComponents(year: 2026, month: 10, day: 20),
            items: [
                ChangelogItem(symbol: "guitars.fill", title: "Solo Buddy",
                              detail: "A backing track to practise your soloing over. Pick a key and up to four chords, or the 12-bar blues, choose a style from fingerpicked to funk, and solo along with the pentatonic box it shows, in any of its five positions."),
                ChangelogItem(symbol: "music.note.list", title: "21 grooves to jam over",
                              detail: "Presets from Spanish Nights and Rock Anthem to Slow Blues, Island Reggae and a bossa ii–V–I, each playable in any key. Or tap Make Your Own and build a groove from scratch, chord by chord."),
                ChangelogItem(symbol: "speaker.wave.2", title: "Hear your compositions",
                              detail: "Turn on Hear Compositions in Compose Settings (the ⋯ menu) and a speaker button plays your piece on the guitar, chords and melody, before you play along."),
                ChangelogItem(symbol: "sparkles.rectangle.stack", title: "A tour of Compose",
                              detail: "A quick walkthrough lights up each part of the editor. It opens when you start Compose until you turn it off, and you can take it again from Compose Settings."),
                ChangelogItem(symbol: "music.quarternote.3", title: "A tidier Compose",
                              detail: "Chord names and numerals line up on the staff like a lead sheet, the key and time fold away to give the staff room, and new compositions get names of their own."),
            ]
        ),
        ChangelogEntry(
            version: "1.4",
            released: "October 2026",
            releasedOn: DateComponents(year: 2026, month: 10, day: 14),
            items: [
                ChangelogItem(symbol: "hand.point.up.left", title: "See where to play each chord",
                              detail: "Long-press a chord in Compose for a chord chart of where to play it. Play Along shows the shape for each chord as you go, with other spots on the neck a tap away."),
                ChangelogItem(symbol: "music.note", title: "More chords to compose with",
                              detail: "Tap a numeral for its 7th and sus chords (and the major V in minor keys), swipe for borrowed and secondary chords like ♭VII, iv and V/V, and long-press a chord to invert it."),
                ChangelogItem(symbol: "music.quarternote.3", title: "Write a melody",
                              detail: "Switch Compose to Melody to put single notes over your chords, from eighth notes to whole notes, sharps and flats included. Play Along can listen for it note by note."),
                ChangelogItem(symbol: "music.note.list", title: "Start from a progression",
                              detail: "Begin from the pop progression, a jazz ii–V–I, a 12-bar blues and more, in any key. Compositions can now run to 16 measures."),
                ChangelogItem(symbol: "arrow.uturn.backward", title: "Quicker editing",
                              detail: "Undo and Redo, copy a measure into the next one, or clear it."),
                ChangelogItem(symbol: "hand.raised", title: "Take your time",
                              detail: "After you answer, the games now wait for you to tap Next, so you can take in the answer first. Prefer the old pace? Choose After Answering in any game's Settings."),
                ChangelogItem(symbol: "book", title: "How to Compose",
                              detail: "A full guide to Compose, from Roman numerals to borrowed chords, in its ⋯ menu."),
                ChangelogItem(symbol: "metronome", title: "A louder metronome",
                              detail: "The click is brighter and fuller, so it's easier to hear over your guitar, in the Metronome and in Scale Study."),
                ChangelogItem(symbol: "arrow.left.arrow.right", title: "Scale Study string pairs",
                              detail: "Each round plays a scale and its relative on one string, then the parallel scale and its relative on the other."),
            ]
        ),
        ChangelogEntry(
            version: "1.3",
            released: "October 2026",
            releasedOn: DateComponents(year: 2026, month: 10, day: 8),
            items: [
                ChangelogItem(symbol: "chart.bar", title: "Anonymous usage statistics",
                              detail: "The app now counts, anonymously, how many people use it and which features they open, so we know what to improve next. Nothing personal is ever collected: no names, recordings, or compositions."),
            ]
        ),
        ChangelogEntry(
            version: "1.2",
            released: "October 2026",
            releasedOn: DateComponents(year: 2026, month: 10, day: 6),
            items: [
                ChangelogItem(symbol: "music.note.house", title: "Compose",
                              detail: "Drag Roman numerals onto a staff to write your own chord progressions in any key, in 4/4 or 3/4, mixing quarter, half, dotted half, and whole notes. Save them, and play them while the app listens and marks each chord."),
                ChangelogItem(symbol: "arrow.up.and.down", title: "Interval Trainer",
                              detail: "Name the interval on the staff in any key, then find it on the neck. Bonus rounds on inversions and compound intervals."),
                ChangelogItem(symbol: "circle.hexagongrid", title: "Modes",
                              detail: "A Modes reference: what each mode is, how it differs from major or minor, and how to play it. Plus a Mode Quiz."),
                ChangelogItem(symbol: "music.note.list", title: "Triads on the staff",
                              detail: "The Triad Trainer now writes every shape's notes on the staff, too."),
                ChangelogItem(symbol: "speaker.wave.2", title: "A real guitar sound",
                              detail: "Every note the app plays is now a recorded nylon-string guitar, exactly in tune, with chords and scales in tight time."),
            ]
        ),
        ChangelogEntry(
            version: "1.1",
            released: "October 2026",
            releasedOn: DateComponents(year: 2026, month: 10, day: 4),
            items: [
                ChangelogItem(symbol: "tuningfork", title: "Steadier tuner",
                              detail: "The low E string holds steady now, and you can tap a string to lock the tuner to it."),
                ChangelogItem(symbol: "waveform", title: "Looper upgrades",
                              detail: "A 3-2-1 count-in before every recording, overdubs that line up with the loop, and a library to save layers and add them back later."),
                ChangelogItem(symbol: "bell.badge", title: "Smarter reminders",
                              detail: "Reminders skip days you've already practiced, mention your streak, and nudge you in the evening if it's on the line."),
                ChangelogItem(symbol: "lock.shield", title: "Block apps until you practice",
                              detail: "Cover distracting apps until today's session is done, with a 15-minute unlock if you need it."),
                ChangelogItem(symbol: "music.quarternote.3", title: "Scale Study fix",
                              detail: "Scales now follow the correct 6th and 5th string pattern."),
                ChangelogItem(symbol: "sparkles", title: "A new name",
                              detail: "Neck Practice is now Guitar Man."),
            ]
        ),
        ChangelogEntry(
            version: "1.0",
            released: "June 2026",
            releasedOn: DateComponents(year: 2026, month: 6, day: 17),
            items: [
                ChangelogItem(symbol: "flame", title: "Daily Practice",
                              detail: "Build a routine, follow it step by step with timers and audio cues, and keep your streak and monthly heatmap going."),
                ChangelogItem(symbol: "scope", title: "Six fretboard trainers",
                              detail: "Note Guesser, Triad Trainer, Pentatonic Trainer, Sight Reading, Scale Study, and Roman Numerals."),
                ChangelogItem(symbol: "book", title: "Reference tools",
                              detail: "Circle of Fifths, scale and pentatonic shapes, diatonic chords, and a Fretboard Explorer."),
                ChangelogItem(symbol: "tuningfork", title: "Tuner, metronome, and looper",
                              detail: "A chromatic tuner, a metronome with time signatures, and an audio looper for solo practice."),
                ChangelogItem(symbol: "lock", title: "Private by design",
                              detail: "No accounts, ads, or subscriptions. Everything stays on your device."),
            ]
        ),
    ]

    /// The version in Info.plist (`MARKETING_VERSION`).
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    static func entry(for version: String) -> ChangelogEntry? {
        entries.first { $0.version == version }
    }
}

// MARK: - When to show "What's New"

enum WhatsNewTracker {

    private static let key = "whatsNew.lastSeenVersion"

    /// The entry to present at this launch, or nil.
    ///
    /// - Updated from a version we recorded → show the new version's notes once.
    /// - Nothing recorded (1.0 never recorded one) → show only if the app was installed before
    ///   this version came out, i.e. an existing user who just updated. Fresh installs get nothing:
    ///   they haven't seen anything "new" yet.
    static func entryToPresent(
        currentVersion: String = Changelog.currentVersion,
        installDate: Date? = installDate(),
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) -> ChangelogEntry? {
        guard let entry = Changelog.entry(for: currentVersion) else { return nil }
        let lastSeen = defaults.string(forKey: key)

        if lastSeen == currentVersion { return nil }
        if lastSeen != nil { return entry }

        guard let installDate, let shipped = calendar.date(from: entry.releasedOn) else { return nil }
        return installDate < shipped ? entry : nil
    }

    /// Remember that this version's notes were handled (shown, or not applicable).
    static func markSeen(version: String = Changelog.currentVersion, defaults: UserDefaults = .standard) {
        defaults.set(version, forKey: key)
    }

    /// When this app was first installed: the Documents folder is created at install and survives updates.
    static func installDate() -> Date? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let attributes = try? FileManager.default.attributesOfItem(atPath: documents.path)
        else { return nil }
        return attributes[.creationDate] as? Date
    }
}
