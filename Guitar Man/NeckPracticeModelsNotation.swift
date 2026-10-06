//
//  Notation.swift
//  Guitar Man
//
//  Written-music types shared by the staff views: a pitch spelled with a letter and an
//  accidental (so F♯ and G♭ are different notes on the staff), key signatures, note values,
//  and intervals. No UI here, so the theory can be checked offline — see scripts/interval-check.swift.
//

import Foundation

// MARK: - SpelledPitch

/// A pitch as it's written: a letter, an accidental, and an octave.
struct SpelledPitch: Hashable, Codable {
    /// 0 = C … 6 = B
    let letter: Int
    /// −2 = double flat, −1 = flat, 0 = natural, 1 = sharp, 2 = double sharp.
    let accidental: Int
    /// Scientific octave of the letter at concert pitch (middle C is C4). Guitar music is
    /// written an octave higher than it sounds; `staffPosition` takes care of that.
    let octave: Int

    static let letterNames = ["C", "D", "E", "F", "G", "A", "B"]
    static let naturalSemitones = [0, 2, 4, 5, 7, 9, 11]

    init(letter: Int, accidental: Int = 0, octave: Int) {
        self.letter = letter
        self.accidental = accidental
        self.octave = octave
    }

    /// `midi` spelled with `letter`, or nil if that would take more than a double accidental.
    init?(midi: Int, letter: Int) {
        let pitchClass = ((midi % 12) + 12) % 12
        var accidental = pitchClass - Self.naturalSemitones[letter]
        if accidental > 6 { accidental -= 12 }
        if accidental < -6 { accidental += 12 }
        guard abs(accidental) <= 2 else { return nil }
        let naturalMidi = midi - accidental
        self.init(letter: letter, accidental: accidental,
                  octave: (naturalMidi - Self.naturalSemitones[letter]) / 12 - 1)
    }

    /// MIDI note number of the sounding pitch.
    var midi: Int { 12 * (octave + 1) + Self.naturalSemitones[letter] + accidental }

    /// The pitch class, for the fretboard and the synth.
    var note: Note { Note(rawValue: ((midi % 12) + 12) % 12)! }

    /// Octave of the sounding pitch (B♯3 sounds as C4), as `AudioPlayer.playNote(_:octave:)` expects.
    var soundingOctave: Int { midi / 12 - 1 }

    /// Steps counted in letters from C0: what interval numbers and staff placement are measured in.
    var diatonicNumber: Int { octave * 7 + letter }

    /// Position on a treble-clef staff in guitar notation (written an octave above concert):
    /// 0 = bottom line (written E4), each step is the next line or space. Low E is −7.
    var staffPosition: Int { diatonicNumber - 23 }

    /// "F♯", "B♭", "C".
    var name: String { Self.letterNames[letter] + Self.accidentalSymbol(accidental) }

    /// The pitch `interval` above (or below) this one, spelled by counting letters,
    /// or nil if it would need more than a double accidental.
    func transposed(by interval: Interval, up: Bool = true) -> SpelledPitch? {
        let steps = interval.number - 1
        let target = up ? diatonicNumber + steps : diatonicNumber - steps
        let letter = ((target % 7) + 7) % 7
        let octave = (target - letter) / 7
        let targetMidi = up ? midi + interval.semitones : midi - interval.semitones
        let accidental = targetMidi - (12 * (octave + 1) + Self.naturalSemitones[letter])
        guard abs(accidental) <= 2 else { return nil }
        return SpelledPitch(letter: letter, accidental: accidental, octave: octave)
    }

    static func accidentalSymbol(_ accidental: Int) -> String {
        switch accidental {
        case 2:  return "𝄪"
        case 1:  return "♯"
        case -1: return "♭"
        case -2: return "𝄫"
        default: return ""
        }
    }
}

// MARK: - KeySignature

/// A key signature: how many sharps (positive) or flats (negative), −7…7.
struct KeySignature: Hashable, Codable {
    let fifths: Int

    init(fifths: Int) {
        self.fifths = max(-7, min(7, fifths))
    }

    static let cMajor = KeySignature(fifths: 0)

    /// Letters sharpened, in the order they're written: F C G D A E B.
    static let sharpLetters = [3, 0, 4, 1, 5, 2, 6]
    /// Letters flattened, in the order they're written: B E A D G C F.
    static let flatLetters = [6, 2, 5, 1, 4, 0, 3]
    /// Where each sharp / flat sits on the treble staff (0 = bottom line).
    static let sharpStaffPositions = [8, 5, 9, 6, 3, 7, 4]
    static let flatStaffPositions = [4, 7, 3, 6, 2, 5, 1]

    /// The accidental this signature gives `letter`.
    func accidental(forLetter letter: Int) -> Int {
        if fifths > 0 { return Self.sharpLetters.prefix(fifths).contains(letter) ? 1 : 0 }
        if fifths < 0 { return Self.flatLetters.prefix(-fifths).contains(letter) ? -1 : 0 }
        return 0
    }

    /// The accidental to print in front of `pitch`: nil when the signature already covers it,
    /// 0 for a natural sign.
    func printedAccidental(for pitch: SpelledPitch) -> Int? {
        pitch.accidental == accidental(forLetter: pitch.letter) ? nil : pitch.accidental
    }

    /// The major key's tonic: letter and accidental. Each sharp moves it up a fifth (4 letters),
    /// and the tonic is in its own scale, so the signature gives its accidental.
    var majorTonic: (letter: Int, accidental: Int) {
        let letter = ((4 * fifths) % 7 + 7) % 7
        return (letter, accidental(forLetter: letter))
    }

    /// The relative minor's tonic: a sixth above the major tonic.
    var minorTonic: (letter: Int, accidental: Int) {
        let letter = (majorTonic.letter + 5) % 7
        return (letter, accidental(forLetter: letter))
    }

    var majorKeyName: String {
        SpelledPitch.letterNames[majorTonic.letter] + SpelledPitch.accidentalSymbol(majorTonic.accidental) + " Major"
    }

    var minorKeyName: String {
        SpelledPitch.letterNames[minorTonic.letter] + SpelledPitch.accidentalSymbol(minorTonic.accidental) + " Minor"
    }

    /// The signature of the major key on this tonic, or nil if it would need more than 7 accidentals
    /// (G♯ major, for one).
    static func major(letter: Int, accidental: Int) -> KeySignature? {
        (-7...7).map(KeySignature.init(fifths:)).first {
            $0.majorTonic.letter == letter && $0.majorTonic.accidental == accidental
        }
    }

    /// The signature of the natural-minor key on this tonic, or nil past 7 accidentals.
    static func minor(letter: Int, accidental: Int) -> KeySignature? {
        (-7...7).map(KeySignature.init(fifths:)).first {
            $0.minorTonic.letter == letter && $0.minorTonic.accidental == accidental
        }
    }

    /// The signature for a key root as the rest of the app spells it (D♭ major, C♯ minor).
    init(root: Note, isMinor: Bool) {
        let info = root.keyLetterInfo(asMinor: isMinor)
        let found = isMinor
            ? KeySignature.minor(letter: info.letterIndex, accidental: info.accidental)
            : KeySignature.major(letter: info.letterIndex, accidental: info.accidental)
        self = found ?? .cMajor
    }

    /// The scale note on `letter` in `octave`: the letter with this signature's accidental.
    func pitch(letter: Int, octave: Int) -> SpelledPitch {
        SpelledPitch(letter: letter, accidental: accidental(forLetter: letter), octave: octave)
    }
}

// MARK: - NoteValue

/// How long a note lasts, in quarter-note beats. Drives note-head drawing and measure lengths.
enum NoteValue: String, Codable, CaseIterable, Identifiable {
    case quarter, half, dottedHalf, whole

    var id: String { rawValue }

    var beats: Int {
        switch self {
        case .quarter:    return 1
        case .half:       return 2
        case .dottedHalf: return 3
        case .whole:      return 4
        }
    }

    var displayName: String {
        switch self {
        case .quarter:    return "Quarter"
        case .half:       return "Half"
        case .dottedHalf: return "Dotted Half"
        case .whole:      return "Whole"
        }
    }

    var hasStem: Bool { self != .whole }
    var isFilled: Bool { self == .quarter }
    var isDotted: Bool { self == .dottedHalf }
}

// MARK: - Interval

enum IntervalQuality: Int, Codable, CaseIterable {
    case diminished, minor, perfect, major, augmented

    var name: String {
        switch self {
        case .diminished: return "Diminished"
        case .minor:      return "Minor"
        case .perfect:    return "Perfect"
        case .major:      return "Major"
        case .augmented:  return "Augmented"
        }
    }

    var abbreviation: String {
        switch self {
        case .diminished: return "d"
        case .minor:      return "m"
        case .perfect:    return "P"
        case .major:      return "M"
        case .augmented:  return "A"
        }
    }

    /// The quality after inverting: major ↔ minor, augmented ↔ diminished, perfect stays perfect.
    var inverted: IntervalQuality {
        switch self {
        case .diminished: return .augmented
        case .minor:      return .major
        case .perfect:    return .perfect
        case .major:      return .minor
        case .augmented:  return .diminished
        }
    }
}

/// An interval measured up from the lower note: a quality and a number (1 = unison, 8 = octave,
/// 9 and up are compound).
struct Interval: Hashable, Codable, Identifiable {
    let quality: IntervalQuality
    let number: Int

    init(_ quality: IntervalQuality, _ number: Int) {
        self.quality = quality
        self.number = number
    }

    var id: String { shortName }

    /// Semitones of the major or perfect interval for each simple number, unison to 7th.
    private static let majorOrPerfectSemitones = [0, 2, 4, 5, 7, 9, 11]

    /// 1–7: the number with whole octaves removed (an octave and a 15th count as 1).
    var simpleNumber: Int { (number - 1) % 7 + 1 }

    /// Unisons, 4ths, 5ths and octaves (and their compounds) are perfect; the rest are major/minor.
    var isPerfectType: Bool { [1, 4, 5].contains(simpleNumber) }

    /// Wider than an octave.
    var isCompound: Bool { number > 8 }

    /// Whether this quality exists for this number (no "major 5th", no "diminished unison").
    var isValid: Bool {
        guard number >= 1 else { return false }
        if number == 1 { return quality == .perfect || quality == .augmented }
        return isPerfectType
            ? [.diminished, .perfect, .augmented].contains(quality)
            : [.diminished, .minor, .major, .augmented].contains(quality)
    }

    var semitones: Int {
        let base = Self.majorOrPerfectSemitones[(number - 1) % 7] + 12 * ((number - 1) / 7)
        switch quality {
        case .perfect, .major: return base
        case .minor:           return base - 1
        case .augmented:       return base + 1
        case .diminished:      return base - (isPerfectType ? 1 : 2)
        }
    }

    /// "Major 6th", "Perfect Octave".
    var name: String { "\(quality.name) \(Self.ordinal(number))" }

    /// "M6", "P8".
    var shortName: String { "\(quality.abbreviation)\(number)" }

    /// The interval you get by flipping the lower note up an octave: the numbers add up to 9
    /// and the quality flips (a major 6th inverts to a minor 3rd). Simple intervals only.
    var inversion: Interval? {
        guard number <= 8 else { return nil }
        return Interval(quality.inverted, 9 - number)
    }

    /// The same interval an octave wider (a major 3rd → a major 10th): add 7 to the number.
    var compound: Interval? {
        guard (2...7).contains(number) else { return nil }
        return Interval(quality, number + 7)
    }

    /// The same interval with the octave taken out (a major 10th → a major 3rd).
    var simple: Interval {
        number > 8 ? Interval(quality, number - 7) : self
    }

    static func ordinal(_ number: Int) -> String {
        switch number {
        case 1:  return "Unison"
        case 8:  return "Octave"
        case 15: return "Double Octave"
        default:
            let suffix: String
            switch (number % 10, number % 100) {
            case (1, let n) where n != 11: suffix = "st"
            case (2, let n) where n != 12: suffix = "nd"
            case (3, let n) where n != 13: suffix = "rd"
            default:                       suffix = "th"
            }
            return "\(number)\(suffix)"
        }
    }

    /// The interval between two written pitches, measured up from the lower one, or nil if it's
    /// beyond doubly augmented/diminished.
    static func between(_ a: SpelledPitch, _ b: SpelledPitch) -> Interval? {
        let (low, high) = (a.diatonicNumber, a.midi) <= (b.diatonicNumber, b.midi) ? (a, b) : (b, a)
        let number = high.diatonicNumber - low.diatonicNumber + 1
        let semitones = high.midi - low.midi
        let base = Interval(.perfect, number).isPerfectType ? Interval(.perfect, number) : Interval(.major, number)
        let difference = semitones - base.semitones
        let quality: IntervalQuality?
        if base.quality == .perfect {
            switch difference {
            case -1: quality = .diminished
            case 0:  quality = .perfect
            case 1:  quality = .augmented
            default: quality = nil
            }
        } else {
            switch difference {
            case -2: quality = .diminished
            case -1: quality = .minor
            case 0:  quality = .major
            case 1:  quality = .augmented
            default: quality = nil
            }
        }
        guard let quality else { return nil }
        let interval = Interval(quality, number)
        return interval.isValid ? interval : nil
    }

    // MARK: Pools

    /// Simple intervals the trainer asks about.
    static let simplePool: [Interval] = [
        Interval(.minor, 2), Interval(.major, 2), Interval(.minor, 3), Interval(.major, 3),
        Interval(.perfect, 4), Interval(.augmented, 4), Interval(.diminished, 5), Interval(.perfect, 5),
        Interval(.minor, 6), Interval(.major, 6), Interval(.minor, 7), Interval(.major, 7),
        Interval(.perfect, 8),
    ]

    /// Compound intervals (9ths to 13ths) for the bonus setting.
    static let compoundPool: [Interval] = [
        Interval(.minor, 9), Interval(.major, 9), Interval(.minor, 10), Interval(.major, 10),
        Interval(.perfect, 11), Interval(.augmented, 11), Interval(.diminished, 12), Interval(.perfect, 12),
        Interval(.minor, 13), Interval(.major, 13),
    ]

    /// Less common spellings that make good wrong answers: they sound the same as a pool interval
    /// (an augmented 5th is a minor 6th's sound) but students know the names.
    static let commonAlternates: [Interval] = [
        Interval(.augmented, 2), Interval(.augmented, 5), Interval(.augmented, 6), Interval(.diminished, 7),
    ]

    /// Names a student would recognise — the only ones used as answer choices.
    var isCommon: Bool {
        Self.simplePool.contains(self) || Self.compoundPool.contains(self) || Self.commonAlternates.contains(self)
    }

    /// Wrong answers that are close enough to make you think: the same number with another quality
    /// (minor vs major 6th), the same sound spelled another way (augmented 4th vs diminished 5th) or
    /// measured from the wrong note (its inversion), then the neighbouring numbers.
    func distractors(_ count: Int) -> [Interval] {
        let qualities: [IntervalQuality] = [.diminished, .minor, .perfect, .major, .augmented]
        func candidates(numbers: [Int]) -> [Interval] {
            numbers.flatMap { n in qualities.map { Interval($0, n) } }
        }
        let allowed: (Interval) -> Bool = { other in
            other != self && other.isValid && other.isCommon && (isCompound || !other.isCompound)
        }

        // 1. Same number, the other common quality.
        let sameNumber = candidates(numbers: [number]).filter(allowed)
        // 2. Same sound, different spelling; the inversion; the simple form of a compound.
        var sameSound = candidates(numbers: [number - 1, number + 1])
            .filter { $0.semitones == semitones }
        if let inversion { sameSound.append(inversion) }
        if isCompound { sameSound.append(simple) }
        sameSound = sameSound.filter(allowed)
        // 3. One number either side.
        let neighbours = candidates(numbers: [number - 1, number + 1]).filter(allowed)

        var picks: [Interval] = []
        for tier in [sameNumber, sameSound, neighbours] {
            if let pick = tier.shuffled().first(where: { !picks.contains($0) }) {
                picks.append(pick)
            }
        }
        for other in (sameNumber + sameSound + neighbours).shuffled() where !picks.contains(other) {
            picks.append(other)
        }
        return Array(picks.prefix(count))
    }
}
