//
//  RomanNumeral.swift
//  Neck Practice
//
//  Music theory types for diatonic scale degree (Roman Numeral) practice.
//

import Foundation

// MARK: - DiatonicScale

enum DiatonicScale: CaseIterable, Codable {
    case major, minor

    var displayName: String {
        switch self {
        case .major: return "Major"
        case .minor: return "Minor"
        }
    }

    var isMinor: Bool { self == .minor }

    /// Semitone intervals from the root for each scale degree (1–7).
    var intervals: [Int] {
        switch self {
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .minor: return [0, 2, 3, 5, 7, 8, 10]
        }
    }

    /// Chord quality for each scale degree (1–7).
    var chordQualities: [RNChordQuality] {
        switch self {
        case .major: return [.major, .minor, .minor, .major, .major, .minor, .diminished]
        case .minor: return [.minor, .diminished, .major, .minor, .minor, .major, .major]
        }
    }

    /// Roman numeral strings for each degree (1–7).
    var romanNumerals: [String] {
        switch self {
        case .major: return ["I", "ii", "iii", "IV", "V", "vi", "vii\u{00B0}"]
        case .minor: return ["i", "ii\u{00B0}", "III", "iv", "v", "VI", "VII"]
        }
    }
}

// MARK: - RNChordQuality

enum RNChordQuality: CaseIterable {
    case major, minor, diminished

    var displayName: String {
        switch self {
        case .major:      return "Major"
        case .minor:      return "Minor"
        case .diminished: return "Dim"
        }
    }

    /// Suffix for chord name display (e.g., "C Major", "Dm", "B°")
    var suffix: String {
        switch self {
        case .major:      return " Major"
        case .minor:      return "m"
        case .diminished: return "\u{00B0}"
        }
    }
}

// MARK: - RomanNumeralQuestion

struct RomanNumeralQuestion {
    let key: Note
    let scale: DiatonicScale
    let degree: Int                      // 1–7

    /// The roman numeral string for this degree.
    var romanNumeral: String {
        scale.romanNumerals[degree - 1]
    }

    /// The chord quality for this degree.
    var chordQuality: RNChordQuality {
        scale.chordQualities[degree - 1]
    }

    /// The root note of the chord at this degree.
    var chordRoot: Note {
        key.advanced(by: scale.intervals[degree - 1])
    }

    /// The chord root spelled correctly for this key context.
    var chordRootSpelled: String {
        chordRoot.spelled(inKey: key, asDegree: degree - 1, keyIsMinor: scale.isMinor)
    }

    /// Display name for the chord using correct enharmonic spelling.
    var chordDisplayName: String {
        "\(chordRootSpelled)\(chordQuality.suffix)"
    }

    /// Full key display using correct enharmonic spelling, e.g., "Bb Major"
    var keyDisplayName: String {
        "\(key.keyName(asMinor: scale.isMinor)) \(scale.displayName)"
    }

    /// All 7 chord display names in this key/scale (enharmonically correct).
    var allChordsInKey: [String] {
        (0..<7).map { i in
            let root = key.advanced(by: scale.intervals[i])
            let quality = scale.chordQualities[i]
            return "\(root.spelled(inKey: key, asDegree: i, keyIsMinor: scale.isMinor))\(quality.suffix)"
        }
    }

    /// All 7 chord root note names (enharmonically correct, no quality suffix).
    var allChordRootsInKey: [String] {
        (0..<7).map { i in
            key.advanced(by: scale.intervals[i]).spelled(inKey: key, asDegree: i, keyIsMinor: scale.isMinor)
        }
    }
}
