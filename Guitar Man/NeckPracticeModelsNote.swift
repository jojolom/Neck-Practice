//
//  Note.swift
//  Neck Practice
//

/// The 12 chromatic notes in order.
enum Note: Int, CaseIterable, Identifiable, CustomStringConvertible, Codable {
    case c, cSharp, d, dSharp, e, f, fSharp, g, gSharp, a, aSharp, b

    var id: Int { rawValue }

    /// Primary display name (sharp spelling).
    var description: String {
        switch self {
        case .c:      return "C"
        case .cSharp: return "C#"
        case .d:      return "D"
        case .dSharp: return "D#"
        case .e:      return "E"
        case .f:      return "F"
        case .fSharp: return "F#"
        case .g:      return "G"
        case .gSharp: return "G#"
        case .a:      return "A"
        case .aSharp: return "A#"
        case .b:      return "B"
        }
    }

    /// Flat alias where applicable.
    var flatAlias: String? {
        switch self {
        case .cSharp: return "Db"
        case .dSharp: return "Eb"
        case .fSharp: return "Gb"
        case .gSharp: return "Ab"
        case .aSharp: return "Bb"
        default:      return nil
        }
    }

    /// Returns a display string that shows both names for enharmonics (e.g. "C# / Db").
    var displayName: String {
        if let flat = flatAlias {
            return "\(description) / \(flat)"
        }
        return description
    }

    var isNatural: Bool { flatAlias == nil }

    /// Diatonic letter index for staff positioning: C=0, D=1, E=2, F=3, G=4, A=5, B=6.
    /// Sharps/flats share their natural's position.
    var diatonicIndex: Int {
        switch self {
        case .c, .cSharp: return 0
        case .d, .dSharp: return 1
        case .e:          return 2
        case .f, .fSharp: return 3
        case .g, .gSharp: return 4
        case .a, .aSharp: return 5
        case .b:          return 6
        }
    }

    /// Whether the note needs a sharp symbol on the staff.
    var needsSharp: Bool { !isNatural }

    /// The note `n` semitones above this one.
    func advanced(by semitones: Int) -> Note {
        Note(rawValue: (rawValue + semitones + 120) % 12)!
    }

    /// Relative minor of a major key (3 semitones down).
    var relativeMinor: Note { advanced(by: -3) }

    /// Relative major of a minor key (3 semitones up).
    var relativeMajor: Note { advanced(by: 3) }

    /// Notes ordered by circle-of-fifths distance (closest first).
    /// P5 up, P4 up, M2 up, m7 up, M6 up, m3 up, M3 up, m6 up, m2 down, m2 up, tritone.
    func circleOfFifthsDistractors() -> [Note] {
        let distances = [7, 5, 2, 10, 9, 3, 4, 8, 11, 1, 6]
        return distances.map { self.advanced(by: $0) }
    }

    // MARK: - Enharmonic spelling

    private static let letterNames = ["C", "D", "E", "F", "G", "A", "B"]
    private static let naturalSemitones = [0, 2, 4, 5, 7, 9, 11]

    /// Preferred letter index (0=C … 6=B) and accidental offset when
    /// this note is used as a key root. Defaults to major-mode spelling.
    var keyLetterInfo: (letterIndex: Int, accidental: Int) {
        keyLetterInfo(asMinor: false)
    }

    /// Preferred letter index and accidental offset for this note as a
    /// key root in the given mode. Sharp-side keys flip between sharp
    /// (minor) and flat (major) spellings where convention differs:
    /// e.g. Db major vs C# minor; Ab major vs G# minor.
    func keyLetterInfo(asMinor: Bool) -> (letterIndex: Int, accidental: Int) {
        if asMinor {
            switch self {
            case .c:      return (0,  0)   // C
            case .cSharp: return (0,  1)   // C#m  (4 sharps)
            case .d:      return (1,  0)   // D
            case .dSharp: return (2, -1)   // Ebm  (6 flats)
            case .e:      return (2,  0)   // E
            case .f:      return (3,  0)   // F
            case .fSharp: return (3,  1)   // F#m  (3 sharps)
            case .g:      return (4,  0)   // G
            case .gSharp: return (4,  1)   // G#m  (5 sharps)
            case .a:      return (5,  0)   // A
            case .aSharp: return (6, -1)   // Bbm  (5 flats; preferred over A#m 7 sharps)
            case .b:      return (6,  0)   // B
            }
        }
        switch self {
        case .c:      return (0,  0)   // C
        case .cSharp: return (1, -1)   // Db
        case .d:      return (1,  0)   // D
        case .dSharp: return (2, -1)   // Eb
        case .e:      return (2,  0)   // E
        case .f:      return (3,  0)   // F
        case .fSharp: return (3,  1)   // F#
        case .g:      return (4,  0)   // G
        case .gSharp: return (5, -1)   // Ab
        case .a:      return (5,  0)   // A
        case .aSharp: return (6, -1)   // Bb
        case .b:      return (6,  0)   // B
        }
    }

    /// Display name for this note when used as a key root in the given mode,
    /// e.g. `Note.cSharp.keyName(asMinor: true)` → "C#" but
    ///      `Note.cSharp.keyName(asMinor: false)` → "Db".
    func keyName(asMinor: Bool) -> String {
        spelled(inKey: self, asDegree: 0, keyIsMinor: asMinor)
    }

    /// Diatonic degree index (0–6) of this note within the given key, or nil
    /// if the note isn't in the natural major/minor scale of that key.
    func diatonicDegree(inKey key: Note, asMinor: Bool) -> Int? {
        let intervals = asMinor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11]
        let distance = (self.rawValue - key.rawValue + 12) % 12
        return intervals.firstIndex(of: distance)
    }

    /// Enharmonic spelling of this note assuming it's a diatonic member of
    /// the given key. Non-diatonic notes fall back to the default sharp
    /// spelling. Use this anywhere a note appears in a key/chord context
    /// (triads, scales, pentatonics) so accidentals reflect the harmony.
    func spelled(inKey key: Note, asMinor: Bool) -> String {
        if let degree = diatonicDegree(inKey: key, asMinor: asMinor) {
            return spelled(inKey: key, asDegree: degree, keyIsMinor: asMinor)
        }
        return description
    }

    /// The enharmonically correct name for this note when it appears
    /// as the given scale degree (0-based) in the given key (major mode).
    ///
    /// Example: `Note.aSharp.spelled(inKey: .f, asDegree: 3)` → "Bb"
    func spelled(inKey key: Note, asDegree degreeIndex: Int) -> String {
        spelled(inKey: key, asDegree: degreeIndex, keyIsMinor: false)
    }

    /// The enharmonically correct name for this note when it appears as
    /// the given scale degree (0-based) in the given key, accounting for
    /// whether the key is minor.
    func spelled(inKey key: Note, asDegree degreeIndex: Int, keyIsMinor: Bool) -> String {
        let (rootLetter, _) = key.keyLetterInfo(asMinor: keyIsMinor)
        let targetLetter = (rootLetter + degreeIndex) % 7
        let naturalSemitone = Self.naturalSemitones[targetLetter]
        var accidental = (self.rawValue - naturalSemitone + 12) % 12
        if accidental > 6 { accidental -= 12 }

        let name = Self.letterNames[targetLetter]
        switch accidental {
        case  1: return "\(name)#"
        case -1: return "\(name)b"
        case  2: return "\(name)##"
        case -2: return "\(name)bb"
        default: return name
        }
    }

    // MARK: - Circle of fifths

    /// Notes in circle-of-fifths order starting at C, used as conventional
    /// major-key roots. Sharps clockwise from C, then flats counter-clockwise.
    static let circleOfFifthsMajorKeys: [Note] = [
        .c, .g, .d, .a, .e, .b, .fSharp, .cSharp, .gSharp, .dSharp, .aSharp, .f
    ]

    /// Notes in circle-of-fifths order starting at A, used as conventional
    /// minor-key roots. Sharps clockwise from A, then flats counter-clockwise.
    static let circleOfFifthsMinorKeys: [Note] = [
        .a, .e, .b, .fSharp, .cSharp, .gSharp, .dSharp, .aSharp, .f, .c, .g, .d
    ]

    /// Conventional key roots in circle-of-fifths order for the given mode.
    static func circleOfFifthsKeys(asMinor: Bool) -> [Note] {
        asMinor ? circleOfFifthsMinorKeys : circleOfFifthsMajorKeys
    }
}
