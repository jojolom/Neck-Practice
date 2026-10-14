//
//  Composition.swift
//  Guitar Man
//
//  A piece the student writes on a staff: a key, 4/4 or 3/4 time, 2–16 measures, a chord
//  progression, and optionally a melody over it.
//
//  Chords (see ChordSymbol) last from a quarter to a whole note and can start on any beat.
//  Melody notes are single pitches from an eighth to a whole note, on any eighth. Each line
//  keeps the same rules on its own: nothing crosses a barline or overlaps, so something that
//  wouldn't fit is shortened to fit, and the gaps are rests, so every measure always adds up.
//  The student plays it (the app only plays it with the hidden option in CompositionPlayer).
//
//  Saved compositions live in UserDefaults as JSON, like practice plans; ones saved before
//  chords had their own lengths, or before chord kinds and melodies, load as the same music.
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
    /// The melody's notes in order, on its own timeline in eighths.
    private(set) var melody: [MelodyNote] = []
    var updatedAt: Date = .now

    static let measureRange = 2...16
    static let meters = [4, 3]

    /// A chord on beat `start` (counting quarter-note beats from the start of the piece).
    struct PlacedChord: Hashable, Identifiable {
        var start: Int
        var beats: Int
        var symbol: ChordSymbol

        var id: Int { start }
        var end: Int { start + beats }
        var value: NoteValue { NoteValue(beats: beats) ?? .quarter }
    }

    /// A melody note on eighth `start` (counting eighth notes from the start of the piece).
    struct MelodyNote: Codable, Hashable, Identifiable {
        var start: Int
        /// In eighths: 1, 2, 3, 4, 6 or 8.
        var length: Int
        var pitch: SpelledPitch

        var id: Int { start }
        var end: Int { start + length }
        var value: NoteValue { NoteValue(eighths: length) ?? .eighth }
    }

    /// A gap between chords, written as one rest symbol: `glyph` is the rest's note value.
    struct Rest: Hashable {
        var start: Int
        var beats: Int
        var glyph: NoteValue
    }

    /// A gap in the melody, in eighths.
    struct MelodyRest: Hashable {
        var start: Int
        var length: Int
        var glyph: NoteValue
    }

    var totalBeats: Int { measureCount * beatsPerMeasure }
    var eighthsPerMeasure: Int { beatsPerMeasure * 2 }
    var totalEighths: Int { totalBeats * 2 }

    var scale: DiatonicScale { isMinor ? .minor : .major }
    var keySignature: KeySignature { KeySignature(root: keyRoot, isMinor: isMinor) }

    /// "E♭ Major".
    var keyName: String { isMinor ? keySignature.minorKeyName : keySignature.majorKeyName }

    /// "4/4".
    var meterName: String { "\(beatsPerMeasure)/4" }

    var isEmpty: Bool { chords.isEmpty && melody.isEmpty }
    var hasMelody: Bool { !melody.isEmpty }

    /// Chord lengths that fit in a measure of this meter.
    var noteValues: [NoteValue] { NoteValue.chordValues.filter { $0.beats <= beatsPerMeasure } }

    /// Melody note lengths that fit in a measure of this meter.
    var melodyValues: [NoteValue] { NoteValue.allCases.filter { $0.eighths <= eighthsPerMeasure } }

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

    /// The melody note sounding on eighth `tick`, if any.
    func note(covering tick: Int) -> MelodyNote? {
        melody.first { $0.start <= tick && tick < $0.end }
    }

    /// The longest a melody note starting on `tick` could be, in eighths.
    func noteRoom(at tick: Int) -> Int {
        let barline = (tick / eighthsPerMeasure + 1) * eighthsPerMeasure
        let next = melody.first { $0.start > tick }?.start ?? barline
        return max(0, min(barline, next) - tick)
    }

    // MARK: Editing chords

    /// Puts `symbol` on `beat` for `value`, shortened to fit before the next chord or the barline.
    /// A chord already starting there is replaced; one still ringing there is cut short. Returns
    /// the beats the new chord got (less than `value` when it had to be shortened), or nil if
    /// `beat` is outside the piece.
    @discardableResult
    mutating func place(_ symbol: ChordSymbol, at beat: Int, value: NoteValue) -> Int? {
        guard (0..<totalBeats).contains(beat), symbol.isValid else { return nil }
        chords.removeAll { $0.start == beat }
        if let ringing = chords.firstIndex(where: { $0.start < beat && beat < $0.end }) {
            chords[ringing].beats = beat - chords[ringing].start
        }
        let beats = min(max(value.beats, 1), room(at: beat))
        chords.append(PlacedChord(start: beat, beats: beats, symbol: symbol))
        chords.sort { $0.start < $1.start }
        return beats
    }

    /// Puts the key's own triad on `degree` (1–7): see `place(_:at:value:)`.
    @discardableResult
    mutating func place(_ degree: Int, at beat: Int, value: NoteValue) -> Int? {
        place(ChordSymbol(degree: degree), at: beat, value: value)
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

    /// Changes the chord starting on `start` (its kind, inversion, …), keeping its place and length.
    mutating func setSymbol(ofChordAt start: Int, to symbol: ChordSymbol) {
        guard symbol.isValid, let index = chords.firstIndex(where: { $0.start == start }) else { return }
        chords[index].symbol = symbol
    }

    mutating func clearChords() { chords = [] }

    // MARK: Editing the melody

    /// Puts `pitch` on eighth `tick` for `value`, shortened to the longest note value that fits
    /// before the next note or the barline. A note already starting there is replaced; one still
    /// ringing is cut short (to the longest value that fits). Returns the value the note got, or
    /// nil if `tick` is outside the piece.
    @discardableResult
    mutating func placeNote(_ pitch: SpelledPitch, at tick: Int, value: NoteValue) -> NoteValue? {
        guard (0..<totalEighths).contains(tick) else { return nil }
        melody.removeAll { $0.start == tick }
        if let ringing = melody.firstIndex(where: { $0.start < tick && tick < $0.end }) {
            melody[ringing].length = NoteValue.longest(fitting: tick - melody[ringing].start)?.eighths ?? 1
        }
        guard let fitted = NoteValue.longest(fitting: min(value.eighths, noteRoom(at: tick))) else { return nil }
        melody.append(MelodyNote(start: tick, length: fitted.eighths, pitch: pitch))
        melody.sort { $0.start < $1.start }
        return fitted
    }

    mutating func removeNote(covering tick: Int) {
        melody.removeAll { $0.start <= tick && tick < $0.end }
    }

    /// Makes the note starting on `start` last `value`, shortened to fit like `placeNote`.
    mutating func setLength(ofNoteAt start: Int, to value: NoteValue) {
        guard let index = melody.firstIndex(where: { $0.start == start }) else { return }
        let barline = (start / eighthsPerMeasure + 1) * eighthsPerMeasure
        let next = melody.first { $0.start > start }?.start ?? barline
        melody[index].length = NoteValue.longest(fitting: min(value.eighths, min(barline, next) - start))?.eighths ?? 1
    }

    mutating func clearMelody() { melody = [] }

    // MARK: Measures and meter

    /// Changes the number of measures; chords and notes in measures that go away are dropped.
    mutating func setMeasureCount(_ count: Int) {
        measureCount = min(max(count, Self.measureRange.lowerBound), Self.measureRange.upperBound)
        let end = totalBeats
        chords.removeAll { $0.start >= end }
        melody.removeAll { $0.start >= end * 2 }
    }

    /// Changes the meter, keeping each chord and note in its measure at the same place. Going from
    /// 4/4 to 3/4, ones on beat 4 are dropped and longer ones are shortened to the new barline.
    mutating func setBeatsPerMeasure(_ beats: Int) {
        guard Self.meters.contains(beats), beats != beatsPerMeasure else { return }
        let old = beatsPerMeasure
        beatsPerMeasure = beats
        chords = chords.compactMap { chord in
            let measure = chord.start / old, offset = chord.start % old
            guard offset < beats else { return nil }
            return PlacedChord(start: measure * beats + offset, beats: min(chord.beats, beats - offset),
                               symbol: chord.symbol)
        }
        melody = melody.compactMap { note in
            let measure = note.start / (old * 2), offset = note.start % (old * 2)
            guard offset < beats * 2, let fitted = NoteValue.longest(fitting: min(note.length, beats * 2 - offset)) else {
                return nil
            }
            return MelodyNote(start: measure * beats * 2 + offset, length: fitted.eighths, pitch: note.pitch)
        }
    }

    /// Whether `measure` can be copied into the one after it (there's one, or room to add one).
    func canDuplicateMeasure(_ measure: Int) -> Bool {
        (0..<measureCount).contains(measure)
            && (measure + 1 < measureCount || measureCount < Self.measureRange.upperBound)
    }

    /// Copies `measure`'s chords and notes over the next measure, adding a measure at the end if needed.
    mutating func duplicateMeasure(_ measure: Int) {
        guard canDuplicateMeasure(measure) else { return }
        if measure + 1 == measureCount { setMeasureCount(measureCount + 1) }
        clearMeasure(measure + 1)
        let beats = beatsPerMeasure, eighths = eighthsPerMeasure
        let first = measure * beats
        let copiedChords = chords.filter { $0.start >= first && $0.start < first + beats }
            .map { PlacedChord(start: $0.start + beats, beats: $0.beats, symbol: $0.symbol) }
        chords = (chords + copiedChords).sorted { $0.start < $1.start }
        let firstTick = measure * eighths
        let copiedNotes = melody.filter { $0.start >= firstTick && $0.start < firstTick + eighths }
            .map { MelodyNote(start: $0.start + eighths, length: $0.length, pitch: $0.pitch) }
        melody = (melody + copiedNotes).sorted { $0.start < $1.start }
    }

    /// Removes `measure`'s chords and notes.
    mutating func clearMeasure(_ measure: Int) {
        let beats = beatsPerMeasure, eighths = eighthsPerMeasure
        let first = measure * beats, firstTick = measure * eighths
        chords.removeAll { $0.start >= first && $0.start < first + beats }
        melody.removeAll { $0.start >= firstTick && $0.start < firstTick + eighths }
    }

    func isMeasureEmpty(_ measure: Int) -> Bool {
        let first = measure * beatsPerMeasure, firstTick = measure * eighthsPerMeasure
        return !chords.contains { $0.start >= first && $0.start < first + beatsPerMeasure }
            && !melody.contains { $0.start >= firstTick && $0.start < firstTick + eighthsPerMeasure }
    }

    // MARK: Rests

    /// The rests filling measure `measure`'s gaps between chords, as they're written: a whole
    /// rest for an empty measure (in any meter), a half rest for two free beats starting the
    /// measure (or its second half, in 4/4), and quarter rests otherwise.
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

    /// The rests filling the melody's gaps in `measure`, in eighths: a whole rest for a measure
    /// with no notes, then the same half and quarter rests as the chords on the beat, and eighth
    /// rests off it.
    func melodyRests(inMeasure measure: Int) -> [MelodyRest] {
        let first = measure * eighthsPerMeasure, last = first + eighthsPerMeasure
        let inMeasure = melody.filter { $0.start >= first && $0.start < last }
        if inMeasure.isEmpty { return [MelodyRest(start: first, length: eighthsPerMeasure, glyph: .whole)] }
        var rests: [MelodyRest] = []
        var tick = first
        while tick < last {
            if let note = inMeasure.first(where: { $0.start == tick }) {
                tick = note.end
                continue
            }
            let gap = (inMeasure.first { $0.start > tick }?.start ?? last) - tick
            let offset = tick - first
            let strong = offset == 0 || (beatsPerMeasure == 4 && offset == 4)
            if strong && gap >= 4 {
                rests.append(MelodyRest(start: tick, length: 4, glyph: .half))
                tick += 4
            } else if offset % 2 == 0 && gap >= 2 {
                rests.append(MelodyRest(start: tick, length: 2, glyph: .quarter))
                tick += 2
            } else {
                rests.append(MelodyRest(start: tick, length: 1, glyph: .eighth))
                tick += 1
            }
        }
        return rests
    }

    // MARK: Chords

    /// The chord `symbol` spelled in this key.
    func chord(_ symbol: ChordSymbol) -> CompositionChord {
        CompositionChord(symbol: symbol, keySignature: keySignature, isMinor: isMinor)
    }

    /// The key's own triad on scale degree `degree` (1–7).
    func chord(degree: Int) -> CompositionChord {
        chord(ChordSymbol(degree: degree))
    }

    // MARK: Melody notes

    /// The key's scale from its tonic upward, starting in concert octave `octave` (3 is written
    /// on the staff in guitar notation): what the melody palette offers.
    func scalePitches(octave: Int) -> [SpelledPitch] {
        let tonic = isMinor ? keySignature.minorTonic.letter : keySignature.majorTonic.letter
        return (0..<7).map { step in
            let letter = (tonic + step) % 7
            return keySignature.pitch(letter: letter, octave: octave + (tonic + step) / 7)
        }
    }
}

// MARK: - Saving

extension Composition.PlacedChord: Codable {
    private enum CodingKeys: String, CodingKey { case start, beats, symbol, degree }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decode(Int.self, forKey: .start)
        beats = try c.decode(Int.self, forKey: .beats)
        // Before chord kinds, a chord was just its degree.
        symbol = try c.decodeIfPresent(ChordSymbol.self, forKey: .symbol)
            ?? ChordSymbol(degree: c.decode(Int.self, forKey: .degree))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(start, forKey: .start)
        try c.encode(beats, forKey: .beats)
        try c.encode(symbol, forKey: .symbol)
        // Also the bare degree, so an older version of the app (going back from a TestFlight
        // build) still reads the composition, as plain triads, instead of failing on all of them.
        try c.encode(symbol.secondary == nil ? symbol.degree : 5, forKey: .degree)
    }
}

extension Composition: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, keyRoot, isMinor, measureCount, beatsPerMeasure, chords, melody, updatedAt
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
                place(chord.symbol, at: chord.start, value: NoteValue(beats: chord.beats) ?? .quarter)
            }
        } else {
            let value = try c.decode(NoteValue.self, forKey: .noteValue)
            let slots = try c.decode([Int?].self, forKey: .slots)
            beatsPerMeasure = value == .dottedHalf ? 3 : 4
            for (slot, degree) in slots.enumerated() {
                if let degree { place(degree, at: slot * value.beats, value: value) }
            }
        }
        for note in (try c.decodeIfPresent([MelodyNote].self, forKey: .melody) ?? []).sorted(by: { $0.start < $1.start }) {
            placeNote(note.pitch, at: note.start, value: NoteValue(eighths: note.length) ?? .eighth)
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
        if !melody.isEmpty { try c.encode(melody, forKey: .melody) }
        try c.encode(updatedAt, forKey: .updatedAt)
    }
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
