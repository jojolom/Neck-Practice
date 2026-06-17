//
//  Pentatonic.swift
//  Neck Practice
//

import Foundation

// MARK: - PentatonicQuality

enum PentatonicQuality: CaseIterable, Codable {
    case minor, major

    var displayName: String {
        switch self {
        case .minor: return "Minor"
        case .major: return "Major"
        }
    }

    var isMinor: Bool { self == .minor }
}

// MARK: - PentatonicShape

/// One of the 5 pentatonic box positions.
///
/// `stringOffsets[i]` = [lowerOffset, higherOffset] for app stringIndex i
/// (0 = high e, 5 = low E), expressed as semitone offsets from `anchorFret`.
///
/// `anchorFret` is the fret on string 6 (low E) at offset 0. All actual
/// fret numbers = anchorFret + offset. Offsets may be negative (Position 5).
///
/// `rootMarkers` lists which (stringIndex, offsetIndex) pairs sound the root.
/// offsetIndex 0 = the lower value in the pair, 1 = the higher.
struct PentatonicShape: Identifiable {
    let id: Int   // 1–5
    let stringOffsets: [[Int]]   // [stringIndex 0..5][lowerOffset, higherOffset]
    let rootMarkers: [(stringIndex: Int, offsetIndex: Int)]

    /// The offset from anchorFret of the lowest fret in the entire shape.
    var minOffset: Int { stringOffsets.flatMap { $0 }.min() ?? 0 }

    /// The offset from anchorFret of the highest fret in the entire shape.
    var maxOffset: Int { stringOffsets.flatMap { $0 }.max() ?? 0 }

    /// The root offset on string 6 (stringIndex 5). Used to derive anchorFret.
    /// If string 6 has a root marker, use it; otherwise fall back to string 5 (A).
    var rootOffsetOnLowE: Int? {
        guard let marker = rootMarkers.first(where: { $0.stringIndex == 5 }) else { return nil }
        return stringOffsets[5][marker.offsetIndex]
    }

    /// Fall-back root on string 5 (A string) for positions without a low-E root.
    var rootOffsetOnAString: Int? {
        guard let marker = rootMarkers.first(where: { $0.stringIndex == 4 }) else { return nil }
        return stringOffsets[4][marker.offsetIndex]
    }
}

// MARK: - All 5 Shapes

/// All offsets are relative to anchorFret (fret on low E at offset 0).
/// Array order: [stringIndex 0 (high e), 1 (B), 2 (G), 3 (D), 4 (A), 5 (low E)]
let allPentatonicShapes: [PentatonicShape] = [

    // ── Position 1 — "The Blues Box" ─────────────────────────────────────
    // S6[0,3] S5[0,2] S4[0,2] S3[0,2] S2[0,3] S1[0,3]
    // Roots: S6@0, S4@2, S1@0
    PentatonicShape(
        id: 1,
        stringOffsets: [
            [0, 3],   // stringIndex 0 — high e (S1)
            [0, 3],   // stringIndex 1 — B     (S2)
            [0, 2],   // stringIndex 2 — G     (S3)
            [0, 2],   // stringIndex 3 — D     (S4)
            [0, 2],   // stringIndex 4 — A     (S5)
            [0, 3],   // stringIndex 5 — low E (S6)
        ],
        rootMarkers: [
            (stringIndex: 5, offsetIndex: 0),   // S6 lower note = root
            (stringIndex: 3, offsetIndex: 1),   // S4 higher note = root
            (stringIndex: 0, offsetIndex: 0),   // S1 lower note = root
        ]
    ),

    // ── Position 2 ───────────────────────────────────────────────────────
    // S6[3,5] S5[2,5] S4[2,5] S3[2,4] S2[3,5] S1[3,5]
    // Roots: S4@offset2 (offsetIndex 0), S2@offset5 (offsetIndex 1)
    PentatonicShape(
        id: 2,
        stringOffsets: [
            [3, 5],   // high e
            [3, 5],   // B
            [2, 4],   // G
            [2, 5],   // D
            [2, 5],   // A
            [3, 5],   // low E
        ],
        rootMarkers: [
            (stringIndex: 3, offsetIndex: 0),   // S4 lower note (offset 2) = root
            (stringIndex: 1, offsetIndex: 1),   // S2 higher note (offset 5) = root
        ]
    ),

    // ── Position 3 ───────────────────────────────────────────────────────
    // S6[5,7] S5[5,7] S4[5,7] S3[4,7] S2[5,8] S1[5,7]
    // Roots: S5@offset7 (offsetIndex 1), S2@offset5 (offsetIndex 0)
    PentatonicShape(
        id: 3,
        stringOffsets: [
            [5, 7],   // high e
            [5, 8],   // B  ← pinky stretch
            [4, 7],   // G  ← index stretch down
            [5, 7],   // D
            [5, 7],   // A
            [5, 7],   // low E
        ],
        rootMarkers: [
            (stringIndex: 4, offsetIndex: 1),   // S5 higher note (offset 7) = root
            (stringIndex: 1, offsetIndex: 0),   // S2 lower note (offset 5) = root
        ]
    ),

    // ── Position 4 ───────────────────────────────────────────────────────
    // S6[7,10] S5[7,10] S4[7,9] S3[7,9] S2[8,10] S1[7,10]
    // Roots: S5@offset7 (offsetIndex 0), S3@offset9 (offsetIndex 1)
    PentatonicShape(
        id: 4,
        stringOffsets: [
            [7, 10],   // high e
            [8, 10],   // B
            [7,  9],   // G
            [7,  9],   // D
            [7, 10],   // A
            [7, 10],   // low E
        ],
        rootMarkers: [
            (stringIndex: 4, offsetIndex: 0),   // S5 lower note (offset 7) = root
            (stringIndex: 2, offsetIndex: 1),   // S3 higher note (offset 9) = root
        ]
    ),

    // ── Position 5 ───────────────────────────────────────────────────────
    // S6[-2,0] S5[-2,0] S4[-3,0] S3[-3,0] S2[-2,0] S1[-2,0]
    // Roots: S6@offset0 (offsetIndex 1), S3@offset-3 (offsetIndex 0), S1@offset0 (offsetIndex 1)
    // Note: anchorFret must be ≥ 4 so that anchorFret-3 ≥ 1
    PentatonicShape(
        id: 5,
        stringOffsets: [
            [-2, 0],   // high e
            [-2, 0],   // B
            [-3, 0],   // G
            [-3, 0],   // D
            [-2, 0],   // A
            [-2, 0],   // low E
        ],
        rootMarkers: [
            (stringIndex: 5, offsetIndex: 1),   // S6 higher note (offset 0) = root
            (stringIndex: 2, offsetIndex: 0),   // S3 lower note (offset -3) = root
            (stringIndex: 0, offsetIndex: 1),   // S1 higher note (offset 0) = root
        ]
    ),
]

// MARK: - PentatonicQuestion

struct PentatonicQuestion {
    let shape: PentatonicShape
    let quality: PentatonicQuality
    let rootNote: Note
    /// Fret on low E (stringIndex 5) at offset 0.
    let anchorFret: Int

    /// All 12 fretboard positions in this shape.
    var shapePositions: [FretboardPosition] {
        shape.stringOffsets.enumerated().flatMap { stringIndex, offsets in
            offsets.map { offset in
                FretboardPosition(stringIndex: stringIndex, fret: anchorFret + offset)
            }
        }
    }

    /// The subset of positions that are root note markers.
    var rootPositions: Set<FretboardPosition> {
        Set(shape.rootMarkers.map { marker in
            FretboardPosition(
                stringIndex: marker.stringIndex,
                fret: anchorFret + shape.stringOffsets[marker.stringIndex][marker.offsetIndex]
            )
        })
    }

    /// The root note adjusted for quality — minor uses the raw root,
    /// major uses the relative major (3 semitones up).
    var effectiveRootNote: Note {
        switch quality {
        case .minor: return rootNote
        case .major: return rootNote.advanced(by: 3)
        }
    }

    /// Root positions adjusted for quality — for major pentatonic,
    /// highlights positions where the relative major root appears.
    var effectiveRootPositions: Set<FretboardPosition> {
        switch quality {
        case .minor: return rootPositions
        case .major:
            let majorRoot = effectiveRootNote
            return Set(shapePositions.filter { $0.note == majorRoot })
        }
    }

    /// Highest fret used — drives FretboardView maxFret.
    var maxFret: Int { anchorFret + shape.maxOffset }

    /// Lowest fret used — all dots must be ≥ 1.
    var minFret: Int { anchorFret + shape.minOffset }
}

// MARK: - Helpers

/// The fret on string 6 (low E, open = E) that sounds the given note.
/// Returns the lowest such fret (1–12).
func fretOnLowE(for note: Note) -> Int {
    // Low E open = Note.e (rawValue 4 in the enum: c=0,cSharp=1,...,e=4)
    let openE = Note.e.rawValue
    return (note.rawValue - openE + 12) % 12
}

/// The fret on string 5 (A, open = A) that sounds the given note.
func fretOnAString(for note: Note) -> Int {
    let openA = Note.a.rawValue
    return (note.rawValue - openA + 12) % 12
}
