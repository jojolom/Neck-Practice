//
//  Composition.swift
//  Guitar Man
//
//  A chord progression the student writes by dropping Roman numerals onto a staff: a key, 4/4
//  or 3/4 time, 2–8 measures, and chords of any length from a quarter to a whole note, placed
//  on any beat. Beats with no chord are rests, so every measure always adds up. Chords never
//  cross a barline or overlap: one that wouldn't fit is shortened to fit. The student plays it
//  (the app only plays it with the hidden option in CompositionPlayer). Saved compositions live
//  in UserDefaults as JSON, like practice plans; ones saved before chords had their own lengths
//  load as the same music.
//

import Foundation
import Observation

// MARK: - Composition

struct Composition: Identifiable, Hashable {
    var id = UUID()
    var name: String = "Untitled"
    var keyRoot: Note = .c
    var isMinor: Bool = false
    private(set) var measureCount: Int = 4
    /// 4 (4/4) or 3 (3/4).
    private(set) var beatsPerMeasure: Int = 4
    /// The chords in order; see the header for the rules they keep.
    private(set) var chords: [PlacedChord] = []
    var updatedAt: Date = .now

    static let measureRange = 2...8
    static let meters = [4, 3]

    /// A chord on beat `start` (counting quarter-note beats from the start of the piece).
    struct PlacedChord: Codable, Hashable, Identifiable {
        var start: Int
        var beats: Int
        /// Scale degree, 1–7.
        var degree: Int

        var id: Int { start }
        var end: Int { start + beats }
        var value: NoteValue { NoteValue(beats: beats) ?? .quarter }
    }

    /// A gap between chords, written as one rest symbol: `glyph` is the rest's note value.
    struct Rest: Hashable {
        var start: Int
        var beats: Int
        var glyph: NoteValue
    }

    var totalBeats: Int { measureCount * beatsPerMeasure }

    var scale: DiatonicScale { isMinor ? .minor : .major }
    var keySignature: KeySignature { KeySignature(root: keyRoot, isMinor: isMinor) }

    /// "E♭ Major".
    var keyName: String { isMinor ? keySignature.minorKeyName : keySignature.majorKeyName }

    /// "4/4".
    var meterName: String { "\(beatsPerMeasure)/4" }

    var isEmpty: Bool { chords.isEmpty }

    /// Note values that fit in a measure of this meter.
    var noteValues: [NoteValue] { NoteValue.allCases.filter { $0.beats <= beatsPerMeasure } }

    /// The chord sounding on `beat`, if any.
    func chord(covering beat: Int) -> PlacedChord? {
        chords.first { $0.start <= beat && beat < $0.end }
    }

    /// The longest a chord starting on `beat` could be: to the next chord or the barline.
    func room(at beat: Int) -> Int {
        let barline = (beat / beatsPerMeasure + 1) * beatsPerMeasure
        let next = chords.first { $0.start > beat }?.start ?? barline
        return max(0, min(barline, next) - beat)
    }

    // MARK: Editing

    /// Puts `degree` on `beat` for `value`, shortened to fit before the next chord or the barline.
    /// A chord already starting there is replaced; one still ringing there is cut short. Returns
    /// the beats the new chord got (less than `value` when it had to be shortened), or nil if
    /// `beat` is outside the piece.
    @discardableResult
    mutating func place(_ degree: Int, at beat: Int, value: NoteValue) -> Int? {
        guard (0..<totalBeats).contains(beat), (1...7).contains(degree) else { return nil }
        chords.removeAll { $0.start == beat }
        if let ringing = chords.firstIndex(where: { $0.start < beat && beat < $0.end }) {
            chords[ringing].beats = beat - chords[ringing].start
        }
        let beats = min(value.beats, room(at: beat))
        chords.append(PlacedChord(start: beat, beats: beats, degree: degree))
        chords.sort { $0.start < $1.start }
        return beats
    }

    /// Removes the chord sounding on `beat`, leaving rests.
    mutating func removeChord(covering beat: Int) {
        chords.removeAll { $0.start <= beat && beat < $0.end }
    }

    /// Makes the chord starting on `start` last `value`, shortened to fit like `place`.
    mutating func setLength(ofChordAt start: Int, to value: NoteValue) {
        guard let index = chords.firstIndex(where: { $0.start == start }) else { return }
        let others = chords.filter { $0.start != start }
        let barline = (start / beatsPerMeasure + 1) * beatsPerMeasure
        let next = others.first { $0.start > start }?.start ?? barline
        chords[index].beats = max(1, min(value.beats, min(barline, next) - start))
    }

    mutating func clearChords() { chords = [] }

    /// Changes the number of measures; chords in measures that go away are dropped.
    mutating func setMeasureCount(_ count: Int) {
        measureCount = min(max(count, Self.measureRange.lowerBound), Self.measureRange.upperBound)
        let end = totalBeats
        chords.removeAll { $0.start >= end }
    }

    /// Changes the meter, keeping each chord in its measure on the same beat. Going from 4/4 to
    /// 3/4, a chord on beat 4 is dropped and longer ones are shortened to the new barline.
    mutating func setBeatsPerMeasure(_ beats: Int) {
        guard Self.meters.contains(beats), beats != beatsPerMeasure else { return }
        let old = beatsPerMeasure
        beatsPerMeasure = beats
        chords = chords.compactMap { chord in
            let measure = chord.start / old, offset = chord.start % old
            guard offset < beats else { return nil }
            return PlacedChord(start: measure * beats + offset, beats: min(chord.beats, beats - offset),
                               degree: chord.degree)
        }
    }

    // MARK: Rests

    /// The rests filling measure `measure`'s gaps, as they're written: a whole rest for an empty
    /// measure (in any meter), a half rest for two free beats starting the measure (or its
    /// second half, in 4/4), and quarter rests otherwise.
    func rests(inMeasure measure: Int) -> [Rest] {
        let first = measure * beatsPerMeasure, last = first + beatsPerMeasure
        let inMeasure = chords.filter { $0.start >= first && $0.start < last }
        if inMeasure.isEmpty { return [Rest(start: first, beats: beatsPerMeasure, glyph: .whole)] }
        var rests: [Rest] = []
        var beat = first
        while beat < last {
            if let chord = inMeasure.first(where: { $0.start == beat }) {
                beat = chord.end
                continue
            }
            let offset = beat - first
            let strong = offset == 0 || (beatsPerMeasure == 4 && offset == 2)
            if strong && beat + 1 < last && chord(covering: beat + 1) == nil {
                rests.append(Rest(start: beat, beats: 2, glyph: .half))
                beat += 2
            } else {
                rests.append(Rest(start: beat, beats: 1, glyph: .quarter))
                beat += 1
            }
        }
        return rests
    }

    // MARK: Chords

    /// The chord on scale degree `degree` (1–7) of this key.
    func chord(degree: Int) -> CompositionChord {
        CompositionChord(degree: degree, keySignature: keySignature, isMinor: isMinor)
    }
}

// MARK: - Saving

extension Composition: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, keyRoot, isMinor, measureCount, beatsPerMeasure, chords, updatedAt
        // Before chords had their own lengths: one note value for all, and one chord (or nil) per slot.
        case noteValue, slots
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        keyRoot = try c.decode(Note.self, forKey: .keyRoot)
        isMinor = try c.decode(Bool.self, forKey: .isMinor)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        let measures = try c.decode(Int.self, forKey: .measureCount)
        measureCount = min(max(measures, Self.measureRange.lowerBound), Self.measureRange.upperBound)
        if let chords = try c.decodeIfPresent([PlacedChord].self, forKey: .chords) {
            let beats = try c.decode(Int.self, forKey: .beatsPerMeasure)
            beatsPerMeasure = Self.meters.contains(beats) ? beats : 4
            // Re-apply the rules, in case the saved data was ever out of shape.
            for chord in chords.sorted(by: { $0.start < $1.start }) {
                place(chord.degree, at: chord.start, value: NoteValue(beats: chord.beats) ?? .quarter)
            }
        } else {
            let value = try c.decode(NoteValue.self, forKey: .noteValue)
            let slots = try c.decode([Int?].self, forKey: .slots)
            beatsPerMeasure = value == .dottedHalf ? 3 : 4
            for (slot, degree) in slots.enumerated() {
                if let degree { place(degree, at: slot * value.beats, value: value) }
            }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(keyRoot, forKey: .keyRoot)
        try c.encode(isMinor, forKey: .isMinor)
        try c.encode(measureCount, forKey: .measureCount)
        try c.encode(beatsPerMeasure, forKey: .beatsPerMeasure)
        try c.encode(chords, forKey: .chords)
        try c.encode(updatedAt, forKey: .updatedAt)
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
