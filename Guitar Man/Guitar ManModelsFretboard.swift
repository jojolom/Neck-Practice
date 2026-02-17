//
//  Fretboard.swift
//  Guitar Man
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

    /// Human-readable string label (e.g. "String 1 (e)", "String 6 (E)").
    var stringLabel: String {
        let labels = ["1 (e)", "2 (B)", "3 (G)", "4 (D)", "5 (A)", "6 (E)"]
        return "String \(labels[stringIndex])"
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
