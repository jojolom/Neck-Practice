//
//  CompositionHearing.swift
//  Guitar Man
//
//  Writing a composition by playing it: working out what was played from what the microphone
//  heard (see ChordListener), and putting a take played in time onto the beat.
//
//  A chord is one of the chords Compose offers in the key (the palette's, with their versions,
//  and the borrowed and secondary ones): the one whose notes the strum's chroma fits best. A
//  7th or sus chord is only chosen over its plain triad when its extra note really rings, since
//  a triad's overtones put a little sound on other notes. What's in the bass can't be told, so
//  chords are heard in root position. A single note is the pitch the tuner's analysis finds,
//  spelled for the key, as long as the chroma agrees on which note it is.
//
//  NoteTracker and ChordTracker decide when something heard counts as played: after a fresh
//  pluck or strum, and steady for a couple of analyses.
//  No UI here, so scripts/chord-check.swift can check it.
//

import Foundation

enum ComposeHearing {

    /// Low E to the top of the neck.
    static let midiRange = 40...88

    /// How much of the sound each note of a four-note chord must carry for it to be heard as
    /// that rather than as the triad it contains (and what each note costs a chord's score, so
    /// the simpler chord wins unless the extra note earns its place). Lower, and a triad's
    /// overtones turn it into a 7th; higher, and real 7ths are heard as triads.
    static let extraNoteShare = 0.1

    /// The nearest MIDI note to `frequency` (Hz).
    static func midi(frequency: Double) -> Int {
        Int((69 + 12 * log2(frequency / 440)).rounded())
    }

    /// `midi` spelled for `key`: the scale's own note if it is one, else a natural, else a sharp
    /// in sharp keys (and C) and a flat in flat keys.
    static func spell(midi: Int, in key: KeySignature) -> SpelledPitch {
        let options = (0..<7).compactMap { SpelledPitch(midi: midi, letter: $0) }.filter { abs($0.accidental) <= 1 }
        if let inKey = options.first(where: { $0.accidental == key.accidental(forLetter: $0.letter) }) { return inKey }
        if let natural = options.first(where: { $0.accidental == 0 }) { return natural }
        let wanted = key.fifths >= 0 ? 1 : -1
        return options.first { $0.accidental == wanted } ?? options.first ?? SpelledPitch(letter: 0, octave: midi / 12 - 1)
    }

    /// The single note sounding: `frequency`'s, if it's on the guitar and the chroma says the
    /// same: most of the sound on that one note, as a plucked string has. That rules out a
    /// strummed chord, an overtone taken for the note, and talking or music in the room.
    static func midi(frequency: Double?, chroma: [Double]) -> Int? {
        guard let frequency, frequency > 0, chroma.count == 12 else { return nil }
        let midi = midi(frequency: frequency)
        guard midiRange.contains(midi), ChordAnalyzer.matchesNote(chroma: chroma, pitchClass: midi % 12) else { return nil }
        return midi
    }

    /// The chords to listen for in `composition`'s key, the key's own first.
    static func candidates(for composition: Composition) -> [CompositionChord] {
        var symbols: [ChordSymbol] = []
        for degree in 1...7 {
            symbols += CompositionChord.variants(degree: degree, keySignature: composition.keySignature,
                                                 isMinor: composition.isMinor)
        }
        for pair in CompositionChord.borrowed(isMinor: composition.isMinor) {
            symbols += [pair.chord, pair.seventh]
        }
        // Two names for the same notes: the first (the key's own) is the one heard.
        var seen: Set<Set<Int>> = []
        return symbols.map(composition.chord).filter { seen.insert($0.pitchClasses).inserted }
    }

    /// The chord of `candidates` that `chroma` sounds like, or nil if none fits.
    static func chord(in chroma: [Double], candidates: [CompositionChord]) -> CompositionChord? {
        guard chroma.count == 12 else { return nil }
        var best: (chord: CompositionChord, score: Double)? = nil
        for candidate in candidates {
            let required = candidate.requiredPitchClasses
            guard ChordAnalyzer.matches(chroma: chroma, pitchClasses: required,
                                        optional: candidate.pitchClasses.subtracting(required)) else { continue }
            let share = candidate.pitchClasses.reduce(0.0) { $0 + chroma[$1] }
            // A fourth note has to ring like a played string, not like an overtone of the others.
            if candidate.pitchClasses.count > 3,
               (required.map { chroma[$0] }.min() ?? 0) < extraNoteShare { continue }
            let score = share - extraNoteShare * Double(candidate.pitchClasses.count)
            if score > (best?.score ?? -.infinity) { best = (candidate, score) }
        }
        return best?.chord
    }
}

/// Decides when a note that's heard has been played: after a pluck, the same note on two
/// analyses running. One pluck writes one note, so a note left ringing, or sound with no
/// attack to it, writes nothing.
struct NoteTracker {
    private var candidate: Int? = nil
    private var count = 0
    private var attackPending = false

    /// A pluck was heard.
    mutating func attack() {
        attackPending = true
        candidate = nil
        count = 0
    }

    /// Takes each analysis's note (nil for none); returns one when it counts as played.
    mutating func hear(_ midi: Int?) -> Int? {
        guard attackPending, let midi else {
            candidate = nil
            count = 0
            return nil
        }
        if midi == candidate { count += 1 } else { (candidate, count) = (midi, 1) }
        guard count >= 2 else { return nil }
        attackPending = false
        return midi
    }
}

/// Decides when a chord that's heard has been played: after a strum, the same chord on two
/// analyses running. One strum writes one chord.
struct ChordTracker {
    private var candidate: ChordSymbol? = nil
    private var count = 0
    private var attackPending = false

    /// A strum was heard.
    mutating func attack() {
        attackPending = true
        candidate = nil
        count = 0
    }

    mutating func hear(_ symbol: ChordSymbol?) -> ChordSymbol? {
        guard attackPending, let symbol else {
            candidate = nil
            count = 0
            return nil
        }
        if symbol == candidate { count += 1 } else { (candidate, count) = (symbol, 1) }
        guard count >= 2 else { return nil }
        attackPending = false
        return symbol
    }
}

// MARK: - Takes played in time

extension Composition {

    /// A chord or note in a take, at `beat` quarter-note beats after the take's first barline.
    struct Heard<Value> {
        var beat: Double
        var value: Value
    }

    /// The measures a take starting at `measure` with events up to `lastBeat` would fill, if any
    /// of it fits.
    private func measures(from measure: Int, lastBeat: Int) -> ClosedRange<Int>? {
        guard (0..<Self.measureRange.upperBound).contains(measure), lastBeat >= 0 else { return nil }
        return measure...min(measure + lastBeat / beatsPerMeasure, Self.measureRange.upperBound - 1)
    }

    /// Writes chords played in time over the chords from `measure` on: each on the nearest beat,
    /// ringing to the next chord or the barline. Adds measures at the end as needed. Returns
    /// the measures written, or nil if there was nothing to write.
    @discardableResult
    mutating func write(chords take: [Heard<ChordSymbol>], fromMeasure measure: Int) -> ClosedRange<Int>? {
        let heard = take.map { (beat: Int($0.beat.rounded()), symbol: $0.value) }.filter { $0.beat >= 0 }
        guard let last = heard.map(\.beat).max(), let range = measures(from: measure, lastBeat: last) else { return nil }
        if range.upperBound >= measureCount { setMeasureCount(range.upperBound + 1) }
        let first = measure * beatsPerMeasure
        clearChords(from: first, to: (range.upperBound + 1) * beatsPerMeasure)
        let longest = NoteValue(beats: beatsPerMeasure) ?? .whole
        let events = heard.filter { first + $0.beat < totalBeats }
        for event in events { place(event.symbol, at: first + event.beat, value: longest) }
        // A chord left ringing over the barline is held, tied, until the next one is played.
        for event in events.sorted(by: { $0.beat < $1.beat }) {
            var beat = (first + event.beat) / beatsPerMeasure * beatsPerMeasure + beatsPerMeasure
            let end = events.map { first + $0.beat }.filter { $0 > first + event.beat }.min() ?? 0
            while beat < end, let held = chord(covering: beat - 1), held.end == beat, held.symbol == event.symbol,
                  chord(covering: beat) == nil {
                place(event.symbol, at: beat, value: longest)
                toggleTie(ofChordAt: held.start)
                beat += beatsPerMeasure
            }
        }
        return range
    }

    /// Writes notes played in time over the melody from `measure` on, like `write(chords:)`: each
    /// on the nearest eighth, lasting to the next note or the barline.
    @discardableResult
    mutating func write(notes take: [Heard<SpelledPitch>], fromMeasure measure: Int) -> ClosedRange<Int>? {
        let events = take.map { (tick: Int(($0.beat * 2).rounded()) * 6, pitch: $0.value) }.filter { $0.tick >= 0 }
        guard let last = events.map(\.tick).max(),
              let range = measures(from: measure, lastBeat: last / Self.ticksPerBeat) else { return nil }
        if range.upperBound >= measureCount { setMeasureCount(range.upperBound + 1) }
        let first = measure * ticksPerMeasure
        clearNotes(from: first, to: (range.upperBound + 1) * ticksPerMeasure)
        let longest = NoteValue(ticks: ticksPerMeasure) ?? .whole
        for event in events { placeNote(event.pitch, at: first + event.tick, value: longest) }
        return range
    }

    // MARK: Tablature

    /// MIDI notes of the open strings, high e (string 0) to low E (string 5).
    static let openStrings = [64, 59, 55, 50, 45, 40]
    static let highestFret = 20

    /// Where `note` is played, for tablature: on the string it was entered on, if it was entered
    /// on the fretboard, else at the lowest fret it can be played at.
    func tabPosition(of note: MelodyNote) -> (string: Int, fret: Int)? {
        let midi = note.pitch.midi
        if let string = note.string, Self.openStrings.indices.contains(string),
           (0...Self.highestFret).contains(midi - Self.openStrings[string]) {
            return (string, midi - Self.openStrings[string])
        }
        return Self.openStrings.enumerated()
            .map { (string: $0.offset, fret: midi - $0.element) }
            .filter { (0...Self.highestFret).contains($0.fret) }
            .min { $0.fret < $1.fret }
    }
}
