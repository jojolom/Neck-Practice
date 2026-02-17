//
//  Note.swift
//  Guitar Man
//

/// The 12 chromatic notes in order.
enum Note: Int, CaseIterable, Identifiable, CustomStringConvertible {
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

    /// The note `n` semitones above this one.
    func advanced(by semitones: Int) -> Note {
        Note(rawValue: (rawValue + semitones) % 12)!
    }
}
