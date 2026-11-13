//
//  Composition.swift
//  Guitar Man
//
//  A piece the student writes on a staff: a key, 4/4 or 3/4 time, 2–32 measures, a chord
//  progression, and optionally a melody over it.
//
//  Chords (see ChordSymbol) last from a quarter to a whole note and can start on any beat.
//  Melody notes are single pitches from a sixteenth to a whole note, on a timeline of ticks,
//  twelve to a beat: plain notes sit on sixteenths (every 3 ticks), and a beat can instead be
//  split in three for eighth-note triplets (every 4), which then have the beat to themselves.
//  A chord or note can be tied to the next one (the same chord or pitch, starting where it
//  ends), across a barline too: the two then sound as one. Each line
//  keeps the same rules on its own: nothing crosses a barline or overlaps, so something that
//  wouldn't fit is shortened to fit, and the gaps are rests, so every measure always adds up.
//  The student plays it (the app plays it too with Hear Compositions on: see CompositionPlayer).
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
    /// The melody's notes in order, on its own timeline in ticks (twelve to a beat).
    private(set) var melody: [MelodyNote] = []
    /// The tempo it's played back at, once one's been set for this piece (else Compose's usual one).
    var tempo: Int? = nil
    var updatedAt: Date = .now

    static let measureRange = 2...32
    static let meters = [4, 3]

    /// A chord on beat `start` (counting quarter-note beats from the start of the piece).
    struct PlacedChord: Hashable, Identifiable {
        var start: Int
        var beats: Int
        var symbol: ChordSymbol
        /// Tied to the next chord: see `tiesForward(_:)`.
        var tied = false

        var id: Int { start }
        var end: Int { start + beats }
        var value: NoteValue { NoteValue(beats: beats) ?? .quarter }
    }

    /// A melody note on tick `start` (counting twelve to a beat from the start of the piece).
    struct MelodyNote: Codable, Hashable, Identifiable {
        var start: Int
        /// In ticks: a note value's (3 for a sixteenth … 48 for a whole note).
        var length: Int
        var pitch: SpelledPitch
        /// The string it's played on (0 = high e … 5 = low E), when it was entered on the
        /// fretboard: for tablature (see `tabPosition(of:)`).
        var string: Int? = nil
        /// Tied to the next note: see `tiesForward(_:)`.
        var tied = false

        var id: Int { start }
        var end: Int { start + length }
        var value: NoteValue { NoteValue(ticks: length) ?? .eighth }
        var isTriplet: Bool { length == NoteValue.tripletEighth.ticks }

        private enum CodingKeys: String, CodingKey { case start, length, pitch, string, tied }

        init(start: Int, length: Int, pitch: SpelledPitch, string: Int? = nil, tied: Bool = false) {
            self.start = start
            self.length = length
            self.pitch = pitch
            self.string = string
            self.tied = tied
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            start = try c.decode(Int.self, forKey: .start)
            length = try c.decode(Int.self, forKey: .length)
            pitch = try c.decode(SpelledPitch.self, forKey: .pitch)
            string = try c.decodeIfPresent(Int.self, forKey: .string)
            tied = try c.decodeIfPresent(Bool.self, forKey: .tied) ?? false
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(start, forKey: .start)
            try c.encode(length, forKey: .length)
            try c.encode(pitch, forKey: .pitch)
            try c.encodeIfPresent(string, forKey: .string)
            if tied { try c.encode(true, forKey: .tied) }
        }

        func moved(to start: Int, length: Int? = nil) -> MelodyNote {
            var copy = self
            copy.start = start
            if let length { copy.length = length }
            return copy
        }
    }

    /// A gap between chords, written as one rest symbol: `glyph` is the rest's note value.
    struct Rest: Hashable {
        var start: Int
        var beats: Int
        var glyph: NoteValue
    }

    /// A gap in the melody, in ticks.
    struct MelodyRest: Hashable {
        var start: Int
        var length: Int
        var glyph: NoteValue
    }

    var totalBeats: Int { measureCount * beatsPerMeasure }
    static let ticksPerBeat = NoteValue.ticksPerBeat
    var ticksPerMeasure: Int { beatsPerMeasure * Self.ticksPerBeat }
    var totalTicks: Int { totalBeats * Self.ticksPerBeat }

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
    var melodyValues: [NoteValue] { NoteValue.allCases.filter { $0.ticks <= ticksPerMeasure } }

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

    /// The melody note sounding on `tick`, if any.
    func note(covering tick: Int) -> MelodyNote? {
        melody.first { $0.start <= tick && tick < $0.end }
    }

    /// Whether the beat `tick` is in is split in three: it holds an eighth-note triplet.
    func isTripletBeat(at tick: Int) -> Bool {
        let beat = tick / Self.ticksPerBeat
        return melody.contains { $0.isTriplet && $0.start / Self.ticksPerBeat == beat }
    }

    /// Where a note of `value` written at `tick` would go: the triplet it's in, for a triplet;
    /// else the sixteenth (the eighth, in a beat that's split in three and about to be replaced).
    func snapped(_ tick: Int, for value: NoteValue) -> Int {
        let beatStart = tick / Self.ticksPerBeat * Self.ticksPerBeat, offset = tick - beatStart
        if value.isTriplet { return beatStart + min(offset / 4, 2) * 4 }
        return beatStart + (isTripletBeat(at: tick) ? offset / 6 * 6 : offset / 3 * 3)
    }

    /// Where a plain note starting on `start` has to stop: the barline, the next note, or the
    /// start of the next beat that's split in three.
    private func limit(after start: Int) -> Int {
        let barline = (start / ticksPerMeasure + 1) * ticksPerMeasure
        guard let next = melody.first(where: { $0.start > start }) else { return barline }
        return min(barline, next.isTriplet ? next.start / Self.ticksPerBeat * Self.ticksPerBeat : next.start)
    }

    /// The longest a melody note starting on `tick` could be, in ticks.
    func noteRoom(at tick: Int) -> Int {
        max(0, limit(after: tick) - tick)
    }

    // MARK: Editing chords

    /// Puts `symbol` on `beat` for `value`, shortened to fit before the next chord or the barline.
    /// A chord already starting there is replaced; one still ringing there is cut short. Returns
    /// the beats the new chord got (less than `value` when it had to be shortened), or nil if
    /// `beat` is outside the piece.
    @discardableResult
    mutating func place(_ symbol: ChordSymbol, at beat: Int, value: NoteValue, tied: Bool = false) -> Int? {
        guard (0..<totalBeats).contains(beat), symbol.isValid else { return nil }
        chords.removeAll { $0.start == beat }
        if let ringing = chords.firstIndex(where: { $0.start < beat && beat < $0.end }) {
            chords[ringing].beats = beat - chords[ringing].start
        }
        let beats = min(max(value.beats, 1), room(at: beat))
        chords.append(PlacedChord(start: beat, beats: beats, symbol: symbol, tied: tied))
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

    /// Leaves beats `from..<to` silent: chords starting there go, and one ringing into them is cut short.
    mutating func clearChords(from: Int, to: Int) {
        chords.removeAll { $0.start >= from && $0.start < to }
        if let ringing = chords.firstIndex(where: { $0.start < from && from < $0.end }) {
            chords[ringing].beats = from - chords[ringing].start
        }
    }

    // MARK: Editing the melody

    /// Puts `pitch` at `tick` (snapped: see `snapped(_:for:)`) for `value`, shortened to the
    /// longest value that fits before the next note or the barline. A note already starting
    /// there is replaced; one still ringing is cut short. A triplet takes over its beat: plain
    /// notes in it go, and a plain note written in a beat of triplets replaces them the same way.
    /// Returns the value the note got, or nil if `tick` is outside the piece.
    @discardableResult
    mutating func placeNote(_ pitch: SpelledPitch, at tick: Int, value: NoteValue, string: Int? = nil,
                            tied: Bool = false) -> NoteValue? {
        guard (0..<totalTicks).contains(tick) else { return nil }
        let tick = snapped(tick, for: value)
        let beatStart = tick / Self.ticksPerBeat * Self.ticksPerBeat
        if value.isTriplet != isTripletBeat(at: tick) || (value.isTriplet && note(covering: beatStart)?.isTriplet == false) {
            clearNotes(from: beatStart, to: beatStart + Self.ticksPerBeat)
        }
        melody.removeAll { $0.start == tick }
        let fitted: NoteValue
        if value.isTriplet {
            fitted = value
        } else {
            if let ringing = melody.firstIndex(where: { $0.start < tick && tick < $0.end }) {
                melody[ringing].length = NoteValue.longest(fitting: tick - melody[ringing].start)?.ticks ?? 3
            }
            guard let longest = NoteValue.longest(fitting: min(value.ticks, noteRoom(at: tick))) else { return nil }
            fitted = longest
        }
        melody.append(MelodyNote(start: tick, length: fitted.ticks, pitch: pitch, string: string, tied: tied))
        melody.sort { $0.start < $1.start }
        return fitted
    }

    mutating func removeNote(covering tick: Int) {
        melody.removeAll { $0.start <= tick && tick < $0.end }
    }

    /// Makes the note starting on `start` last `value`, shortened to fit like `placeNote`.
    /// Triplets keep their length: they're a third of their beat.
    mutating func setLength(ofNoteAt start: Int, to value: NoteValue) {
        guard !value.isTriplet, let index = melody.firstIndex(where: { $0.start == start }), !melody[index].isTriplet else { return }
        melody[index].length = NoteValue.longest(fitting: min(value.ticks, limit(after: start) - start))?.ticks ?? 3
    }

    mutating func clearMelody() { melody = [] }

    /// Leaves ticks `from..<to` silent, like `clearChords(from:to:)`. A note ringing into them
    /// is cut short, or goes if what's left of it is no note value (a triplet, or under a sixteenth).
    mutating func clearNotes(from: Int, to: Int) {
        melody.removeAll { $0.start >= from && $0.start < to }
        if let ringing = melody.firstIndex(where: { $0.start < from && from < $0.end }) {
            if !melody[ringing].isTriplet, let left = NoteValue.longest(fitting: from - melody[ringing].start) {
                melody[ringing].length = left.ticks
            } else {
                melody.remove(at: ringing)
            }
        }
    }

    // MARK: Ties

    /// Whether `chord` is tied to the next: marked so, and the next is the same chord starting
    /// where it ends. Tied chords sound as one.
    func tiesForward(_ chord: PlacedChord) -> Bool {
        chord.tied && chords.contains { $0.start == chord.end && $0.symbol == chord.symbol }
    }

    func tiesForward(_ note: MelodyNote) -> Bool {
        note.tied && melody.contains { $0.start == note.end && $0.pitch == note.pitch }
    }

    /// Whether `chord` carries on one tied to it from before, so it isn't struck again.
    func isTiedOver(_ chord: PlacedChord) -> Bool {
        chords.contains { $0.end == chord.start && $0.symbol == chord.symbol && $0.tied }
    }

    func isTiedOver(_ note: MelodyNote) -> Bool {
        melody.contains { $0.end == note.start && $0.pitch == note.pitch && $0.tied }
    }

    /// The chords and notes that are struck: all but the ones carrying on a tie.
    var struckChords: [PlacedChord] { chords.filter { !isTiedOver($0) } }
    var struckMelody: [MelodyNote] { melody.filter { !isTiedOver($0) } }

    /// How long `chord` sounds with what it's tied to, in beats.
    func soundingBeats(of chord: PlacedChord) -> Int {
        var last = chord
        while tiesForward(last), let next = chords.first(where: { $0.start == last.end }) { last = next }
        return last.end - chord.start
    }

    /// How long `note` sounds with what it's tied to, in ticks.
    func soundingTicks(of note: MelodyNote) -> Int {
        var last = note
        while tiesForward(last), let next = melody.first(where: { $0.start == last.end }) { last = next }
        return last.end - note.start
    }

    /// Ties the chord starting on `start` to the next, or unties it. If nothing follows it, the
    /// same chord is written after it (the same length, or what fits; in a new measure at the
    /// end of the piece if there's room for one). False if a different chord follows.
    @discardableResult
    mutating func toggleTie(ofChordAt start: Int) -> Bool {
        guard let index = chords.firstIndex(where: { $0.start == start }) else { return false }
        let chord = chords[index]
        if tiesForward(chord) {
            chords[index].tied = false
            return true
        }
        if let next = self.chord(covering: chord.end) {
            guard next.start == chord.end, next.symbol == chord.symbol else { return false }
        } else {
            if chord.end >= totalBeats {
                guard hasRoom(forMeasures: 1) else { return false }
                setMeasureCount(measureCount + 1)
            }
            guard place(chord.symbol, at: chord.end, value: chord.value) != nil else { return false }
        }
        if let index = chords.firstIndex(where: { $0.start == start }) { chords[index].tied = true }
        return true
    }

    /// Ties the note starting on `start` to the next, like `toggleTie(ofChordAt:)`.
    @discardableResult
    mutating func toggleTie(ofNoteAt start: Int) -> Bool {
        guard let index = melody.firstIndex(where: { $0.start == start }) else { return false }
        let note = melody[index]
        if tiesForward(note) {
            melody[index].tied = false
            return true
        }
        if let next = self.note(covering: note.end) {
            guard next.start == note.end, next.pitch == note.pitch else { return false }
        } else {
            if note.end >= totalTicks {
                guard hasRoom(forMeasures: 1) else { return false }
                setMeasureCount(measureCount + 1)
            }
            // After a triplet in the middle of its beat comes another; at the end of it, an eighth.
            let value = note.isTriplet && note.end % Self.ticksPerBeat == 0 ? .eighth : note.value
            guard placeNote(note.pitch, at: note.end, value: value, string: note.string) != nil else { return false }
        }
        if let index = melody.firstIndex(where: { $0.start == start }) { melody[index].tied = true }
        return true
    }

    // MARK: Measures and meter

    /// Changes the number of measures; chords and notes in measures that go away are dropped.
    mutating func setMeasureCount(_ count: Int) {
        measureCount = min(max(count, Self.measureRange.lowerBound), Self.measureRange.upperBound)
        let end = totalBeats
        chords.removeAll { $0.start >= end }
        melody.removeAll { $0.start >= end * Self.ticksPerBeat }
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
                               symbol: chord.symbol, tied: chord.tied)
        }
        let oldTicks = old * Self.ticksPerBeat, newTicks = beats * Self.ticksPerBeat
        melody = melody.compactMap { note in
            let measure = note.start / oldTicks, offset = note.start % oldTicks
            guard offset < newTicks else { return nil }
            if note.isTriplet { return note.moved(to: measure * newTicks + offset) }
            guard let fitted = NoteValue.longest(fitting: min(note.length, newTicks - offset)) else { return nil }
            return note.moved(to: measure * newTicks + offset, length: fitted.ticks)
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
        let beats = beatsPerMeasure, ticks = ticksPerMeasure
        let first = measure * beats
        let copiedChords = chords.filter { $0.start >= first && $0.start < first + beats }
            .map { PlacedChord(start: $0.start + beats, beats: $0.beats, symbol: $0.symbol, tied: $0.tied) }
        chords = (chords + copiedChords).sorted { $0.start < $1.start }
        let firstTick = measure * ticks
        let copiedNotes = melody.filter { $0.start >= firstTick && $0.start < firstTick + ticks }
            .map { $0.moved(to: $0.start + ticks) }
        melody = (melody + copiedNotes).sorted { $0.start < $1.start }
    }

    /// Removes `measure`'s chords and notes.
    mutating func clearMeasure(_ measure: Int) {
        let beats = beatsPerMeasure, ticks = ticksPerMeasure
        let first = measure * beats, firstTick = measure * ticks
        chords.removeAll { $0.start >= first && $0.start < first + beats }
        melody.removeAll { $0.start >= firstTick && $0.start < firstTick + ticks }
    }

    func isMeasureEmpty(_ measure: Int) -> Bool {
        let first = measure * beatsPerMeasure, firstTick = measure * ticksPerMeasure
        return !chords.contains { $0.start >= first && $0.start < first + beatsPerMeasure }
            && !melody.contains { $0.start >= firstTick && $0.start < firstTick + ticksPerMeasure }
    }

    // MARK: Whole measures

    /// What's in one measure, with starts counted from its barline: for copying and moving measures.
    struct MeasureContent: Hashable {
        var chords: [PlacedChord] = []
        var notes: [MelodyNote] = []
        var isEmpty: Bool { chords.isEmpty && notes.isEmpty }
    }

    /// Measures copied from a composition, to paste into one in the same meter.
    struct Clip: Hashable {
        var beatsPerMeasure: Int
        var measures: [MeasureContent]
    }

    func content(ofMeasure measure: Int) -> MeasureContent {
        let beats = beatsPerMeasure, ticks = ticksPerMeasure
        let first = measure * beats, firstTick = measure * ticks
        return MeasureContent(
            chords: chords.filter { $0.start >= first && $0.start < first + beats }
                .map { PlacedChord(start: $0.start - first, beats: $0.beats, symbol: $0.symbol, tied: $0.tied) },
            notes: melody.filter { $0.start >= firstTick && $0.start < firstTick + ticks }
                .map { $0.moved(to: $0.start - firstTick) })
    }

    private var allMeasures: [MeasureContent] { (0..<measureCount).map(content(ofMeasure:)) }

    /// Rebuilds the piece from `contents`, one per measure (cut or padded to the allowed number).
    private mutating func setMeasures(_ contents: [MeasureContent]) {
        var contents = Array(contents.prefix(Self.measureRange.upperBound))
        while contents.count < Self.measureRange.lowerBound { contents.append(MeasureContent()) }
        let beats = beatsPerMeasure, ticks = ticksPerMeasure
        measureCount = contents.count
        chords = contents.enumerated().flatMap { measure, content in
            content.chords.map { PlacedChord(start: $0.start + measure * beats, beats: $0.beats, symbol: $0.symbol, tied: $0.tied) }
        }
        melody = contents.enumerated().flatMap { measure, content in
            content.notes.map { $0.moved(to: $0.start + measure * ticks) }
        }
    }

    private func clamped(_ range: ClosedRange<Int>) -> ClosedRange<Int>? {
        let low = max(range.lowerBound, 0), high = min(range.upperBound, measureCount - 1)
        return low <= high ? low...high : nil
    }

    /// The measures in `range`, copied.
    func clip(_ range: ClosedRange<Int>) -> Clip {
        Clip(beatsPerMeasure: beatsPerMeasure, measures: (clamped(range) ?? 0...0).map(content(ofMeasure:)))
    }

    /// Whether `count` more measures fit.
    func hasRoom(forMeasures count: Int) -> Bool { measureCount + count <= Self.measureRange.upperBound }

    /// Adds an empty measure before `measure` (or at the end), moving the rest along.
    @discardableResult
    mutating func insertMeasure(at measure: Int) -> Bool {
        guard hasRoom(forMeasures: 1), (0...measureCount).contains(measure) else { return false }
        var all = allMeasures
        all.insert(MeasureContent(), at: measure)
        setMeasures(all)
        return true
    }

    /// Takes the measures in `range` out, closing the gap (the piece keeps at least two measures).
    mutating func deleteMeasures(_ range: ClosedRange<Int>) {
        guard let range = clamped(range) else { return }
        var all = allMeasures
        all.removeSubrange(range)
        setMeasures(all)
    }

    /// Empties the measures in `range`.
    mutating func clearMeasures(_ range: ClosedRange<Int>) {
        guard let range = clamped(range) else { return }
        range.forEach { clearMeasure($0) }
    }

    /// Writes the measures in `range` again right after themselves, moving the rest along.
    /// False if they wouldn't fit.
    @discardableResult
    mutating func repeatMeasures(_ range: ClosedRange<Int>) -> Bool {
        guard let range = clamped(range), hasRoom(forMeasures: range.count) else { return false }
        var all = allMeasures
        all.insert(contentsOf: all[range], at: range.upperBound + 1)
        setMeasures(all)
        return true
    }

    /// Moves the measures in `range` one measure earlier (`offset` −1) or later (1), swapping
    /// with their neighbour. Returns where they are now, or nil if they're at that end already.
    @discardableResult
    mutating func moveMeasures(_ range: ClosedRange<Int>, by offset: Int) -> ClosedRange<Int>? {
        guard let range = clamped(range), abs(offset) == 1,
              range.lowerBound + offset >= 0, range.upperBound + offset < measureCount else { return nil }
        var all = allMeasures
        let moved = Array(all[range])
        all.removeSubrange(range)
        all.insert(contentsOf: moved, at: range.lowerBound + offset)
        setMeasures(all)
        return (range.lowerBound + offset)...(range.upperBound + offset)
    }

    /// Whether `clip` can go in at `measure`: same meter, and it starts inside the piece.
    func canPaste(_ clip: Clip, at measure: Int) -> Bool {
        clip.beatsPerMeasure == beatsPerMeasure && !clip.measures.isEmpty && (0..<measureCount).contains(measure)
    }

    /// Whether pasting `clip` at `measure` would write over something.
    func pasteOverwrites(_ clip: Clip, at measure: Int) -> Bool {
        (measure..<min(measure + clip.measures.count, measureCount)).contains { !isMeasureEmpty($0) }
    }

    /// Writes `clip` over the measures from `measure` on, adding measures at the end if it runs
    /// past it (what doesn't fit in the most measures a piece can have is left off). Returns the
    /// measures it filled.
    @discardableResult
    mutating func paste(_ clip: Clip, at measure: Int) -> ClosedRange<Int>? {
        guard canPaste(clip, at: measure) else { return nil }
        var all = allMeasures
        let pasted = Array(clip.measures.prefix(Self.measureRange.upperBound - measure))
        for (offset, content) in pasted.enumerated() {
            if measure + offset < all.count { all[measure + offset] = content } else { all.append(content) }
        }
        setMeasures(all)
        return measure...(measure + pasted.count - 1)
    }

    // MARK: Key

    private var tonic: (letter: Int, accidental: Int) { isMinor ? keySignature.minorTonic : keySignature.majorTonic }

    /// Changes the key. The chords are numerals, so they follow by themselves; the melody moves
    /// the same way: a note of the scale keeps its place in the scale (so the 3rd follows a
    /// change from major to minor), and a note from outside it keeps its distance from the
    /// tonic. It goes up or down, whichever leaves the melody nearer the middle of the staff
    /// and on the guitar.
    mutating func setKey(root: Note, isMinor minor: Bool) {
        guard root != keyRoot || minor != isMinor else { return }
        let oldKey = keySignature
        let oldTonic = SpelledPitch(letter: tonic.letter, accidental: tonic.accidental, octave: 3)
        keyRoot = root
        isMinor = minor
        guard !melody.isEmpty else { return }
        let newKey = keySignature
        let newTonic = SpelledPitch(letter: tonic.letter, accidental: tonic.accidental, octave: 3)
        let steps = newTonic.diatonicNumber - oldTonic.diatonicNumber
        let semitones = newTonic.midi - oldTonic.midi
        func moved(_ pitch: SpelledPitch, octaves: Int) -> SpelledPitch {
            let target = pitch.diatonicNumber + steps + octaves * 7
            let letter = ((target % 7) + 7) % 7, octave = (target - letter) / 7
            if pitch.accidental == oldKey.accidental(forLetter: pitch.letter) {
                return newKey.pitch(letter: letter, octave: octave)
            }
            let natural = SpelledPitch(letter: letter, octave: octave).midi
            return SpelledPitch(letter: letter, accidental: max(-2, min(2, pitch.midi + semitones + octaves * 12 - natural)),
                                octave: octave)
        }
        // Low E to the top of the neck, around the middle of the staff; of two as good, the nearer.
        let before = Double(melody.reduce(0) { $0 + $1.pitch.midi }) / Double(melody.count)
        func cost(_ octaves: Int) -> Double {
            let midis = melody.map { moved($0.pitch, octaves: octaves).midi }
            let mean = Double(midis.reduce(0, +)) / Double(midis.count)
            let outside = midis.filter { !(40...84).contains($0) }.count
            return Double(outside) * 1000 + abs(mean - 60) + abs(mean - before) / 100
        }
        let octaves = (-2...2).min { cost($0) < cost($1) } ?? 0
        melody = melody.map { MelodyNote(start: $0.start, length: $0.length, pitch: moved($0.pitch, octaves: octaves)) }
    }

    /// Changes the pitch of the note starting on `start`, keeping its place and length.
    mutating func setPitch(ofNoteAt start: Int, to pitch: SpelledPitch) {
        guard let index = melody.firstIndex(where: { $0.start == start }) else { return }
        melody[index].pitch = pitch
        melody[index].string = nil
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

    /// The rests filling the melody's gaps in `measure`, in ticks: a whole rest for a measure
    /// with no notes, then the same half and quarter rests as the chords on the beat, eighth and
    /// sixteenth rests off it, and triplet rests in a beat that's split in three.
    func melodyRests(inMeasure measure: Int) -> [MelodyRest] {
        let first = measure * ticksPerMeasure, last = first + ticksPerMeasure
        let inMeasure = melody.filter { $0.start >= first && $0.start < last }
        if inMeasure.isEmpty { return [MelodyRest(start: first, length: ticksPerMeasure, glyph: .whole)] }
        var rests: [MelodyRest] = []
        var tick = first
        while tick < last {
            if let note = inMeasure.first(where: { $0.start == tick }) {
                tick = note.end
                continue
            }
            if isTripletBeat(at: tick) {
                rests.append(MelodyRest(start: tick, length: 4, glyph: .tripletEighth))
                tick += 4
                continue
            }
            let gap = min(limit(after: tick), last) - tick
            let offset = tick - first, inBeat = tick % Self.ticksPerBeat
            let strong = offset == 0 || (beatsPerMeasure == 4 && offset == 24)
            if strong && gap >= 24 {
                rests.append(MelodyRest(start: tick, length: 24, glyph: .half))
                tick += 24
            } else if inBeat == 0 && gap >= 12 {
                rests.append(MelodyRest(start: tick, length: 12, glyph: .quarter))
                tick += 12
            } else if inBeat % 6 == 0 && gap >= 6 {
                rests.append(MelodyRest(start: tick, length: 6, glyph: .eighth))
                tick += 6
            } else {
                rests.append(MelodyRest(start: tick, length: 3, glyph: .sixteenth))
                tick += 3
            }
        }
        return rests
    }

    /// The finest step the staff needs to show `measure`'s melody, in ticks: an eighth (6)
    /// unless it has sixteenths (3), triplets (2), or both (1). The staff and the tablature
    /// under it lay the measure out in columns this wide.
    func columnTicks(inMeasure measure: Int) -> Int {
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let first = measure * ticksPerMeasure
        let starts = melody.filter { $0.start >= first && $0.start < first + ticksPerMeasure }.map { $0.start - first }
            + melodyRests(inMeasure: measure).map { $0.start - first }
        return starts.reduce(6) { gcd($0, $1) }
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
    private enum CodingKeys: String, CodingKey { case start, beats, symbol, degree, tied }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        start = try c.decode(Int.self, forKey: .start)
        beats = try c.decode(Int.self, forKey: .beats)
        // Before chord kinds, a chord was just its degree.
        symbol = try c.decodeIfPresent(ChordSymbol.self, forKey: .symbol)
            ?? ChordSymbol(degree: c.decode(Int.self, forKey: .degree))
        tied = try c.decodeIfPresent(Bool.self, forKey: .tied) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(start, forKey: .start)
        try c.encode(beats, forKey: .beats)
        try c.encode(symbol, forKey: .symbol)
        // Also the bare degree, so an older version of the app (going back from a TestFlight
        // build) still reads the composition, as plain triads, instead of failing on all of them.
        try c.encode(symbol.secondary == nil ? symbol.degree : 5, forKey: .degree)
        if tied { try c.encode(true, forKey: .tied) }
    }
}

extension Composition: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, keyRoot, isMinor, measureCount, beatsPerMeasure, chords, melody, notes, updatedAt, tempo
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
        tempo = try c.decodeIfPresent(Int.self, forKey: .tempo)
        let measures = try c.decode(Int.self, forKey: .measureCount)
        measureCount = min(max(measures, Self.measureRange.lowerBound), Self.measureRange.upperBound)
        if let chords = try c.decodeIfPresent([PlacedChord].self, forKey: .chords) {
            let beats = try c.decode(Int.self, forKey: .beatsPerMeasure)
            beatsPerMeasure = Self.meters.contains(beats) ? beats : 4
            // Re-apply the rules, in case the saved data was ever out of shape.
            for chord in chords.sorted(by: { $0.start < $1.start }) {
                place(chord.symbol, at: chord.start, value: NoteValue(beats: chord.beats) ?? .quarter, tied: chord.tied)
            }
        } else {
            let value = try c.decode(NoteValue.self, forKey: .noteValue)
            let slots = try c.decode([Int?].self, forKey: .slots)
            beatsPerMeasure = value == .dottedHalf ? 3 : 4
            for (slot, degree) in slots.enumerated() {
                if let degree { place(degree, at: slot * value.beats, value: value) }
            }
        }
        // The melody in ticks; before sixteenths and triplets it was saved in eighths, as `melody`.
        var saved = try c.decodeIfPresent([MelodyNote].self, forKey: .notes)
        if saved == nil {
            saved = (try c.decodeIfPresent([MelodyNote].self, forKey: .melody) ?? []).map {
                MelodyNote(start: $0.start * 6, length: $0.length * 6, pitch: $0.pitch, string: $0.string)
            }
        }
        for note in (saved ?? []).sorted(by: { $0.start < $1.start }) {
            placeNote(note.pitch, at: note.start, value: NoteValue(ticks: note.length) ?? .eighth, string: note.string, tied: note.tied)
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
        if !melody.isEmpty {
            try c.encode(melody, forKey: .notes)
            // And in eighths, as it was saved before sixteenths and triplets, so an older version
            // of the app still shows the melody: what's on its eighths, without the ties.
            let eighths: [MelodyNote] = melody.filter { $0.start % 6 == 0 }.map { note in
                let length = [8, 6, 4, 3, 2, 1].first { $0 * 6 <= max(note.length, 6) } ?? 1
                return MelodyNote(start: note.start / 6, length: length, pitch: note.pitch, string: note.string)
            }
            try c.encode(eighths, forKey: .melody)
        }
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(tempo, forKey: .tempo)
    }
}

// MARK: - CompositionStore

/// Saved compositions, newest first.
@Observable
final class CompositionStore {
    private(set) var compositions: [Composition] = []

    /// The one store, so a composition that arrives from outside (a file opened from Messages)
    /// shows up in the list that's on screen.
    static let shared = CompositionStore()

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

    /// Saves a copy of a saved composition under a name of its own ("Song copy"), and returns it.
    @discardableResult
    func duplicate(_ id: UUID) -> Composition? {
        guard var copy = compositions.first(where: { $0.id == id }) else { return nil }
        copy.id = UUID()
        copy.name = unusedName(copy.name.hasSuffix(" copy") ? copy.name : "\(copy.name) copy")
        save(copy)
        return copy
    }

    /// Adds a composition that came from a file, under a name no saved one has, and returns it.
    @discardableResult
    func add(imported composition: Composition) -> Composition {
        var added = composition
        added.id = UUID()
        added.name = unusedName(added.name)
        save(added)
        return compositions.first { $0.id == added.id } ?? added
    }

    /// Renames a saved composition, leaving its place in the list (a new name isn't an edit).
    func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = compositions.firstIndex(where: { $0.id == id }) else { return }
        compositions[index].name = trimmed
        persist()
    }

    /// `base` if no saved composition has that name yet, else "base 2", "base 3"…, so new
    /// compositions can be told apart in the list.
    func unusedName(_ base: String) -> String {
        let names = Set(compositions.map(\.name))
        guard names.contains(base) else { return base }
        var number = 2
        while names.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(compositions) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
