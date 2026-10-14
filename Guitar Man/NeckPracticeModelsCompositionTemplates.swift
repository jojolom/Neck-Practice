//
//  CompositionTemplates.swift
//  Guitar Man
//
//  Progressions to start a composition from (Compose ▸ Start From a Progression). Written as
//  Roman numerals, so changing the key afterwards plays the same progression in the new key.
//

import Foundation

struct CompositionTemplate: Identifiable, Hashable {
    let id: String
    let name: String
    /// One line on what it is or where you've heard it.
    let detail: String
    let isMinor: Bool
    let beatsPerMeasure: Int
    /// Each measure's chords, each filling an equal share of the measure.
    let measures: [[ChordSymbol]]

    /// A new composition holding this progression, in C major or A minor.
    func makeComposition() -> Composition {
        var composition = Composition()
        composition.name = name
        composition.isMinor = isMinor
        composition.keyRoot = isMinor ? .a : .c
        composition.setBeatsPerMeasure(beatsPerMeasure)
        composition.setMeasureCount(measures.count)
        for (index, chords) in measures.enumerated() where !chords.isEmpty {
            let beats = beatsPerMeasure / chords.count
            for (i, symbol) in chords.enumerated() {
                composition.place(symbol, at: index * beatsPerMeasure + i * beats, value: NoteValue(beats: beats) ?? .quarter)
            }
        }
        return composition
    }

    /// "I V vi IV".
    var numerals: String {
        let composition = makeComposition()
        var seen: [String] = []
        for placed in composition.chords {
            let numeral = composition.chord(placed.symbol).romanNumeral
            if seen.last != numeral { seen.append(numeral) }
        }
        return seen.joined(separator: " – ")
    }

    private static func c(_ degree: Int, _ kind: ChordKind = .triad, shift: Int = 0) -> ChordSymbol {
        ChordSymbol(degree: degree, shift: shift, kind: kind)
    }

    static let all: [CompositionTemplate] = [
        CompositionTemplate(id: "pop", name: "Pop Progression",
                            detail: "The four chords behind countless hits.",
                            isMinor: false, beatsPerMeasure: 4,
                            measures: [[c(1)], [c(5)], [c(6)], [c(4)]]),
        CompositionTemplate(id: "fifties", name: "’50s Progression",
                            detail: "Doo-wop and early rock and roll.",
                            isMinor: false, beatsPerMeasure: 4,
                            measures: [[c(1)], [c(6)], [c(4)], [c(5)]]),
        CompositionTemplate(id: "two-five-one", name: "Jazz ii–V–I",
                            detail: "The cadence at the heart of jazz, in seventh chords.",
                            isMinor: false, beatsPerMeasure: 4,
                            measures: [[c(2, .seventh)], [c(5, .seventh)], [c(1, .seventh)], [c(1, .seventh)]]),
        CompositionTemplate(id: "blues", name: "12-Bar Blues",
                            detail: "Three dominant 7ths, twelve bars, with a quick change.",
                            isMinor: false, beatsPerMeasure: 4,
                            measures: [[c(1, .dominant7)], [c(4, .dominant7)], [c(1, .dominant7)], [c(1, .dominant7)],
                                       [c(4, .dominant7)], [c(4, .dominant7)], [c(1, .dominant7)], [c(1, .dominant7)],
                                       [c(5, .dominant7)], [c(4, .dominant7)], [c(1, .dominant7)], [c(5, .dominant7)]]),
        CompositionTemplate(id: "canon", name: "Canon Progression",
                            detail: "Pachelbel’s Canon, two chords a bar.",
                            isMinor: false, beatsPerMeasure: 4,
                            measures: [[c(1), c(5)], [c(6), c(3)], [c(4), c(1)], [c(4), c(5)]]),
        CompositionTemplate(id: "waltz", name: "Three-Chord Waltz",
                            detail: "I, IV and V in 3/4 time.",
                            isMinor: false, beatsPerMeasure: 3,
                            measures: [[c(1)], [c(4)], [c(5)], [c(1)]]),
        CompositionTemplate(id: "andalusian", name: "Andalusian Cadence",
                            detail: "Flamenco’s descending minor line, ending on a major V.",
                            isMinor: true, beatsPerMeasure: 4,
                            measures: [[c(1)], [c(7)], [c(6)], [c(5, .major)]]),
        CompositionTemplate(id: "minor-ballad", name: "Minor Ballad",
                            detail: "The pop progression’s moodier relative.",
                            isMinor: true, beatsPerMeasure: 4,
                            measures: [[c(1)], [c(6)], [c(3)], [c(7)]]),
    ]
}
