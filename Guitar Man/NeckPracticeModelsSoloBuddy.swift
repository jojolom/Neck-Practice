//
//  SoloBuddy.swift
//  Guitar Man
//
//  Solo Buddy: a backing track to practise pentatonic soloing over. Pick a key, one to four
//  chords (as Roman numerals, like Compose, so a preset works in any key) or the 12-bar blues,
//  a style, and a tempo; it loops on the recorded nylon guitar while you solo with the
//  pentatonic box it shows.
//
//  Every style is a pattern played on each chord's guitar shape (see ChordVoicing): which
//  strings, when, how long. So any style plays any chord in any key: fingerpicking walks the
//  shape's strings, a strum rolls across them, power chords and boogie bass lines build on the
//  root. Bars come out as `Hit`s in beats; BackingTrack turns them into sound. No UI here, so
//  scripts/solo-buddy-check.swift can check it.
//

import Foundation

// MARK: - Style

enum BackingStyle: String, Codable, CaseIterable, Identifiable {
    case fingerpicked, strummed, ballad, shuffle, rock, reggae, bossa, funk, waltz

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fingerpicked: return "Fingerpicked"
        case .strummed:     return "Strummed"
        case .ballad:       return "Ballad"
        case .shuffle:      return "Blues Shuffle"
        case .rock:         return "Rock"
        case .reggae:       return "Reggae"
        case .bossa:        return "Bossa Nova"
        case .funk:         return "Funk"
        case .waltz:        return "Waltz"
        }
    }

    var detail: String {
        switch self {
        case .fingerpicked: return "Arpeggios in eighth notes, bass note first."
        case .strummed:     return "Down, down-up, up-down-up."
        case .ballad:       return "One slow strum a bar, left to ring."
        case .shuffle:      return "A swung boogie bass line with chord stabs."
        case .rock:         return "Driving eighth-note power chords."
        case .reggae:       return "Bass on the beat, short chops on 2 and 4."
        case .bossa:        return "Bass on 1 and 3, chords off the beat."
        case .funk:         return "Tight sixteenth-note chops."
        case .waltz:        return "Oom-pah-pah, in 3/4."
        }
    }

    var beatsPerBar: Int { self == .waltz ? 3 : 4 }

    var defaultBPM: Int {
        switch self {
        case .fingerpicked: return 95
        case .strummed:     return 100
        case .ballad:       return 70
        case .shuffle:      return 90
        case .rock:         return 120
        case .reggae:       return 76
        case .bossa:        return 130
        case .funk:         return 100
        case .waltz:        return 120
        }
    }
}

// MARK: - Groove

/// Loop the chords in order, or play the 12-bar blues in the key.
enum SoloForm: String, Codable {
    case loop, twelveBar
}

/// Everything Solo Buddy plays, and the scale it suggests soloing with. Saved between visits.
struct SoloGroove: Codable, Equatable {
    var keyRoot: Note = .a
    var isMinor = true
    /// One to four chords, looped in order (ignored by the 12-bar form).
    var chords: [ChordSymbol] = [ChordSymbol(degree: 1), ChordSymbol(degree: 7), ChordSymbol(degree: 6),
                                 ChordSymbol(degree: 5, kind: .major)]
    var form: SoloForm = .loop
    var style: BackingStyle = .fingerpicked
    var bpm = 95
    /// Bars each chord lasts in a loop: 1 or 2.
    var barsPerChord = 1
    /// The pentatonic to solo with, on the key's tonic.
    var scale: PentatonicQuality = .minor
    /// The preset it came from, if it's unchanged since (for the title).
    var presetID: String? = nil
    /// The saved groove it was opened from (it may have been changed since).
    var savedID: UUID? = nil

    static let chordRange = 1...4
    static let tempoRange = 50...180

    var keySignature: KeySignature { KeySignature(root: keyRoot, isMinor: isMinor) }

    /// The same music (key, chords, style, tempo, scale), wherever each came from.
    func sameMusic(as other: SoloGroove) -> Bool {
        var a = self, b = other
        a.presetID = nil; a.savedID = nil
        b.presetID = nil; b.savedID = nil
        return a == b
    }

    /// "A Minor".
    var keyName: String { isMinor ? keySignature.minorKeyName : keySignature.majorKeyName }

    /// The key's tonic as it's spelled in the key: "B♭".
    var tonicName: String {
        let tonic = isMinor ? keySignature.minorTonic : keySignature.majorTonic
        return SpelledPitch.letterNames[tonic.letter] + SpelledPitch.accidentalSymbol(tonic.accidental)
    }

    /// "A minor pentatonic".
    var scaleName: String { "\(tonicName) \(scale.displayName.lowercased()) pentatonic" }

    func chord(_ symbol: ChordSymbol) -> CompositionChord {
        CompositionChord(symbol: symbol, keySignature: keySignature, isMinor: isMinor)
    }

    /// One time through, bar by bar.
    var bars: [ChordSymbol] {
        switch form {
        case .loop:
            let chords = Array(self.chords.prefix(Self.chordRange.upperBound))
            return chords.flatMap { Array(repeating: $0, count: min(max(barsPerChord, 1), 2)) }
        case .twelveBar:
            // In major: I7 IV7 V7. In minor: i7 iv7 and a dominant V7.
            let one = ChordSymbol(degree: 1, kind: isMinor ? .minor7 : .dominant7)
            let four = ChordSymbol(degree: 4, kind: isMinor ? .minor7 : .dominant7)
            let five = ChordSymbol(degree: 5, kind: .dominant7)
            return [one, four, one, one, four, four, one, one, five, four, one, five]
        }
    }

    /// The chord played in bar `bar` (counting on through the repeats).
    func symbol(forBar bar: Int) -> ChordSymbol {
        let bars = self.bars
        return bars.isEmpty ? ChordSymbol(degree: 1) : bars[((bar % bars.count) + bars.count) % bars.count]
    }

    var secondsPerBeat: Double { 60 / Double(min(max(bpm, Self.tempoRange.lowerBound), Self.tempoRange.upperBound)) }
    var beatsPerBar: Int { style.beatsPerBar }

    // MARK: Notes

    /// One note of the backing: when (in beats from the start of the bar, plus a strum's
    /// roll in seconds), which pitch, how long it rings (beats), and how loud.
    struct Hit: Equatable {
        var beat: Double
        var roll: Double = 0
        var midi: Int
        var beats: Double
        var gain: Float
    }

    /// What plays in bar `bar`, in the style, on the bar's chord.
    func hits(forBar bar: Int) -> [Hit] {
        Self.hits(for: chord(symbol(forBar: bar)), style: style)
    }

    static let openMidi = [64, 59, 55, 50, 45, 40]

    /// The shape a chord is played with: the best one low on the neck (open chords and barre
    /// chords up to the 7th fret), as MIDI notes low to high.
    static func shape(for chord: CompositionChord) -> [Int] {
        let shapes = ChordVoicing.find(pitchClasses: chord.pitchClasses, required: chord.requiredPitchClasses,
                                       bass: chord.bass.note.rawValue, limit: 3)
        guard let shape = shapes.first(where: { $0.highestFret <= 8 }) ?? shapes.first else {
            // No shape (shouldn't happen): the chord's notes as written.
            return chord.pitches.map(\.midi)
        }
        return shape.played.map { openMidi[$0.string] + $0.fret }
    }

    /// The root low on the neck (E2 to D♯3), for power chords and bass lines.
    static func lowRoot(of chord: CompositionChord) -> Int {
        40 + ((chord.root.note.rawValue - 4) % 12 + 12) % 12
    }

    /// The chord's 5th (perfect, diminished or augmented) above `bass`.
    static func fifth(of chord: CompositionChord, above bass: Int) -> Int {
        let root = chord.root.note.rawValue
        let fifthClass = chord.pitchClasses.first { [6, 7, 8].contains(($0 - root + 12) % 12) } ?? (root + 7) % 12
        var midi = bass + 1
        while midi % 12 != fifthClass { midi += 1 }
        return midi
    }

    /// Every note stops by the barline, so the next chord comes in clean.
    static func hits(for chord: CompositionChord, style: BackingStyle) -> [Hit] {
        let bar = Double(style.beatsPerBar)
        return pattern(for: chord, style: style).map { hit in
            var hit = hit
            hit.beats = min(hit.beats, bar - hit.beat)
            return hit
        }
    }

    private static func pattern(for chord: CompositionChord, style: BackingStyle) -> [Hit] {
        let shape = shape(for: chord)
        guard let bass = shape.first else { return [] }
        let upper = Array(shape.dropFirst())
        let top3 = Array(shape.suffix(3))
        let n = shape.count
        let bar = Double(style.beatsPerBar)
        func strum(_ notes: [Int], at beat: Double, down: Bool = true, roll: Double = 0.012,
                   beats: Double, gain: Float) -> [Hit] {
            let ordered = down ? notes : notes.reversed()
            let each = gain / Float(max(notes.count, 1)).squareRoot()
            return ordered.enumerated().map { i, midi in
                Hit(beat: beat, roll: Double(i) * roll, midi: midi, beats: beats, gain: each)
            }
        }
        func ringToEnd(from beat: Double) -> Double { max(bar - beat, 0.5) }

        switch style {
        case .fingerpicked:
            // Thumb on the bass, then fingers up and down the top strings: p i m a m i m a.
            let order = n >= 4 ? [0, n - 3, n - 2, n - 1, n - 2, n - 3, n - 2, n - 1] : [0, 1, 2, 1, 2, 1, 2, 1].map { min($0, n - 1) }
            return order.enumerated().map { i, string in
                let beat = Double(i) / 2
                return Hit(beat: beat, midi: shape[string], beats: ringToEnd(from: beat), gain: string == 0 ? 0.9 : 0.6)
            }

        case .strummed:
            // D . D U . U D U
            let pattern: [(beat: Double, down: Bool)] = [(0, true), (1, true), (1.5, false), (2.5, false), (3, true), (3.5, false)]
            return pattern.flatMap { hit in
                hit.down
                    ? strum(shape, at: hit.beat, beats: hit.beat == 3 ? ringToEnd(from: 3) : 1.2, gain: hit.beat == 0 ? 1.0 : 0.85)
                    : strum(Array(shape.suffix(4)), at: hit.beat, down: false, roll: 0.01, beats: 0.9, gain: 0.6)
            }

        case .ballad:
            // A slow strum on 1 left to ring, and the top strings picked gently on 3.
            return strum(shape, at: 0, roll: 0.03, beats: bar, gain: 0.95)
                + top3.enumerated().map { i, midi in
                    let beat = 2 + Double(i) * 0.5
                    return Hit(beat: beat, midi: midi, beats: ringToEnd(from: beat), gain: 0.4)
                }

        case .shuffle:
            // Swung eighths of the root with its 5th, then its 6th (the boogie), and a chord stab on 2 and 4.
            let root = lowRoot(of: chord)
            let fifth = fifth(of: chord, above: root)
            var hits: [Hit] = []
            for beat in 0..<4 {
                let partner = beat % 2 == 0 ? fifth : root + 9
                for (offset, gain) in [(0.0, Float(0.6)), (2.0 / 3, Float(0.45))] {
                    let at = Double(beat) + offset
                    hits += [Hit(beat: at, midi: root, beats: 0.55, gain: gain), Hit(beat: at, midi: partner, beats: 0.55, gain: gain)]
                }
                if beat % 2 == 1 { hits += strum(top3, at: Double(beat), roll: 0.006, beats: 0.35, gain: 0.55) }
            }
            return hits

        case .rock:
            // Palm-muted power chords (root, 5th, octave) on every eighth, accents on the beat.
            let root = lowRoot(of: chord)
            let fifth = fifth(of: chord, above: root)
            return (0..<8).flatMap { i in
                strum([root, fifth, root + 12], at: Double(i) / 2, roll: 0.006, beats: 0.42, gain: i % 2 == 0 ? 0.95 : 0.7)
            }

        case .reggae:
            // Bass on 1 and 3, short upper-string chops on 2 and 4.
            return [Hit(beat: 0, midi: bass, beats: 1.4, gain: 0.85), Hit(beat: 2, midi: bass, beats: 1.4, gain: 0.75)]
                + strum(top3, at: 1, down: false, roll: 0.006, beats: 0.2, gain: 0.7)
                + strum(top3, at: 3, down: false, roll: 0.006, beats: 0.2, gain: 0.7)

        case .bossa:
            // Thumb: root on 1, 5th on 3. Fingers: the upper notes off the beat.
            let fifth = fifth(of: chord, above: bass)
            let pluck = upper.isEmpty ? top3 : Array(upper.suffix(3))
            return [Hit(beat: 0, midi: bass, beats: 1.8, gain: 0.8), Hit(beat: 2, midi: fifth, beats: 1.8, gain: 0.7)]
                + [0.0, 1.5, 3.0].flatMap { strum(pluck, at: $0, roll: 0.004, beats: 0.9, gain: 0.55) }

        case .funk:
            // Sixteenth chops on the top strings, with the bass on 1.
            let chops: [(beat: Double, gain: Float)] = [(0, 0.8), (0.75, 0.55), (1.5, 0.65), (2, 0.8), (2.75, 0.55), (3.25, 0.5), (3.5, 0.65)]
            return [Hit(beat: 0, midi: bass, beats: 0.5, gain: 0.8)]
                + chops.flatMap { strum(top3, at: $0.beat, down: Int($0.beat * 4) % 2 == 0, roll: 0.004, beats: 0.16, gain: $0.gain) }

        case .waltz:
            // Bass on 1, the rest of the chord on 2 and 3.
            let rest = upper.isEmpty ? shape : upper
            return [Hit(beat: 0, midi: bass, beats: 1, gain: 0.85)]
                + strum(rest, at: 1, roll: 0.008, beats: 0.8, gain: 0.6)
                + strum(rest, at: 2, roll: 0.008, beats: 0.8, gain: 0.6)
        }
    }
}

// MARK: - Presets

struct SoloPreset: Identifiable {
    enum Group: String, CaseIterable {
        case minor = "Minor Keys"
        case blues = "Blues"
        case major = "Major Keys"

        /// For a three-way switch: "Minor", "Blues", "Major".
        var shortName: String {
            switch self {
            case .minor: return "Minor"
            case .blues: return "Blues"
            case .major: return "Major"
            }
        }
    }

    let id: String
    let name: String
    let detail: String
    let group: Group
    let groove: SoloGroove

    private init(_ id: String, _ name: String, _ detail: String, _ group: Group, key: Note, minor: Bool,
                 _ chords: [ChordSymbol], form: SoloForm = .loop, style: BackingStyle, bpm: Int,
                 bars: Int = 1, scale: PentatonicQuality) {
        self.id = id
        self.name = name
        self.detail = detail
        self.group = group
        groove = SoloGroove(keyRoot: key, isMinor: minor, chords: chords.isEmpty ? [ChordSymbol(degree: 1)] : chords,
                            form: form, style: style, bpm: bpm, barsPerChord: bars, scale: scale, presetID: id)
    }

    private static func c(_ degree: Int, _ kind: ChordKind = .triad, shift: Int = 0) -> ChordSymbol {
        ChordSymbol(degree: degree, shift: shift, kind: kind)
    }

    static let all: [SoloPreset] = [
        // Minor keys: minor pentatonic on the tonic.
        SoloPreset("spanish", "Spanish Nights", "Flamenco's falling line, fingerpicked: i–VII–VI–V.", .minor,
                   key: .a, minor: true, [c(1), c(7), c(6), c(5, .major)], style: .fingerpicked, bpm: 95, scale: .minor),
        SoloPreset("moody-ballad", "Moody Ballad", "Slow and open: i–VI–III–VII.", .minor,
                   key: .a, minor: true, [c(1), c(6), c(3), c(7)], style: .ballad, bpm: 70, scale: .minor),
        SoloPreset("rock-anthem", "Rock Anthem", "Power chords in E minor: i–VI–VII–i.", .minor,
                   key: .e, minor: true, [c(1), c(6), c(7), c(1)], style: .rock, bpm: 120, scale: .minor),
        SoloPreset("latin", "Latin Groove", "A two-chord Dorian vamp: i7–IV7.", .minor,
                   key: .a, minor: true, [c(1, .minor7), c(4, .dominant7)], style: .bossa, bpm: 110, bars: 2, scale: .minor),
        SoloPreset("funk-vamp", "One-Chord Funk", "Sixteenth chops on one minor 7th: all yours.", .minor,
                   key: .e, minor: true, [c(1, .minor7)], style: .funk, bpm: 100, scale: .minor),
        SoloPreset("minor-reggae", "Minor Reggae", "Laid back on i and iv, two bars each.", .minor,
                   key: .a, minor: true, [c(1), c(4)], style: .reggae, bpm: 76, bars: 2, scale: .minor),
        SoloPreset("jazz-minor", "Jazz Minor", "The minor ii–V–i, bossa style.", .minor,
                   key: .a, minor: true, [c(2, .seventh), c(5, .dominant7), c(1, .minor7), c(1, .minor7)],
                   style: .bossa, bpm: 120, scale: .minor),
        SoloPreset("desert", "Desert Drone", "Exotic and dark: i and its half-step neighbour, ♭II.", .minor,
                   key: .e, minor: true, [c(1), c(2, .major, shift: -1)], style: .fingerpicked, bpm: 90, bars: 2, scale: .minor),
        SoloPreset("minor-waltz", "Minor Waltz", "A haunting 3/4: i–iv–V–i.", .minor,
                   key: .d, minor: true, [c(1), c(4), c(5, .major), c(1)], style: .waltz, bpm: 110, scale: .minor),

        // Blues: minor pentatonic over dominant 7ths, the classic sound.
        SoloPreset("twelve-bar", "12-Bar Blues", "I7, IV7 and V7 with a shuffle. Solo with the minor pentatonic.", .blues,
                   key: .a, minor: false, [], form: .twelveBar, style: .shuffle, bpm: 90, scale: .minor),
        SoloPreset("slow-blues", "Slow Blues", "Twelve bars, slow and heavy, in E.", .blues,
                   key: .e, minor: false, [], form: .twelveBar, style: .shuffle, bpm: 62, scale: .minor),
        SoloPreset("minor-blues", "Minor Blues", "The twelve bars in minor: i7, iv7 and V7.", .blues,
                   key: .a, minor: true, [], form: .twelveBar, style: .ballad, bpm: 72, scale: .minor),
        SoloPreset("funky-dominant", "Funky Dominant", "One dominant 7th to wail over with the minor pentatonic.", .blues,
                   key: .e, minor: false, [c(1, .dominant7)], style: .funk, bpm: 104, scale: .minor),
        SoloPreset("mixolydian-rock", "Classic Rock", "I–♭VII–IV–I: rock's favourite borrowed chord.", .blues,
                   key: .a, minor: false, [c(1), c(7, .major, shift: -1), c(4), c(1)], style: .rock, bpm: 120, scale: .minor),

        // Major keys: major pentatonic on the tonic.
        SoloPreset("pop-anthem", "Pop Anthem", "The four chords: I–V–vi–IV.", .major,
                   key: .g, minor: false, [c(1), c(5), c(6), c(4)], style: .strummed, bpm: 100, scale: .major),
        SoloPreset("sunny", "Sunny Two-Chord", "Back and forth between I and IV.", .major,
                   key: .d, minor: false, [c(1), c(4)], style: .strummed, bpm: 110, bars: 2, scale: .major),
        SoloPreset("soul-ballad", "Soul Ballad", "Smooth 7ths: Imaj7–vi7–ii7–V7.", .major,
                   key: .c, minor: false, [c(1, .seventh), c(6, .seventh), c(2, .seventh), c(5, .seventh)],
                   style: .ballad, bpm: 68, scale: .major),
        SoloPreset("island", "Island Reggae", "Sunshine chops: I–IV–V–IV.", .major,
                   key: .g, minor: false, [c(1), c(4), c(5), c(4)], style: .reggae, bpm: 78, scale: .major),
        SoloPreset("bossa", "Bossa ii–V–I", "Smooth jazz in C: ii7–V7–Imaj7.", .major,
                   key: .c, minor: false, [c(2, .seventh), c(5, .seventh), c(1, .seventh), c(1, .seventh)],
                   style: .bossa, bpm: 130, scale: .major),
        SoloPreset("country-waltz", "Country Waltz", "I–IV–V–I in 3/4.", .major,
                   key: .g, minor: false, [c(1), c(4), c(5), c(1)], style: .waltz, bpm: 120, scale: .major),
        SoloPreset("folk", "Folk Picking", "I–vi–IV–V, fingerpicked.", .major,
                   key: .c, minor: false, [c(1), c(6), c(4), c(5)], style: .fingerpicked, bpm: 92, scale: .major),
    ]

    static func preset(_ id: String?) -> SoloPreset? { all.first { $0.id == id } }
}

// MARK: - BarClock

/// Hands out bars back to back on AudioPlayer's timeline, a little ahead of when they're due,
/// so the backing never drifts: each bar starts exactly where the last one ended, and a new
/// tempo (`framesPerBar`) applies from the next bar handed out.
struct BarClock {

    struct Bar: Equatable {
        let index: Int
        let frame: Int64
        let frames: Int64
    }

    private(set) var nextIndex = 0
    private(set) var nextFrame: Int64

    init(firstBarFrame: Int64) {
        nextFrame = firstBarFrame
    }

    /// The bars that start before `horizon` and haven't been handed out yet.
    mutating func bars(dueBy horizon: Int64, framesPerBar: Int64) -> [Bar] {
        var bars: [Bar] = []
        while nextFrame < horizon {
            let bar = Bar(index: nextIndex, frame: nextFrame, frames: max(framesPerBar, 1))
            bars.append(bar)
            nextIndex += 1
            nextFrame += bar.frames
        }
        return bars
    }

    /// Which of `bars` is sounding at `frame`, and how far into it (0–1); nil before the first.
    func position(at frame: Int64, in bars: [Bar]) -> (index: Int, fraction: Double)? {
        guard let bar = bars.last(where: { $0.frame <= frame }) else { return nil }
        return (bar.index, min(Double(frame - bar.frame) / Double(bar.frames), 1))
    }
}

// MARK: - Saved grooves

/// A groove you saved, by name.
struct SavedGroove: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var groove: SoloGroove
    var savedAt = Date()

    /// The groove ready to play: it remembers it came from here.
    var playable: SoloGroove {
        var groove = self.groove
        groove.presetID = nil
        groove.savedID = id
        return groove
    }
}

/// Saved grooves, newest first, kept in UserDefaults.
enum SavedGrooves {
    static let key = "soloBuddy.savedGrooves"

    /// Where 1.5's TestFlight builds kept the one groove you'd made ("Your Groove").
    static let oldYourGrooveKey = "soloBuddy.myGroove"

    static func load(_ defaults: UserDefaults = .standard) -> [SavedGroove] {
        var saved = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([SavedGroove].self, from: $0) } ?? []
        // Your Groove from a TestFlight build becomes a saved groove, once.
        if let data = defaults.data(forKey: oldYourGrooveKey) {
            if let groove = try? JSONDecoder().decode(SoloGroove.self, from: data),
               !saved.contains(where: { $0.groove.sameMusic(as: groove) }) {
                var music = groove
                music.presetID = nil
                music.savedID = nil
                saved.append(SavedGroove(name: unusedName("My Groove", in: saved), groove: music))
                store(saved, defaults)
            }
            defaults.removeObject(forKey: oldYourGrooveKey)
        }
        return saved.sorted { $0.savedAt > $1.savedAt }
    }

    static func store(_ saved: [SavedGroove], _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: key) }
    }

    /// `base`, or "base 2", "base 3"… if a saved groove already has that name.
    static func unusedName(_ base: String, in saved: [SavedGroove]) -> String {
        let names = Set(saved.map(\.name))
        guard names.contains(base) else { return base }
        var number = 2
        while names.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }
}
