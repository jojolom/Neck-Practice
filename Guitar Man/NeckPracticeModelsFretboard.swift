//
//  Fretboard.swift
//  Neck Practice
//

/// Standard tuning open-string notes, from string 1 (high e) to string 6 (low E).
/// Index 0 = string 1 (thinnest / highest pitch).
let standardTuning: [Note] = [.e, .b, .g, .d, .a, .e]

/// The total number of frets shown on the fretboard (0 = open string).
let fretCount = 13   // frets 0–12

/// The total number of strings on the guitar.
let stringCount = 6

/// A unique position on the fretboard.
struct FretboardPosition: Hashable, Identifiable {
    /// 0 = high e (thinnest), 5 = low E (thickest).
    let stringIndex: Int
    /// 0 = open string, 1–12 = frets 1–12.
    let fret: Int

    var id: String { "\(stringIndex)-\(fret)" }

    /// The note sounding at this position in standard tuning.
    var note: Note {
        standardTuning[stringIndex].advanced(by: fret)
    }

    /// MIDI note numbers for open strings: E4=64, B3=59, G3=55, D3=50, A2=45, E2=40.
    private static let openStringMidi: [Int] = [64, 59, 55, 50, 45, 40]

    /// The MIDI note number for this position (used for pitch comparison).
    var midiNote: Int { Self.openStringMidi[stringIndex] + fret }

    /// The concert octave of this position's pitch.
    var octave: Int { midiNote / 12 - 1 }

    /// Human-readable string label (e.g. "String 1 - e String", "String 6 - E String").
    var stringLabel: String {
        let numbers = ["1", "2", "3", "4", "5", "6"]
        let letters = ["e", "B", "G", "D", "A", "E"]
        return "String \(numbers[stringIndex]) - \(letters[stringIndex]) String"
    }
}

/// All positions within a given fret range.
func positions(frets: ClosedRange<Int> = 0...12) -> [FretboardPosition] {
    frets.flatMap { fret in
        (0..<stringCount).map { string in
            FretboardPosition(stringIndex: string, fret: fret)
        }
    }
}
