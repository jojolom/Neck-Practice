//
//  Chord.swift
//  Guitar Man
//
//  The chords Compose writes. A ChordSymbol names a chord in the key's own terms: a scale
//  degree (optionally a half step off it, like ♭VII, or a secondary dominant like V/V), a kind
//  (the key's own triad or seventh, or a fixed one: V major in a minor key, sus4, …), and an
//  inversion. CompositionChord spells one in a key: its Roman numeral, name (V7 in E♭ is B♭7),
//  and notes on the staff, stacked by letter so the spelling is right. The palette's choices
//  live here too: each degree's variants, and the borrowed and secondary chords.
//  No UI here, so scripts/chord-check.swift can check it.
//

import Foundation

// MARK: - ChordKind

enum ChordKind: String, Codable, CaseIterable {
    /// The key's own triad / seventh chord on the degree: these change when the key goes from
    /// major to minor, like the plain numerals always have.
    case triad, seventh
    case major, minor, diminished, augmented
    case major7, dominant7, minor7, halfDiminished7, diminished7
    case sus2, sus4

    /// The notes above the root, for a fixed kind (nil for `triad` and `seventh`).
    var intervals: [Interval]? {
        switch self {
        case .triad, .seventh:  return nil
        case .major:            return [Interval(.major, 3), Interval(.perfect, 5)]
        case .minor:            return [Interval(.minor, 3), Interval(.perfect, 5)]
        case .diminished:       return [Interval(.minor, 3), Interval(.diminished, 5)]
        case .augmented:        return [Interval(.major, 3), Interval(.augmented, 5)]
        case .major7:           return [Interval(.major, 3), Interval(.perfect, 5), Interval(.major, 7)]
        case .dominant7:        return [Interval(.major, 3), Interval(.perfect, 5), Interval(.minor, 7)]
        case .minor7:           return [Interval(.minor, 3), Interval(.perfect, 5), Interval(.minor, 7)]
        case .halfDiminished7:  return [Interval(.minor, 3), Interval(.diminished, 5), Interval(.minor, 7)]
        case .diminished7:      return [Interval(.minor, 3), Interval(.diminished, 5), Interval(.diminished, 7)]
        case .sus2:             return [Interval(.major, 2), Interval(.perfect, 5)]
        case .sus4:             return [Interval(.perfect, 4), Interval(.perfect, 5)]
        }
    }

    static let fixedKinds: [ChordKind] = allCases.filter { $0.intervals != nil }

    var isSeventh: Bool { [.seventh, .major7, .dominant7, .minor7, .halfDiminished7, .diminished7].contains(self) }
    var isSus: Bool { self == .sus2 || self == .sus4 }
    /// Written with an upper-case numeral (a major 3rd).
    var isMajorish: Bool { [.major, .augmented, .major7, .dominant7].contains(self) }

    /// After the chord's letter: "m", "°", "maj7", "ø7".
    var nameSuffix: String {
        switch self {
        case .triad, .seventh, .major: return ""
        case .minor:            return "m"
        case .diminished:       return "°"
        case .augmented:        return "+"
        case .major7:           return "maj7"
        case .dominant7:        return "7"
        case .minor7:           return "m7"
        case .halfDiminished7:  return "ø7"
        case .diminished7:      return "°7"
        case .sus2:             return "sus2"
        case .sus4:             return "sus4"
        }
    }

    /// "major", "dominant 7th".
    var longName: String {
        switch self {
        case .triad, .seventh, .major: return "major"
        case .minor:            return "minor"
        case .diminished:       return "diminished"
        case .augmented:        return "augmented"
        case .major7:           return "major 7th"
        case .dominant7:        return "dominant 7th"
        case .minor7:           return "minor 7th"
        case .halfDiminished7:  return "half-diminished 7th"
        case .diminished7:      return "diminished 7th"
        case .sus2:             return "sus2"
        case .sus4:             return "sus4"
        }
    }
}

// MARK: - ChordSymbol

/// Which chord, in the key's terms. Saved with compositions, so new fields need defaults.
struct ChordSymbol: Codable, Hashable {
    /// Scale degree of the root, 1–7 (for a secondary dominant, ignored: see `secondary`).
    var degree: Int
    /// Half steps the root is moved off the scale note: −1 for ♭VII in a major key.
    var shift: Int = 0
    var kind: ChordKind = .triad
    /// A secondary dominant: the degree it's the V of (V/V → 5). The root is then a 5th above that degree.
    var secondary: Int? = nil
    /// 0 = root position, 1 = 3rd in the bass, 2 = 5th, 3 = 7th.
    var inversion: Int = 0

    init(degree: Int, shift: Int = 0, kind: ChordKind = .triad, secondary: Int? = nil, inversion: Int = 0) {
        self.degree = degree
        self.shift = shift
        self.kind = kind
        self.secondary = secondary
        self.inversion = inversion
    }

    /// The same chord in root position.
    var rootPosition: ChordSymbol { inverted(0) }

    /// The same chord with `inversion`'s note in the bass.
    func inverted(_ inversion: Int) -> ChordSymbol {
        var copy = self
        copy.inversion = inversion
        return copy
    }

    var isValid: Bool {
        (1...7).contains(degree) && (-1...1).contains(shift) && (0...3).contains(inversion)
            && secondary.map { (1...7).contains($0) } ?? true
    }

    private enum CodingKeys: String, CodingKey { case degree, shift, kind, secondary, inversion }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        degree = try c.decode(Int.self, forKey: .degree)
        shift = try c.decodeIfPresent(Int.self, forKey: .shift) ?? 0
        kind = (try? c.decodeIfPresent(ChordKind.self, forKey: .kind)) ?? .triad
        secondary = try c.decodeIfPresent(Int.self, forKey: .secondary)
        inversion = try c.decodeIfPresent(Int.self, forKey: .inversion) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(degree, forKey: .degree)
        if shift != 0 { try c.encode(shift, forKey: .shift) }
        if kind != .triad { try c.encode(kind, forKey: .kind) }
        try c.encodeIfPresent(secondary, forKey: .secondary)
        if inversion != 0 { try c.encode(inversion, forKey: .inversion) }
    }

    // MARK: Drag and drop

    /// The text a palette button drags: "chord:" and the symbol as JSON.
    var dragText: String {
        let json = (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "chord:" + json
    }

    /// A chord dragged from the palette (or, from before chord kinds, a bare degree "5").
    init?(dragText: String) {
        if let degree = Int(dragText) {
            self.init(degree: degree)
        } else if dragText.hasPrefix("chord:"),
                  let symbol = try? JSONDecoder().decode(ChordSymbol.self, from: Data(dragText.dropFirst(6).utf8)) {
            self = symbol
        } else {
            return nil
        }
        guard isValid else { return nil }
    }
}

// MARK: - CompositionChord

/// A chord spelled in a key: Roman numeral, name (IV in E♭ = A♭), and notes.
struct CompositionChord: Hashable {
    let symbol: ChordSymbol
    let keySignature: KeySignature
    let isMinor: Bool

    init(symbol: ChordSymbol, keySignature: KeySignature, isMinor: Bool) {
        self.symbol = symbol
        self.keySignature = keySignature
        self.isMinor = isMinor
    }

    init(degree: Int, keySignature: KeySignature, isMinor: Bool) {
        self.init(symbol: ChordSymbol(degree: degree), keySignature: keySignature, isMinor: isMinor)
    }

    var degree: Int { symbol.degree }
    private var scale: DiatonicScale { isMinor ? .minor : .major }
    private var tonicLetter: Int { isMinor ? keySignature.minorTonic.letter : keySignature.majorTonic.letter }

    /// The scale note on `degree`, in concert octave 3.
    private func scaleNote(_ degree: Int) -> SpelledPitch {
        keySignature.pitch(letter: (tonicLetter + degree - 1) % 7, octave: 3)
    }

    /// The root, in concert octave 3 (written in octave 4: on or just below the staff).
    var root: SpelledPitch {
        if let target = symbol.secondary {
            let fifth = scaleNote(target).transposed(by: Interval(.perfect, 5)) ?? scaleNote(target)
            return SpelledPitch(letter: fifth.letter, accidental: fifth.accidental, octave: 3)
        }
        let note = scaleNote(symbol.degree)
        let shifted = SpelledPitch(letter: note.letter, accidental: note.accidental + symbol.shift, octave: 3)
        // A borrowed root that would need a double flat is written as its neighbour: ♭VI in D♭ is A, not B𝄫.
        guard abs(shifted.accidental) > 1 else { return shifted }
        let letter = (shifted.letter + (shifted.accidental > 0 ? 1 : 6)) % 7
        guard let respelled = SpelledPitch(midi: shifted.midi, letter: letter) else { return shifted }
        return SpelledPitch(letter: respelled.letter, accidental: respelled.accidental, octave: 3)
    }

    /// What the chord actually is. The key's own triad or seventh is read off the scale (3rds
    /// stacked from the degree); a fixed kind is itself.
    var kind: ChordKind {
        guard symbol.kind == .triad || symbol.kind == .seventh else { return symbol.kind }
        let start = scaleNote(symbol.degree)
        let steps = symbol.kind == .triad ? [2, 4] : [2, 4, 6]
        let stacked = steps.map { keySignature.pitch(letter: (start.letter + $0) % 7, octave: 3 + (start.letter + $0) / 7) }
        let intervals = stacked.compactMap { Interval.between(start, $0) }
        let candidates: [ChordKind] = symbol.kind == .triad
            ? [.major, .minor, .diminished, .augmented]
            : [.major7, .dominant7, .minor7, .halfDiminished7, .diminished7]
        return candidates.first { $0.intervals == intervals } ?? (symbol.kind == .triad ? .major : .dominant7)
    }

    /// The triad quality for a plain diatonic chord, as the rest of the app names them.
    var quality: RNChordQuality {
        switch kind {
        case .minor, .minor7: return .minor
        case .diminished, .halfDiminished7, .diminished7: return .diminished
        default: return .major
        }
    }

    /// Root position, low to high.
    private var rootPositionPitches: [SpelledPitch] {
        let root = self.root
        return [root] + (kind.intervals ?? []).compactMap { root.transposed(by: $0) }
    }

    var maxInversion: Int { kind.isSus ? 0 : rootPositionPitches.count - 1 }

    private var inversion: Int { min(max(symbol.inversion, 0), maxInversion) }

    /// The notes as written, low to high: in root position stacked up from the root; inverted,
    /// the lower notes go up an octave. The whole chord drops an octave if that would sit it
    /// high above the staff.
    var pitches: [SpelledPitch] {
        let stack = rootPositionPitches
        var notes = Array(stack[inversion...]) + stack[..<inversion].map {
            SpelledPitch(letter: $0.letter, accidental: $0.accidental, octave: $0.octave + 1)
        }
        let middle = Double((notes.first?.staffPosition ?? 4) + (notes.last?.staffPosition ?? 4)) / 2
        if middle > 7.5 {
            notes = notes.map { SpelledPitch(letter: $0.letter, accidental: $0.accidental, octave: $0.octave - 1) }
        }
        return notes
    }

    /// The bass note (the lowest one).
    var bass: SpelledPitch { pitches.first ?? root }

    /// "A♭", "Fm", "B°", "G7", "C/E".
    var name: String {
        let base = root.name + kind.nameSuffix
        return inversion > 0 ? "\(base)/\(bass.name)" : base
    }

    /// "A♭ major", "G dominant 7th", "C major over E".
    var longName: String {
        let base = kind.isSus ? root.name + kind.nameSuffix : "\(root.name) \(kind.longName)"
        return inversion > 0 ? "\(base) over \(bass.name)" : base
    }

    // MARK: Roman numeral

    private static let numerals = ["I", "II", "III", "IV", "V", "VI", "VII"]

    /// "IV", "ii7", "♭VII", "V7/V", "I⁶", "V⁶₅".
    var romanNumeral: String {
        if let target = symbol.secondary {
            let targetNumeral = scale.romanNumerals[target - 1]
            return "V" + qualityMark(majorish: true) + "/" + targetNumeral
        }
        // A plain diatonic triad in root position reads as it always has.
        if symbol.kind == .triad && symbol.shift == 0 && inversion == 0 {
            return scale.romanNumerals[symbol.degree - 1]
        }
        let base = Self.numerals[symbol.degree - 1]
        let majorish = kind.isSus ? scale.chordQualities[symbol.degree - 1] == .major : kind.isMajorish
        // In minor, the raised 6th and 7th (vii° in A minor is G♯°) are written without a sharp.
        let raisedInMinor = isMinor && symbol.shift == 1 && symbol.degree >= 6
        let prefix = raisedInMinor ? "" : symbol.shift < 0 ? "♭" : symbol.shift > 0 ? "♯" : ""
        return prefix + (majorish ? base : base.lowercased()) + qualityMark(majorish: majorish)
    }

    /// The part after the numeral: the kind, then the inversion's figures.
    private func qualityMark(majorish: Bool) -> String {
        let figures: String
        if kind.isSeventh {
            figures = ["7", "⁶₅", "⁴₃", "⁴₂"][inversion]
        } else {
            figures = ["", "⁶", "⁶₄"][min(inversion, 2)]
        }
        switch kind {
        case .diminished:       return "°" + figures
        case .augmented:        return "+" + figures
        case .halfDiminished7:  return "ø" + figures
        case .diminished7:      return "°" + figures
        case .major7:           return "maj" + figures
        case .sus2:             return "sus2"
        case .sus4:             return "sus4"
        default:                return figures
        }
    }

    // MARK: Hearing it

    /// Pitch classes of all the notes, for ChordAnalyzer.
    var pitchClasses: Set<Int> { Set(pitches.map { $0.note.rawValue }) }

    /// The notes Play Along insists on hearing: all of them, except that a seventh chord's
    /// perfect 5th may be left out, as guitar shapes often do (C7 is x32310, no G).
    var requiredPitchClasses: Set<Int> {
        let stack = rootPositionPitches
        guard stack.count == 4, kind.intervals?[1] == Interval(.perfect, 5) else { return pitchClasses }
        var required = pitchClasses
        required.remove(stack[2].note.rawValue)
        return required
    }

    /// Whether every note is in the key (no accidentals outside the signature).
    var isDiatonic: Bool {
        rootPositionPitches.allSatisfy { $0.accidental == keySignature.accidental(forLetter: $0.letter) }
    }
}

// MARK: - Palette choices

extension CompositionChord {

    /// What a degree's palette button offers: its triad and seventh, the sus chords that stay in
    /// the key, and in a minor key the major V and V7 that most minor-key songs use.
    static func variants(degree: Int, keySignature: KeySignature, isMinor: Bool) -> [ChordSymbol] {
        var symbols = [ChordSymbol(degree: degree), ChordSymbol(degree: degree, kind: .seventh)]
        if isMinor && degree == 5 {
            symbols += [ChordSymbol(degree: 5, kind: .major), ChordSymbol(degree: 5, kind: .dominant7)]
        }
        for sus in [ChordKind.sus2, .sus4] {
            let symbol = ChordSymbol(degree: degree, kind: sus)
            if CompositionChord(symbol: symbol, keySignature: keySignature, isMinor: isMinor).isDiatonic {
                symbols.append(symbol)
            }
        }
        return symbols
    }

    /// The second palette page: chords borrowed from the parallel key and secondary dominants,
    /// the ones that make a progression sound like a real song. Each with its seventh as a variant.
    static func borrowed(isMinor: Bool) -> [(chord: ChordSymbol, seventh: ChordSymbol)] {
        func pair(_ degree: Int, shift: Int = 0, _ kind: ChordKind, _ seventh: ChordKind, secondary: Int? = nil)
            -> (chord: ChordSymbol, seventh: ChordSymbol) {
            (ChordSymbol(degree: degree, shift: shift, kind: kind, secondary: secondary),
             ChordSymbol(degree: degree, shift: shift, kind: seventh, secondary: secondary))
        }
        if isMinor {
            return [
                pair(5, .major, .dominant7),                  // V: the harmonic-minor dominant
                pair(7, shift: 1, .diminished, .diminished7), // vii°: the leading tone
                pair(4, .major, .dominant7),                  // IV: Dorian
                pair(2, shift: -1, .major, .major7),          // ♭II: Neapolitan
                pair(1, .major, .dominant7),                  // I: Picardy third (I7 leads to iv)
                pair(5, .major, .dominant7, secondary: 5),    // V/V
            ]
        }
        return [
            pair(3, shift: -1, .major, .major7),              // ♭III
            pair(4, .minor, .minor7),                         // iv
            pair(6, shift: -1, .major, .major7),              // ♭VI
            pair(7, shift: -1, .major, .dominant7),           // ♭VII
            pair(5, .major, .dominant7, secondary: 2),        // V/ii
            pair(5, .major, .dominant7, secondary: 5),        // V/V
            pair(5, .major, .dominant7, secondary: 6),        // V/vi
        ]
    }
}
