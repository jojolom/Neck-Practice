//
//  Triad.swift
//  Guitar Man
//

import Foundation

// MARK: - Enums

enum TriadQuality: CaseIterable {
    case major, minor

    var displayName: String {
        switch self {
        case .major: return "Major"
        case .minor: return "Minor"
        }
    }
}

enum TriadInversion {
    case root, first, second

    var displayName: String {
        switch self {
        case .root:   return "Root Position"
        case .first:  return "1st Inversion"
        case .second: return "2nd Inversion"
        }
    }
}

enum StringGroup: CaseIterable {
    case strings1_2_3   // high e (0), B (1), G (2)
    case strings2_3_4   // B (1), G (2), D (3)

    var displayName: String {
        switch self {
        case .strings1_2_3: return "Strings 1–2–3"
        case .strings2_3_4: return "Strings 2–3–4"
        }
    }

    /// String indices from lowest-pitched to highest-pitched within the group.
    /// e.g. strings1_2_3 → [G=2, B=1, e=0]
    var stringIndices: [Int] {
        switch self {
        case .strings1_2_3: return [2, 1, 0]
        case .strings2_3_4: return [3, 2, 1]
        }
    }
}

// MARK: - TriadShape

/// One of the 12 three-string triad shapes.
struct TriadShape: Identifiable {
    let id: String
    let quality: TriadQuality
    let inversion: TriadInversion
    let stringGroup: StringGroup

    /// Fret offsets from the lowest fret in the shape, ordered [lowestString, midString, highestString].
    /// Minimum value is always 0.
    let fretOffsets: [Int]

    /// The string index (0=high e…5=low E) that holds the root note.
    let rootStringIndex: Int

    /// Which index in `stringIndices` corresponds to the root string.
    var rootOffsetIndex: Int {
        stringGroup.stringIndices.firstIndex(of: rootStringIndex)!
    }
}

// MARK: - All Shapes

let allTriadShapes: [TriadShape] = [
    // ── Strings 1-2-3 (G=2, B=1, e=0) ──────────────────────────────────
    // fretOffsets order: [G-offset, B-offset, e-offset]

    TriadShape(id: "maj-root-123",  quality: .major, inversion: .root,
               stringGroup: .strings1_2_3, fretOffsets: [1, 1, 0], rootStringIndex: 2),

    TriadShape(id: "maj-first-123", quality: .major, inversion: .first,
               stringGroup: .strings1_2_3, fretOffsets: [1, 0, 1], rootStringIndex: 0),

    TriadShape(id: "maj-sec-123",   quality: .major, inversion: .second,
               stringGroup: .strings1_2_3, fretOffsets: [0, 1, 1], rootStringIndex: 1),

    TriadShape(id: "min-root-123",  quality: .minor, inversion: .root,
               stringGroup: .strings1_2_3, fretOffsets: [1, 0, 0], rootStringIndex: 2),

    TriadShape(id: "min-first-123", quality: .minor, inversion: .first,
               stringGroup: .strings1_2_3, fretOffsets: [0, 0, 1], rootStringIndex: 0),

    TriadShape(id: "min-sec-123",   quality: .minor, inversion: .second,
               stringGroup: .strings1_2_3, fretOffsets: [0, 1, 0], rootStringIndex: 1),

    // ── Strings 2-3-4 (D=3, G=2, B=1) ──────────────────────────────────
    // fretOffsets order: [D-offset, G-offset, B-offset]

    TriadShape(id: "maj-root-234",  quality: .major, inversion: .root,
               stringGroup: .strings2_3_4, fretOffsets: [2, 1, 0], rootStringIndex: 3),

    TriadShape(id: "maj-first-234", quality: .major, inversion: .first,
               stringGroup: .strings2_3_4, fretOffsets: [2, 0, 1], rootStringIndex: 1),

    TriadShape(id: "maj-sec-234",   quality: .major, inversion: .second,
               stringGroup: .strings2_3_4, fretOffsets: [0, 0, 0], rootStringIndex: 2),

    TriadShape(id: "min-root-234",  quality: .minor, inversion: .root,
               stringGroup: .strings2_3_4, fretOffsets: [2, 0, 0], rootStringIndex: 3),

    TriadShape(id: "min-first-234", quality: .minor, inversion: .first,
               stringGroup: .strings2_3_4, fretOffsets: [1, 0, 1], rootStringIndex: 1),

    TriadShape(id: "min-sec-234",   quality: .minor, inversion: .second,
               stringGroup: .strings2_3_4, fretOffsets: [1, 1, 0], rootStringIndex: 2),
]

// MARK: - TriadQuestion

struct TriadQuestion {
    let shape: TriadShape
    /// The fret of the lowest-offset dot in the shape.
    let baseFret: Int

    /// The three fretboard positions that make up this triad.
    var triadPositions: [FretboardPosition] {
        zip(shape.stringGroup.stringIndices, shape.fretOffsets).map { stringIndex, offset in
            FretboardPosition(stringIndex: stringIndex, fret: baseFret + offset)
        }
    }

    /// The position of the root note dot.
    var rootPosition: FretboardPosition {
        FretboardPosition(stringIndex: shape.rootStringIndex,
                          fret: baseFret + shape.fretOffsets[shape.rootOffsetIndex])
    }

    /// The actual root note at this fret position.
    var rootNote: Note {
        rootPosition.note
    }

    /// The highest fret used by this shape.
    var maxFret: Int {
        baseFret + (shape.fretOffsets.max() ?? 0)
    }
}
