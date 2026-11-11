//
//  BluesBuddy.swift
//  Guitar Man
//
//  Blues Buddy: a blues partner to solo over. Pick a key, a form (the 12-bar and its cousins,
//  or one chord), a feel and a tempo, and it plays the way a guitarist comps a blues alone:
//  a picked bass line that keeps the time, a chord or a triad dropped in here and there, and
//  short pentatonic fills where a singer would leave room. Each of the three has its own
//  switch.
//
//  The fretboard shows what to solo with on the key's root, in one area of the neck: the minor
//  pentatonic, the major one, the blues scale (minor with the ♭5), or both pentatonics at once
//  with the notes that differ told apart. Or it follows the chords (`followsChords`), changing
//  with each bar by one of two rules. Fills are made from what's showing.
//
//  Nothing repeats: every bar is made up from a seed and its number (`bar(_:seed:)`), so one
//  take differs from the next and from one chorus to the next, yet the same seed always gives
//  the same bar (BackingTrack asks a bar at a time, and scripts/blues-buddy-check.swift can
//  check thousands). The dice are weighted so it sounds played, not shuffled: one bass pattern
//  for a four-bar line, fills at the ends of lines, a turnaround before the form comes round,
//  and chords that keep out of a fill's way. No UI here.
//

import Foundation

// MARK: - Form

enum BluesForm: String, Codable, CaseIterable, Identifiable {
    case twelveBar, quickChange, minorTwelveBar, eightBar, vamp

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .twelveBar:      return "12-Bar"
        case .quickChange:    return "Quick-Change 12-Bar"
        case .minorTwelveBar: return "Minor 12-Bar"
        case .eightBar:       return "8-Bar"
        case .vamp:           return "One-Chord Vamp"
        }
    }

    var detail: String {
        switch self {
        case .twelveBar:      return "Four bars of I, then IV, I, V, IV, I and a turnaround."
        case .quickChange:    return "The 12-bar with a quick trip to IV in bar 2."
        case .minorTwelveBar: return "The twelve bars in a minor key: i7, iv7 and V7."
        case .eightBar:       return "The short form: I, V, IV, IV, then I, V, I, V."
        case .vamp:           return "One dominant 7th, round and round."
        }
    }

    var isMinor: Bool { self == .minorTwelveBar }

    /// The scale degree of each bar's chord, one time through.
    var degrees: [Int] {
        switch self {
        case .twelveBar:                    return [1, 1, 1, 1, 4, 4, 1, 1, 5, 4, 1, 5]
        case .quickChange, .minorTwelveBar: return [1, 4, 1, 1, 4, 4, 1, 1, 5, 4, 1, 5]
        case .eightBar:                     return [1, 5, 4, 4, 1, 5, 1, 5]
        case .vamp:                         return [1]
        }
    }
}

// MARK: - Feel

enum BluesFeel: String, Codable, CaseIterable, Identifiable {
    case shuffle, slow, straight

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .shuffle:  return "Shuffle"
        case .slow:     return "Slow Blues"
        case .straight: return "Straight"
        }
    }

    var detail: String {
        switch self {
        case .shuffle:  return "Swung eighths with a boogie bounce."
        case .slow:     return "A slow 12/8: three to every beat, and lots of room."
        case .straight: return "Even eighths, for rock and funky blues."
        }
    }

    var defaultBPM: Int {
        switch self {
        case .shuffle:  return 95
        case .slow:     return 60
        case .straight: return 105
        }
    }

    /// Where the eighth after the beat falls, as a part of the beat: halfway, or swung late.
    var offbeat: Double { self == .straight ? 0.5 : 2.0 / 3 }

    /// The places in a bar a fill's notes can go, in beats: eighths (swung in a shuffle), or
    /// the triplets of a slow blues.
    var slots: [Double] {
        switch self {
        case .straight, .shuffle: return (0..<8).map { Double($0 / 2) + ($0 % 2 == 1 ? offbeat : 0) }
        case .slow:               return (0..<12).map { Double($0) / 3 }
        }
    }
}

// MARK: - Scale

/// What Blues Buddy's fretboard shows on a root.
enum BluesScale: String, Codable, CaseIterable, Identifiable {
    case minor, major, blues, both

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .minor: return "Minor"
        case .major: return "Major"
        case .blues: return "Blues"
        case .both:  return "Both"
        }
    }

    /// Its notes, in half steps above the root.
    var steps: Set<Int> {
        switch self {
        case .minor: return [0, 3, 5, 7, 10]
        case .major: return [0, 2, 4, 7, 9]
        case .blues: return [0, 3, 5, 6, 7, 10]
        case .both:  return [0, 2, 3, 4, 5, 7, 9, 10]
        }
    }

    /// The ones that suit a minor blues: the major pentatonic's 3rd fights its chords.
    static let forMinorBlues: [BluesScale] = [.minor, .blues]
}

/// How the fretboard follows the chords.
enum BluesFollowRule: String, Codable, CaseIterable, Identifiable {
    /// On the key's root throughout: major pentatonic over I, minor over IV and V.
    case tonic
    /// Each chord's own pentatonic, on the chord's root.
    case chord

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tonic: return "Major on I, Minor on IV & V"
        case .chord: return "Each Chord's Own"
        }
    }

    var detail: String {
        switch self {
        case .tonic: return "Stays on the key's root: the major pentatonic over the I chord, the minor over IV and V."
        case .chord: return "Moves with the chords: each one's own pentatonic, on its root, in the same part of the neck."
        }
    }
}

// MARK: - Groove

/// Everything Blues Buddy plays, and the scale it shows. Saved between visits.
struct BluesGroove: Codable, Equatable {
    var keyRoot: Note = .a
    var form: BluesForm = .twelveBar
    var feel: BluesFeel = .shuffle
    var bpm = 95
    /// What it plays. With all three off it still picks the bass.
    var bassPicking = true
    var chordStabs = true
    var fills = true
    /// What to solo with, on the key's tonic (minor or blues in a minor blues).
    var scale: BluesScale = .minor
    /// The fretboard changes with the chords instead, by `followRule`.
    var followsChords = false
    var followRule: BluesFollowRule = .tonic
    /// The preset it came from, if it's unchanged since (for the title).
    var presetID: String? = nil
    /// The saved groove it was opened from (it may have been changed since).
    var savedID: UUID? = nil

    static let tempoRange = 40...160
    static let beatsPerBar = 4

    init(keyRoot: Note = .a, form: BluesForm = .twelveBar, feel: BluesFeel = .shuffle, bpm: Int? = nil,
         bassPicking: Bool = true, chordStabs: Bool = true, fills: Bool = true,
         scale: BluesScale = .minor, followsChords: Bool = false, followRule: BluesFollowRule = .tonic,
         presetID: String? = nil, savedID: UUID? = nil) {
        self.keyRoot = keyRoot
        self.form = form
        self.feel = feel
        self.bpm = bpm ?? feel.defaultBPM
        self.bassPicking = bassPicking
        self.chordStabs = chordStabs
        self.fills = fills
        self.scale = form.isMinor && !BluesScale.forMinorBlues.contains(scale) ? .minor : scale
        self.followsChords = followsChords
        self.followRule = followRule
        self.presetID = presetID
        self.savedID = savedID
    }

    private enum CodingKeys: String, CodingKey {
        case keyRoot, form, feel, bpm, bassPicking, chordStabs, fills, scale, followsChords, followRule, presetID, savedID
    }

    /// Every field has a default, so a groove saved by an older version still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyRoot = (try? c.decodeIfPresent(Note.self, forKey: .keyRoot)) ?? .a
        form = (try? c.decodeIfPresent(BluesForm.self, forKey: .form)) ?? .twelveBar
        feel = (try? c.decodeIfPresent(BluesFeel.self, forKey: .feel)) ?? .shuffle
        bpm = (try? c.decodeIfPresent(Int.self, forKey: .bpm)) ?? feel.defaultBPM
        bassPicking = (try? c.decodeIfPresent(Bool.self, forKey: .bassPicking)) ?? true
        chordStabs = (try? c.decodeIfPresent(Bool.self, forKey: .chordStabs)) ?? true
        fills = (try? c.decodeIfPresent(Bool.self, forKey: .fills)) ?? true
        let saved = (try? c.decodeIfPresent(BluesScale.self, forKey: .scale)) ?? .minor
        scale = form.isMinor && !BluesScale.forMinorBlues.contains(saved) ? .minor : saved
        followsChords = (try? c.decodeIfPresent(Bool.self, forKey: .followsChords)) ?? false
        followRule = (try? c.decodeIfPresent(BluesFollowRule.self, forKey: .followRule)) ?? .tonic
        presetID = try? c.decodeIfPresent(String.self, forKey: .presetID)
        savedID = try? c.decodeIfPresent(UUID.self, forKey: .savedID)
    }

    /// The same music (key, form, feel, tempo, what plays, what shows), wherever it came from.
    func sameMusic(as other: BluesGroove) -> Bool {
        var a = self, b = other
        a.presetID = nil; a.savedID = nil
        b.presetID = nil; b.savedID = nil
        return a == b
    }

    // MARK: Key and chords

    var isMinor: Bool { form.isMinor }
    var keySignature: KeySignature { KeySignature(root: keyRoot, isMinor: isMinor) }

    /// The key's tonic as it's spelled in the key: "B♭".
    var tonicName: String {
        let tonic = isMinor ? keySignature.minorTonic : keySignature.majorTonic
        return SpelledPitch.letterNames[tonic.letter] + SpelledPitch.accidentalSymbol(tonic.accidental)
    }

    /// "A", or "A Minor" for a minor blues.
    var keyName: String { isMinor ? keySignature.minorKeyName : tonicName }

    var barCount: Int { form.degrees.count }

    /// Where bar `bar` falls in the form (bars count on through the repeats).
    func index(ofBar bar: Int) -> Int { ((bar % barCount) + barCount) % barCount }

    /// The chord of bar `bar`: dominant 7ths, or in a minor blues i7, iv7 and a dominant V7.
    func symbol(forBar bar: Int) -> ChordSymbol {
        let degree = form.degrees[index(ofBar: bar)]
        return ChordSymbol(degree: degree, kind: isMinor && degree != 5 ? .minor7 : .dominant7)
    }

    func chord(forBar bar: Int) -> CompositionChord {
        CompositionChord(symbol: symbol(forBar: bar), keySignature: keySignature, isMinor: isMinor)
    }

    /// One time through, bar by bar.
    var chords: [CompositionChord] { (0..<barCount).map { chord(forBar: $0) } }

    var secondsPerBeat: Double { 60 / Double(min(max(bpm, Self.tempoRange.lowerBound), Self.tempoRange.upperBound)) }

    /// The three switches as they play: the bass steps in if all are off.
    var plays: (bass: Bool, stabs: Bool, fills: Bool) {
        (bassPicking || !(chordStabs || fills), chordStabs, fills)
    }
}

// MARK: - What to solo with

extension BluesGroove {

    /// A scale on a root: what the fretboard shows, or what a fill is made from.
    struct ScaleChoice: Equatable {
        var root: Note
        /// The root as it's spelled: "B♭".
        var rootName: String
        var scale: BluesScale

        /// "A minor pentatonic", "A blues scale", "A minor + major pentatonic".
        var name: String {
            switch scale {
            case .minor: return "\(rootName) minor pentatonic"
            case .major: return "\(rootName) major pentatonic"
            case .blues: return "\(rootName) blues scale"
            case .both:  return "\(rootName) minor + major pentatonic"
            }
        }
    }

    /// The rule in force: a minor blues can only follow each chord's own (its i and iv want the
    /// minor pentatonic anyway, so the other rule would never change).
    var activeFollowRule: BluesFollowRule { isMinor ? .chord : followRule }

    /// What the fretboard shows over bar `bar`: the scale picked, or, following the chords,
    /// the one the rule gives that bar's chord.
    func shownScale(forBar bar: Int) -> ScaleChoice {
        guard followsChords else { return ScaleChoice(root: keyRoot, rootName: tonicName, scale: scale) }
        switch activeFollowRule {
        case .tonic:
            let onTonicChord = form.degrees[index(ofBar: bar)] == 1
            return ScaleChoice(root: keyRoot, rootName: tonicName, scale: onTonicChord ? .major : .minor)
        case .chord:
            let chord = chord(forBar: bar)
            return ScaleChoice(root: chord.root.note, rootName: chord.root.name,
                               scale: chord.quality == .minor ? .minor : .major)
        }
    }

    /// The part of the neck position `position` (1–5) names: the key's minor pentatonic box
    /// there. Whatever shows is drawn in this area, so switching scales changes the notes
    /// under your fingers and not where your hand is.
    func area(position: Int) -> PentatonicQuestion {
        let index = min(max(position, 1), allPentatonicShapes.count) - 1
        return PentatonicQuestion(shape: allPentatonicShapes[index], quality: .minor, key: keyRoot)
    }

    /// The box of `quality`'s pentatonic on `root` that sits nearest `area` (the lower, if two
    /// are as near).
    static func box(root: Note, quality: PentatonicQuality, nearest area: PentatonicQuestion) -> PentatonicQuestion {
        let minorRoot = quality.isMinor ? root : root.relativeMinor
        let base = fretOnLowE(for: minorRoot)
        let centre = Double(area.minFret + area.maxFret) / 2
        var best: PentatonicQuestion? = nil
        var bestDistance = Double.infinity
        for shape in allPentatonicShapes {
            for anchor in [base - 12, base, base + 12, base + 24] {
                let box = PentatonicQuestion(shape: shape, quality: quality, rootNote: minorRoot, anchorFret: anchor)
                guard box.minFret >= 1, box.maxFret <= 24 else { continue }
                let distance = abs(Double(box.minFret + box.maxFret) / 2 - centre)
                if distance < bestDistance - 0.001 || (abs(distance - bestDistance) <= 0.001 && box.minFret < (best?.minFret ?? .max)) {
                    best = box
                    bestDistance = distance
                }
            }
        }
        return best ?? area
    }

    /// The dots for position `position` over bar `bar`.
    func fretboard(position: Int, bar: Int) -> BluesFretboard {
        let area = area(position: position)
        let choice = shownScale(forBar: bar)
        let root = choice.root.rawValue
        var marks: [FretboardPosition: BluesFretboard.Mark] = [:]
        var labels: [FretboardPosition: String] = [:]
        func halfSteps(_ position: FretboardPosition) -> Int { ((position.note.rawValue - root) % 12 + 12) % 12 }
        func add(_ quality: PentatonicQuality) -> PentatonicQuestion {
            let box = Self.box(root: choice.root, quality: quality, nearest: area)
            for position in box.shapePositions {
                marks[position] = halfSteps(position) == 0 ? .root : .tone
            }
            return box
        }

        switch choice.scale {
        case .minor:
            _ = add(.minor)
        case .major:
            _ = add(.major)
        case .blues:
            // The minor box, and the ♭5 wherever it falls among its frets.
            let box = add(.minor)
            let name = flatFifthName
            for string in 0..<stringCount {
                for fret in box.minFret...box.maxFret {
                    let position = FretboardPosition(stringIndex: string, fret: fret)
                    guard halfSteps(position) == 6 else { continue }
                    marks[position] = .blueNote
                    labels[position] = name
                }
            }
        case .both:
            // Both boxes, every dot named by its degree: the ♭3 and the 3 sit a fret apart.
            _ = add(.minor)
            _ = add(.major)
            for position in Array(marks.keys) {
                let step = halfSteps(position)
                labels[position] = BluesFretboard.degreeNames[step]
                if BluesScale.minor.steps.contains(step) != BluesScale.major.steps.contains(step) {
                    marks[position] = BluesScale.minor.steps.contains(step) ? .minorOnly : .majorOnly
                }
            }
        }

        let frets = marks.keys.map(\.fret)
        return BluesFretboard(marks: marks, labels: labels, root: choice.root, spellsAsMinor: choice.scale != .major,
                              frets: (frets.min() ?? area.minFret)...(frets.max() ?? area.maxFret),
                              focus: max(area.minFret - 1, 1)...(area.maxFret + 1))
    }

    /// The key's ♭5 as it's spelled: "E♭" in A. Where that would take a double flat (A𝄫 in
    /// D♭), the note's plain name instead: "G".
    var flatFifthName: String {
        let tonic = isMinor ? keySignature.minorTonic : keySignature.majorTonic
        let letter = (tonic.letter + 4) % 7
        guard let pitch = SpelledPitch(midi: 60 + keyRoot.rawValue + 6, letter: letter), abs(pitch.accidental) <= 1 else {
            return keyRoot.advanced(by: 6).description
        }
        return SpelledPitch.letterNames[letter] + SpelledPitch.accidentalSymbol(pitch.accidental)
    }
}

/// What Blues Buddy's fretboard shows: the dots, what each is, and any labels that replace a
/// dot's note name.
struct BluesFretboard: Equatable {

    enum Mark: Equatable {
        case root
        /// A note of the scale (in Both: one the two pentatonics share).
        case tone
        /// In Both: only in the minor pentatonic (♭3, 4, ♭7), or only in the major (2, 3, 6).
        case minorOnly, majorOnly
        /// The blues scale's ♭5.
        case blueNote
    }

    var marks: [FretboardPosition: Mark]
    var labels: [FretboardPosition: String]
    /// The root the dots are on, and whether to spell their names as in its minor key.
    var root: Note
    var spellsAsMinor: Bool
    /// The frets the dots span.
    var frets: ClosedRange<Int>
    /// The frets to keep in view: the position's area and a fret either side, the same
    /// whatever shows, so the neck doesn't slide about as the chords change.
    var focus: ClosedRange<Int>

    var roots: Set<FretboardPosition> { Set(marks.filter { $0.value == .root }.keys) }

    /// Scale degrees by half steps above the root.
    static let degreeNames: [Int: String] = [0: "1", 2: "2", 3: "♭3", 4: "3", 5: "4", 6: "♭5", 7: "5", 9: "6", 10: "♭7"]
}

// MARK: - Dice

/// Blues Buddy's dice: the same seed, bar and layer always roll the same (SplitMix64). Each
/// layer has its own, so switching the fills off doesn't change what the bass plays.
struct BluesDice {

    enum Layer: UInt64 {
        case bassLine = 1, bass, stabs, fill, turnaround, scale
    }

    private var state: UInt64

    init(seed: UInt64, bar: Int, layer: Layer) {
        state = seed ^ (UInt64(truncatingIfNeeded: bar) &* 0x9E37_79B9_7F4A_7C15) ^ (layer.rawValue &* 0xD1B5_4A32_D192_ED03)
        _ = next()
        _ = next()
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 up to (not including) 1.
    mutating func unit() -> Double { Double(next() >> 11) / 9_007_199_254_740_992 }

    mutating func chance(_ probability: Double) -> Bool { unit() < probability }

    /// One of `options`, each as likely as its weight.
    mutating func pick<T>(_ options: [(T, Double)]) -> T {
        var roll = unit() * options.reduce(0) { $0 + $1.1 }
        for (option, weight) in options {
            roll -= weight
            if roll < 0 { return option }
        }
        return options[options.count - 1].0
    }
}

// MARK: - Bars

extension BluesGroove {

    typealias Hit = SoloGroove.Hit

    /// One bar, layer by layer.
    struct Bar: Equatable {
        var bass: [Hit] = []
        var stabs: [Hit] = []
        var fill: [Hit] = []
        /// The beats a fill takes up: no chords there, and the bass thins to the root.
        var fillSpan: Range<Double>? = nil
        /// The fill is the turnaround's walk down to the 5th.
        var isTurnaround = false

        var hits: [Hit] { bass + stabs + fill }
    }

    /// What plays in bar `bar` of the take that `seed` names.
    func hits(forBar bar: Int, seed: UInt64) -> [Hit] {
        self.bar(bar, seed: seed).hits
    }

    func bar(_ bar: Int, seed: UInt64) -> Bar {
        let chord = chord(forBar: bar)
        var out = Bar()
        if plays.fills, let fill = fill(forBar: bar, seed: seed, chord: chord) {
            out.fill = fill.hits
            out.fillSpan = fill.span
            out.isTurnaround = fill.isTurnaround
        }
        if plays.bass {
            let thinFrom = out.fillSpan.flatMap { $0.isEmpty ? nil : Int($0.lowerBound) }
            out.bass = bass(forBar: bar, seed: seed, chord: chord, thinFrom: thinFrom)
        }
        if plays.stabs {
            out.stabs = stabs(forBar: bar, seed: seed, chord: chord)
            if let span = out.fillSpan { out.stabs.removeAll { span.contains($0.beat) } }
        }
        // Every note stops by the barline, so the next chord comes in clean.
        let end = Double(Self.beatsPerBar)
        func clipped(_ hits: [Hit]) -> [Hit] {
            hits.map { hit in
                var hit = hit
                hit.beats = min(hit.beats, end - hit.beat)
                return hit
            }
        }
        out.bass = clipped(out.bass)
        out.stabs = clipped(out.stabs)
        out.fill = clipped(out.fill)
        return out
    }

    // MARK: Bass

    private enum BassPattern {
        /// Root with its 5th, then its 6th: the boogie.
        case boogie
        /// Up the chord and back in single notes.
        case walk
        /// The thumb on the root, every beat.
        case steady
        /// Root, 5th, octave in triplets (slow blues).
        case arpeggio
    }

    private var bassPatterns: [(BassPattern, Double)] {
        switch feel {
        case .shuffle:  return [(.boogie, 0.5), (.walk, 0.3), (.steady, 0.2)]
        case .straight: return [(.boogie, 0.35), (.walk, 0.25), (.steady, 0.4)]
        case .slow:     return [(.arpeggio, 0.4), (.boogie, 0.3), (.steady, 0.3)]
        }
    }

    /// The bass keeps one pattern for a four-bar line, with the odd bar of another. From beat
    /// `thinFrom` on (a fill is playing) it's just the root on the beat.
    private func bass(forBar bar: Int, seed: UInt64, chord: CompositionChord, thinFrom: Int?) -> [Hit] {
        let root = SoloGroove.lowRoot(of: chord)
        let fifth = SoloGroove.fifth(of: chord, above: root)
        let isMinorChord = chord.quality == .minor
        var lineDice = BluesDice(seed: seed, bar: Int((Double(bar) / 4).rounded(.down)), layer: .bassLine)
        var pattern = lineDice.pick(bassPatterns)
        // Sometimes the boogie reaches up to the ♭7: 5th, 6th, ♭7th, 6th.
        let reaches = lineDice.chance(0.4)
        var dice = BluesDice(seed: seed, bar: bar, layer: .bass)
        if dice.chance(0.2) { pattern = dice.pick(bassPatterns) }

        let off = feel.offbeat
        var hits: [Hit] = []
        for beat in 0..<Self.beatsPerBar {
            let at = Double(beat)
            if let thinFrom, beat >= thinFrom {
                hits.append(Hit(beat: at, midi: root, beats: 0.6, gain: 0.45))
                continue
            }
            switch pattern {
            case .boogie:
                let partner: Int
                if isMinorChord {
                    partner = beat % 2 == 0 ? fifth : root + 10
                } else if reaches {
                    partner = [fifth, root + 9, root + 10, root + 9][beat]
                } else {
                    partner = beat % 2 == 0 ? fifth : root + 9
                }
                for (offset, length, gain) in [(0.0, off, Float(0.6)), (off, 1 - off, Float(0.45))] {
                    hits.append(Hit(beat: at + offset, midi: root, beats: length * 0.85, gain: gain))
                    hits.append(Hit(beat: at + offset, midi: partner, beats: length * 0.85, gain: gain))
                }

            case .walk:
                if feel == .slow {
                    // A note a beat.
                    let line = isMinorChord ? [0, 3, 7, 10] : [0, 4, 7, 9]
                    hits.append(Hit(beat: at, midi: root + line[beat], beats: 0.9, gain: beat == 0 ? 0.7 : 0.6))
                } else {
                    let line = isMinorChord ? [0, 3, 5, 7, 10, 7, 5, 3] : [0, 4, 7, 9, 10, 9, 7, 4]
                    hits.append(Hit(beat: at, midi: root + line[beat * 2], beats: off * 0.9, gain: beat == 0 ? 0.7 : 0.62))
                    hits.append(Hit(beat: at + off, midi: root + line[beat * 2 + 1], beats: (1 - off) * 0.9, gain: 0.5))
                }

            case .steady:
                hits.append(Hit(beat: at, midi: root, beats: 0.5, gain: beat % 2 == 0 ? 0.7 : 0.55))

            case .arpeggio:
                for (i, midi) in [root, fifth, root + 12].enumerated() {
                    hits.append(Hit(beat: at + Double(i) / 3, midi: midi, beats: i == 0 ? 1 : 0.3,
                                    gain: i == 0 ? (beat % 2 == 0 ? 0.7 : 0.6) : 0.42))
                }
            }
        }
        return hits
    }

    // MARK: Chords

    /// Chords here and there: the full chord where the harmony moves, short stabs on the top
    /// three strings on 2 and 4 (or a slow blues's da-da-da), now and then a push into the next
    /// bar. With the bass off the chords keep the time themselves.
    private func stabs(forBar bar: Int, seed: UInt64, chord: CompositionChord) -> [Hit] {
        let shape = SoloGroove.shape(for: chord)
        let top3 = Array(shape.suffix(3))
        func strum(_ notes: [Int], at beat: Double, roll: Double, beats: Double, gain: Float) -> [Hit] {
            let each = gain / Float(max(notes.count, 1)).squareRoot()
            return notes.enumerated().map { i, midi in
                Hit(beat: beat, roll: Double(i) * roll, midi: midi, beats: beats, gain: each)
            }
        }
        var dice = BluesDice(seed: seed, bar: bar, layer: .stabs)
        let carries = !plays.bass
        let changed = bar == 0 || symbol(forBar: bar) != symbol(forBar: bar - 1)
        var hits: [Hit] = []

        if changed ? (carries || dice.chance(0.55)) : dice.chance(carries ? 0.5 : 0.12) {
            hits += strum(shape, at: 0, roll: 0.014, beats: feel == .slow ? 2 : 1.5, gain: 0.8)
        }

        enum Backbeat { case both, two, four, neither }
        let backbeat: Backbeat = carries
            ? .both
            : dice.pick([(Backbeat.both, 0.3), (Backbeat.two, 0.15), (Backbeat.four, 0.2), (Backbeat.neither, 0.35)])
        for beat in [1, 3] {
            guard backbeat == .both || (backbeat == .two && beat == 1) || (backbeat == .four && beat == 3) else { continue }
            if feel == .slow && dice.chance(0.35) {
                for i in 0..<3 {
                    hits += strum(top3, at: Double(beat) + Double(i) / 3, roll: 0.005, beats: 0.25, gain: i == 0 ? 0.55 : 0.42)
                }
            } else {
                hits += strum(top3, at: Double(beat), roll: 0.006, beats: 0.35, gain: 0.55)
            }
        }

        if dice.chance(0.18) {
            hits += strum(top3, at: 3 + feel.offbeat, roll: 0.005, beats: 0.3, gain: 0.5)
        }
        return hits
    }

    // MARK: Fills

    /// The key's tonic in the middle of the neck: the D-string root of the minor pentatonic's
    /// first box (F3 to E4), so fills sit where that box is.
    var fillTonic: Int { 53 + ((keyRoot.rawValue - 5) % 12 + 12) % 12 }

    /// The scale a fill in bar `bar` is made from. Following the chords, it's the one showing.
    /// Otherwise it's the one showing while the I chord plays (one or the other of Both), and
    /// over IV and V the minor pentatonic, where the major one's 3rd would clash. The blues
    /// scale suits all three.
    func fillScale(forBar bar: Int, seed: UInt64) -> ScaleChoice {
        if followsChords { return shownScale(forBar: bar) }
        var choice = ScaleChoice(root: keyRoot, rootName: tonicName, scale: .minor)
        if scale == .blues {
            choice.scale = .blues
        } else if !isMinor && form.degrees[index(ofBar: bar)] == 1 {
            switch scale {
            case .major:
                choice.scale = .major
            case .both:
                var dice = BluesDice(seed: seed, bar: bar, layer: .scale)
                choice.scale = dice.chance(0.5) ? .major : .minor
            case .minor, .blues:
                break
            }
        }
        return choice
    }

    /// The notes fills are made from, low to high: the scale's notes from a 4th below
    /// `fillTonic` to a minor 10th above (the same part of the neck whatever its root).
    func fillPool(_ choice: ScaleChoice) -> [Int] {
        let steps = choice.scale.steps
        return ((fillTonic - 5)...(fillTonic + 15)).filter { steps.contains((($0 - choice.root.rawValue) % 12 + 12) % 12) }
    }

    private struct Fill {
        var hits: [Hit]
        var span: Range<Double>
        var isTurnaround = false
    }

    /// Whether bar `bar` plays the turnaround: the bar of I before the last, half the time.
    func startsTurnaround(atBar bar: Int, seed: UInt64) -> Bool {
        guard plays.fills, form != .vamp, index(ofBar: bar) == barCount - 2 else { return false }
        var dice = BluesDice(seed: seed, bar: bar, layer: .turnaround)
        return dice.chance(0.5)
    }

    /// How likely a bar is to have a fill: most at the end of a four-bar line, where a singer
    /// would stop for breath, and nearly always when fills are all that's playing.
    private func fillChance(forBar bar: Int) -> Double {
        if !plays.bass && !plays.stabs { return 0.85 }
        let place = form == .vamp ? ((bar % 4) + 4) % 4 : index(ofBar: bar) % 4
        switch place {
        case 3:  return 0.7
        case 2:  return form == .vamp ? 0.12 : 0.4
        case 1:  return form == .vamp ? 0.3 : 0.12
        default: return 0.12
        }
    }

    private func fill(forBar bar: Int, seed: UInt64, chord: CompositionChord) -> Fill? {
        // A turnaround ends on the 5th, on the first beat of the V chord.
        if startsTurnaround(atBar: bar - 1, seed: seed) {
            return Fill(hits: [Hit(beat: 0, midi: fillTonic + 7, beats: 2, gain: 0.85)], span: 0..<0)
        }
        if startsTurnaround(atBar: bar, seed: seed) { return turnaround() }

        var dice = BluesDice(seed: seed, bar: bar, layer: .fill)
        guard dice.chance(fillChance(forBar: bar)) else { return nil }

        // When: from beat 3 most often, from beat 2, a short tag on 4, or nearly the whole bar.
        let slots = feel.slots
        let perBeat = slots.count / Self.beatsPerBar
        let startBeat = dice.pick([(2, 0.45), (1, 0.25), (3, 0.2), (0, 0.1)])
        let first = startBeat == 0 ? 1 : startBeat * perBeat
        // It lands on beat 4 and rings, or runs to the last note of the bar.
        let landing = startBeat < 3 && dice.chance(0.6) ? 3 * perBeat : slots.count - 1
        var onsets = [first]
        for slot in (first + 1)..<landing where dice.chance(0.75) { onsets.append(slot) }
        onsets.append(landing)

        // What: it ends on a note of the chord (its root likeliest), and walks there through
        // the pentatonic, mostly by step and mostly from above.
        let pool = fillPool(fillScale(forBar: bar, seed: seed))
        let chordRoot = chord.root.note.rawValue
        let targets: [(Int, Double)] = pool.indices.compactMap { i in
            let pitchClass = pool[i] % 12
            guard chord.pitchClasses.contains(pitchClass) else { return nil }
            return (i, pitchClass == chordRoot ? 3 : 1)
        }
        guard !targets.isEmpty, pool.count > 2 else { return nil }
        var index = dice.pick(targets)
        var line = [index]
        let fromAbove = dice.chance(0.6)
        for _ in 1..<onsets.count {
            let step = dice.pick([(1, 0.6), (-1, 0.25), (2, 0.15)]) * (fromAbove ? 1 : -1)
            var next = index + step
            if !pool.indices.contains(next) { next = index - step }
            next = min(max(next, 0), pool.count - 1)
            if next == index { next = index > 0 ? index - 1 : index + 1 }
            index = next
            line.insert(index, at: 0)
        }

        // The blues curl: the chord's minor 3rd nudged up to its major 3rd.
        let curls = chord.pitchClasses.contains((chordRoot + 4) % 12)
        let end = Double(Self.beatsPerBar)
        var hits: [Hit] = []
        for (i, slot) in onsets.enumerated() {
            let beat = slots[slot]
            let isLast = i == onsets.count - 1
            let length = isLast ? min(end - beat, 2) : slots[onsets[i + 1]] - beat
            let midi = pool[line[i]]
            let gain: Float = isLast ? 0.9 : (slot % perBeat == 0 ? 0.85 : 0.7)
            if curls, midi % 12 == (chordRoot + 3) % 12, dice.chance(0.5) {
                let grace = min(length / 3, 0.16)
                hits.append(Hit(beat: beat, midi: midi, beats: grace, gain: gain * 0.8))
                hits.append(Hit(beat: beat + grace, midi: midi + 1, beats: length - grace, gain: gain))
            } else {
                hits.append(Hit(beat: beat, midi: midi, beats: length, gain: gain))
            }
        }
        return Fill(hits: hits, span: slots[first]..<end)
    }

    /// The turnaround: the tonic, then ♭7, 6 and ♭6 walking down under a high tonic. The next
    /// bar (the V chord) gets the 5th they lead to.
    private func turnaround() -> Fill {
        let tonic = fillTonic
        let off = feel.offbeat
        var hits = [Hit(beat: 0, midi: tonic, beats: 1, gain: 0.85)]
        for (i, step) in [10, 9, 8].enumerated() {
            let at = Double(i + 1)
            if feel == .slow {
                hits.append(Hit(beat: at, midi: tonic + step, beats: 1.0 / 3, gain: 0.85))
                hits.append(Hit(beat: at + 1.0 / 3, midi: tonic + 12, beats: 1.0 / 3, gain: 0.6))
                hits.append(Hit(beat: at + 2.0 / 3, midi: tonic + step, beats: 1.0 / 3, gain: 0.7))
            } else {
                hits.append(Hit(beat: at, midi: tonic + step, beats: off, gain: 0.85))
                hits.append(Hit(beat: at + off, midi: tonic + 12, beats: 1 - off, gain: 0.6))
            }
        }
        return Fill(hits: hits, span: 0..<Double(Self.beatsPerBar), isTurnaround: true)
    }
}

// MARK: - Backing

/// One take of a groove, for BackingTrack: the groove and the seed its bars are rolled from.
struct BluesBacking: BackingSource {
    var groove: BluesGroove
    var seed: UInt64

    var secondsPerBeat: Double { groove.secondsPerBeat }
    var beatsPerBar: Int { BluesGroove.beatsPerBar }

    func hits(forBar bar: Int) -> [SoloGroove.Hit] {
        groove.hits(forBar: bar, seed: seed)
    }
}

// MARK: - Presets

struct BluesPreset: Identifiable {
    let id: String
    let name: String
    let detail: String
    let groove: BluesGroove

    private init(_ id: String, _ name: String, _ detail: String, key: Note, _ form: BluesForm, _ feel: BluesFeel, bpm: Int) {
        self.id = id
        self.name = name
        self.detail = detail
        groove = BluesGroove(keyRoot: key, form: form, feel: feel, bpm: bpm, presetID: id)
    }

    static let all: [BluesPreset] = [
        BluesPreset("twelve-bar", "12-Bar Blues", "I7, IV7 and V7 with a shuffle. The one to know.", key: .a, .twelveBar, .shuffle, bpm: 95),
        BluesPreset("quick-change", "Quick-Change Blues", "The 12-bar that visits IV in bar 2.", key: .g, .quickChange, .shuffle, bpm: 105),
        BluesPreset("slow-blues", "Slow Blues", "Twelve bars in E, slow and heavy, with room to answer.", key: .e, .twelveBar, .slow, bpm: 60),
        BluesPreset("minor-blues", "Minor Blues", "The twelve bars in minor: i7, iv7 and V7.", key: .a, .minorTwelveBar, .slow, bpm: 65),
        BluesPreset("eight-bar", "8-Bar Blues", "The short form, as in Key to the Highway.", key: .a, .eightBar, .shuffle, bpm: 90),
        BluesPreset("funky-dominant", "Funky Dominant", "One dominant 7th. Switch between minor and major pentatonic on its root.", key: .e, .vamp, .straight, bpm: 105),
    ]

    static func preset(_ id: String?) -> BluesPreset? { all.first { $0.id == id } }
}

// MARK: - Saved grooves

/// A Blues Buddy groove you saved, by name.
struct SavedBlues: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var groove: BluesGroove
    var savedAt = Date()

    /// The groove ready to play: it remembers it came from here.
    var playable: BluesGroove {
        var groove = self.groove
        groove.presetID = nil
        groove.savedID = id
        return groove
    }
}

/// Saved Blues Buddy grooves, newest first, and the groove playing, kept in UserDefaults.
/// Solo Buddy had the 12-bar blues before Blues Buddy took the blues over: grooves saved
/// with it there, and the groove left playing, are moved here the first time either loads.
enum SavedBluesGrooves {
    static let key = "bluesBuddy.savedGrooves"
    static let currentKey = "bluesBuddy.groove"

    static func load(_ defaults: UserDefaults = .standard) -> [SavedBlues] {
        // Solo Buddy hands over any 12-bar grooves it still holds.
        _ = SavedGrooves.load(defaults)
        return stored(defaults).sorted { $0.savedAt > $1.savedAt }
    }

    static func store(_ saved: [SavedBlues], _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(saved) { defaults.set(data, forKey: key) }
    }

    private static func stored(_ defaults: UserDefaults) -> [SavedBlues] {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([SavedBlues].self, from: $0) } ?? []
    }

    /// The groove Blues Buddy was playing last, or the first preset.
    static func loadCurrent(_ defaults: UserDefaults = .standard) -> BluesGroove {
        // If Solo Buddy was left on a 12-bar blues, that comes over first.
        _ = SavedGrooves.loadCurrent(defaults)
        return defaults.data(forKey: currentKey).flatMap { try? JSONDecoder().decode(BluesGroove.self, from: $0) }
            ?? BluesPreset.all[0].groove
    }

    static func storeCurrent(_ groove: BluesGroove, _ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(groove) { defaults.set(data, forKey: currentKey) }
    }

    /// `base`, or "base 2", "base 3"… if a saved groove already has that name.
    static func unusedName(_ base: String, in saved: [SavedBlues]) -> String {
        SavedGrooves.unusedName(base, among: Set(saved.map(\.name)))
    }

    // MARK: From Solo Buddy

    /// A 12-bar groove from Solo Buddy as the nearest Blues Buddy one: its 12-bar had the quick
    /// change, its shuffle is the Shuffle feel, its ballad the slow blues.
    static func blues(from solo: SoloGroove) -> BluesGroove {
        let feel: BluesFeel = solo.style == .shuffle ? .shuffle : solo.style == .ballad ? .slow : .straight
        return BluesGroove(keyRoot: solo.keyRoot, form: solo.isMinor ? .minorTwelveBar : .quickChange, feel: feel,
                           bpm: min(max(solo.bpm, BluesGroove.tempoRange.lowerBound), BluesGroove.tempoRange.upperBound),
                           scale: solo.scale.isMinor ? .minor : .major, savedID: solo.savedID)
    }

    /// Takes over 12-bar grooves saved in Solo Buddy, keeping their names, dates and ids.
    static func adopt(_ grooves: [SavedGroove], _ defaults: UserDefaults = .standard) {
        var saved = stored(defaults)
        for item in grooves where !saved.contains(where: { $0.id == item.id }) {
            var groove = blues(from: item.groove)
            groove.savedID = nil
            saved.append(SavedBlues(id: item.id, name: unusedName(item.name, in: saved), groove: groove, savedAt: item.savedAt))
        }
        store(saved, defaults)
    }

    /// Takes over the 12-bar groove Solo Buddy was left playing, unless Blues Buddy has its own.
    static func adoptCurrent(_ groove: SoloGroove, _ defaults: UserDefaults = .standard) {
        guard defaults.data(forKey: currentKey) == nil else { return }
        storeCurrent(blues(from: groove), defaults)
    }
}
