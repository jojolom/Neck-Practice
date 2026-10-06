//
//  Composition.swift
//  Guitar Man
//
//  A chord progression the student writes by dropping Roman numerals onto a staff: a key,
//  2–8 measures, and one note value for every chord (quarter, half, dotted half, or whole —
//  dotted halves put it in 3/4). The app never plays it; the student does. Saved compositions
//  live in UserDefaults as JSON, like practice plans.
//

import Foundation
import Observation

// MARK: - Composition

struct Composition: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String = "Untitled"
    var keyRoot: Note = .c
    var isMinor: Bool = false
    var measureCount: Int = 4
    var noteValue: NoteValue = .whole
    /// The chord in each slot as a scale degree (1–7), or nil for an empty slot.
    /// There are `measureCount × slotsPerMeasure` slots.
    var slots: [Int?] = Array(repeating: nil, count: 4)
    var updatedAt: Date = .now

    static let measureRange = 2...8

    var beatsPerMeasure: Int { noteValue == .dottedHalf ? 3 : 4 }
    var slotsPerMeasure: Int { beatsPerMeasure / noteValue.beats }
    var slotCount: Int { measureCount * slotsPerMeasure }

    var scale: DiatonicScale { isMinor ? .minor : .major }
    var keySignature: KeySignature { KeySignature(root: keyRoot, isMinor: isMinor) }

    /// "E♭ Major".
    var keyName: String { isMinor ? keySignature.minorKeyName : keySignature.majorKeyName }

    var isEmpty: Bool { slots.allSatisfy { $0 == nil } }

    /// Changes the measure count and/or note value, keeping each chord where it falls in time:
    /// a chord at the start of measure 2 stays at the start of measure 2. Chords that no longer
    /// fit (past the last measure, or two landing in one slot) are dropped.
    mutating func reshape(measureCount newCount: Int, noteValue newValue: NoteValue) {
        let oldSlotsPerMeasure = slotsPerMeasure
        let oldBeats = noteValue.beats
        let old = slots
        measureCount = min(max(newCount, Self.measureRange.lowerBound), Self.measureRange.upperBound)
        noteValue = newValue
        var reshaped = [Int?](repeating: nil, count: slotCount)
        for (i, chord) in old.enumerated() {
            guard let chord else { continue }
            let measure = i / oldSlotsPerMeasure
            let beat = (i % oldSlotsPerMeasure) * oldBeats
            guard measure < measureCount, beat < beatsPerMeasure else { continue }
            let slot = measure * slotsPerMeasure + beat / noteValue.beats
            if reshaped[slot] == nil { reshaped[slot] = chord }
        }
        slots = reshaped
    }

    // MARK: Chords

    /// The chord on scale degree `degree` (1–7) of this key.
    func chord(degree: Int) -> CompositionChord {
        CompositionChord(degree: degree, keySignature: keySignature, isMinor: isMinor)
    }
}

// MARK: - CompositionChord

/// A diatonic triad in a key: its Roman numeral, name (IV in E♭ = A♭), and notes.
struct CompositionChord: Hashable {
    let degree: Int
    let keySignature: KeySignature
    let isMinor: Bool

    private var scale: DiatonicScale { isMinor ? .minor : .major }
    private var tonicLetter: Int { isMinor ? keySignature.minorTonic.letter : keySignature.majorTonic.letter }

    var romanNumeral: String { scale.romanNumerals[degree - 1] }
    var quality: RNChordQuality { scale.chordQualities[degree - 1] }

    /// Root, 3rd, 5th, stacked in thirds from the root around the middle of the staff.
    var pitches: [SpelledPitch] {
        let rootLetter = (tonicLetter + degree - 1) % 7
        // Concert octave 3 is written in octave 4: roots from C to B sit on or just below the staff.
        return [0, 2, 4].map { step in
            let letter = (rootLetter + step) % 7
            let octave = 3 + (rootLetter + step) / 7
            return keySignature.pitch(letter: letter, octave: octave)
        }
    }

    /// "A♭", "Fm", "B°".
    var name: String {
        let root = pitches[0].name
        switch quality {
        case .major:      return root
        case .minor:      return root + "m"
        case .diminished: return root + "°"
        }
    }

    /// "A♭ major".
    var longName: String { "\(pitches[0].name) \(quality == .diminished ? "diminished" : quality.displayName.lowercased())" }

    /// Pitch classes of the three notes, for ChordAnalyzer.
    var pitchClasses: Set<Int> { Set(pitches.map { $0.note.rawValue }) }
}

// MARK: - CompositionStore

/// Saved compositions, newest first.
@Observable
final class CompositionStore {
    private(set) var compositions: [Composition] = []

    private static let key = "compositions.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([Composition].self, from: data) {
            compositions = decoded.sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    /// Adds `composition`, or replaces the saved one with the same id.
    func save(_ composition: Composition) {
        var updated = composition
        updated.updatedAt = .now
        compositions.removeAll { $0.id == updated.id }
        compositions.insert(updated, at: 0)
        persist()
    }

    func delete(_ id: UUID) {
        compositions.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(compositions) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
