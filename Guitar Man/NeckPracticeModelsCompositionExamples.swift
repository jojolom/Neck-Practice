//
//  CompositionExamples.swift
//  Guitar Man
//
//  Compositions to open, hear, play and take apart (Compose ▸ Examples), from two chords to
//  jazz changes: progressions, tunes everyone knows with their melodies, and pieces that show
//  what the editor can do (inversions, borrowed chords, sixteenths, triplets, ties).
//
//  The tunes are all traditional or long out of copyright, so their melodies can be written
//  out. Progressions behind well-known songs are given as chords only: a progression isn't
//  anyone's, and the songs named are just where you'll have heard it.
//
//  Chords are written as in the templates; melodies in a short notation (see `write(melody:)`)
//  that says exactly what's in each measure, so `chord-check` can verify that every example
//  comes out as written.
//

import Foundation

struct CompositionExample: Identifiable, Hashable {

    enum Level: String, CaseIterable, Identifiable {
        case simple = "Simple"
        case heard = "Progressions You've Heard"
        case tunes = "Tunes You Know"
        case advanced = "Advanced"

        var id: String { rawValue }

        var blurb: String {
            switch self {
            case .simple:   return "A few chords, one to a measure. Good ones to change the key of, or add to."
            case .heard:    return "The chords behind a great many songs. A progression belongs to no one: write your own tune over it."
            case .tunes:    return "Traditional and classical tunes with their melodies, easiest first. Try Play Along on the melody."
            case .advanced: return "Seventh chords, borrowed chords, inversions, and rhythms with sixteenths, triplets and ties."
            }
        }
    }

    let id: String
    let name: String
    /// One line on what it is or where you've heard it.
    let detail: String
    let level: Level
    let composition: Composition

    static func == (a: CompositionExample, b: CompositionExample) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// "I – V – vi – IV", up to a line's worth.
    var numerals: String {
        var seen: [String] = []
        for placed in composition.struckChords {
            let numeral = composition.chord(placed.symbol).romanNumeral
            if seen.last != numeral { seen.append(numeral) }
        }
        return seen.prefix(10).joined(separator: " – ") + (seen.count > 10 ? " …" : "")
    }

    /// "G Major · 4/4 · 12 bars · melody".
    var summary: String {
        var parts = [composition.keyName, composition.meterName, "\(composition.measureCount) bars"]
        if composition.hasMelody { parts.append("melody") }
        return parts.joined(separator: " · ")
    }

    // MARK: Building

    /// What went wrong building the examples, if anything (for `chord-check`).
    private(set) static var problems: [String] = []

    /// A chord in a measure, and how many beats it lasts (nil: an equal share of the measure).
    struct Bar {
        var chords: [(symbol: ChordSymbol, beats: Int?)]

        static func each(_ symbols: ChordSymbol...) -> Bar { Bar(chords: symbols.map { ($0, nil) }) }
        static func split(_ chords: (ChordSymbol, Int)...) -> Bar { Bar(chords: chords.map { ($0.0, $0.1) }) }
        static let none = Bar(chords: [])
    }

    private static func c(_ degree: Int, _ kind: ChordKind = .triad, shift: Int = 0, secondary: Int? = nil, inversion: Int = 0) -> ChordSymbol {
        ChordSymbol(degree: degree, shift: shift, kind: kind, secondary: secondary, inversion: inversion)
    }

    private static func example(_ id: String, _ name: String, _ level: Level, _ detail: String,
                                key: Note, minor: Bool = false, beats: Int = 4, tempo: Int,
                                bars: [Bar], melody: String = "") -> CompositionExample? {
        var composition = Composition()
        composition.name = name
        composition.setKey(root: key, isMinor: minor)
        composition.setBeatsPerMeasure(beats)
        composition.setMeasureCount(bars.count)
        composition.tempo = tempo
        guard composition.measureCount == bars.count else {
            problems.append("\(id): \(bars.count) measures")
            return nil
        }
        for (measure, bar) in bars.enumerated() {
            var beat = measure * beats
            for chord in bar.chords {
                let length = chord.beats ?? beats / max(bar.chords.count, 1)
                guard let value = NoteValue(beats: length), composition.place(chord.symbol, at: beat, value: value) == length else {
                    problems.append("\(id): chord in measure \(measure + 1)")
                    return nil
                }
                beat += length
            }
        }
        if !melody.isEmpty, let problem = composition.write(melody: melody) {
            problems.append("\(id): \(problem)")
            return nil
        }
        return CompositionExample(id: id, name: name, detail: detail, level: level, composition: composition)
    }

    private static func template(_ id: String, _ level: Level, _ detail: String, tempo: Int) -> CompositionExample? {
        guard let template = CompositionTemplate.all.first(where: { $0.id == id }) else {
            problems.append("\(id): no such template")
            return nil
        }
        var composition = template.makeComposition()
        composition.tempo = tempo
        return CompositionExample(id: id, name: template.name, detail: detail, level: level, composition: composition)
    }

    // MARK: The examples

    static let all: [CompositionExample] = [
        // ── Simple ──
        example("two-chords", "Two Chords", .simple, "Home and away: the smallest progression there is.",
                key: .c, tempo: 90, bars: [.each(c(1)), .each(c(5)), .each(c(1)), .each(c(5))]),
        example("three-chords", "Three-Chord Rocker", .simple, "I, IV and V: the three chords of La Bamba, Twist and Shout and Wild Thing.",
                key: .a, tempo: 120, bars: [.each(c(1), c(4)), .each(c(5), c(4)), .each(c(1), c(4)), .each(c(5), c(4))]),
        template("waltz", .simple, "I, IV and V in 3/4 time.", tempo: 110),
        example("minor-two", "Minor Mood", .simple, "i, iv and VII: two minor chords and a major one to lead back.",
                key: .a, minor: true, tempo: 80, bars: [.each(c(1)), .each(c(4)), .each(c(1)), .each(c(7))]),

        // ── Progressions you've heard ──
        template("pop", .heard, "I–V–vi–IV: Let It Be, No Woman, No Cry, With or Without You, and hundreds more.", tempo: 100),
        example("other-four", "The Other Four Chords", .heard, "The same four starting from the minor one, vi–IV–I–V: Zombie, and the chorus of Africa.",
                key: .g, tempo: 96, bars: [.each(c(6)), .each(c(4)), .each(c(1)), .each(c(5))]),
        template("fifties", .heard, "I–vi–IV–V: Stand by Me, Earth Angel, and most of doo-wop.", tempo: 100),
        template("blues", .heard, "Twelve bars on three dominant 7ths: Johnny B. Goode, Hound Dog, and the blues itself.", tempo: 110),
        template("andalusian", .heard, "A minor line walking down to a major V: flamenco, and Hit the Road Jack.", tempo: 110),
        example("minor-rock", "Minor Rock Loop", .heard, "i–VII–VI–VII, up and back: All Along the Watchtower.",
                key: .a, minor: true, tempo: 112, bars: [.each(c(1)), .each(c(7)), .each(c(6)), .each(c(7))]),
        example("rock-vamp", "Flat-Seven Vamp", .heard, "I, the major chord a step below it, and IV: the sound of classic-rock riffs.",
                key: .d, tempo: 104, bars: [.each(c(1)), .each(c(7, .major, shift: -1)), .each(c(4)), .each(c(4))]),
        example("rising-sun", "House of the Rising Sun", .heard, "The traditional song's chords, a bar each. Try them Fingerpicked.",
                key: .a, minor: true, beats: 3, tempo: 120,
                bars: [.each(c(1)), .each(c(3)), .each(c(4, .major)), .each(c(6)),
                       .each(c(1)), .each(c(3)), .each(c(5, .major)), .each(c(5, .major)),
                       .each(c(1)), .each(c(3)), .each(c(4, .major)), .each(c(6)),
                       .each(c(1)), .each(c(5, .major)), .each(c(1)), .each(c(5, .major))]),
        template("canon", .heard, "Pachelbel's Canon, two chords a bar: borrowed by pop songs ever since.", tempo: 80),

        // ── Tunes you know ──
        example("twinkle", "Twinkle, Twinkle, Little Star", .tunes, "All quarter and half notes, over I, IV and V.",
                key: .g, tempo: 100,
                bars: [.each(c(1)), .each(c(4), c(1)), .each(c(4), c(1)), .each(c(5), c(1)),
                       .each(c(1), c(4)), .each(c(1), c(5)), .each(c(1), c(4)), .each(c(1), c(5)),
                       .each(c(1)), .each(c(4), c(1)), .each(c(4), c(1)), .each(c(5), c(1))],
                melody: """
                G3q G3q D4q D4q | E4q E4q D4h | C4q C4q B3q B3q | A3q A3q G3h |
                D4q D4q C4q C4q | B3q B3q A3h | D4q D4q C4q C4q | B3q B3q A3h |
                G3q G3q D4q D4q | E4q E4q D4h | C4q C4q B3q B3q | A3q A3q G3h
                """),
        example("ode-to-joy", "Ode to Joy", .tunes, "Beethoven's tune moves by step: a dotted quarter and an eighth end each line.",
                key: .g, tempo: 108,
                bars: [.each(c(1)), .each(c(5)), .each(c(1)), .each(c(5)),
                       .each(c(1)), .each(c(5)), .each(c(1)), .each(c(5), c(1)),
                       .each(c(5)), .each(c(1)), .each(c(5)), .each(c(1), c(5)),
                       .each(c(1)), .each(c(5)), .each(c(1)), .each(c(5), c(1))],
                melody: """
                B3q B3q C4q D4q | D4q C4q B3q A3q | G3q G3q A3q B3q | B3q. A3e A3h |
                B3q B3q C4q D4q | D4q C4q B3q A3q | G3q G3q A3q B3q | A3q. G3e G3h |
                A3q A3q B3q G3q | A3q B3e C4e B3q G3q | A3q B3e C4e B3q A3q | G3q A3q D3h |
                B3q B3q C4q D4q | D4q C4q B3q A3q | G3q G3q A3q B3q | A3q. G3e G3h
                """),
        example("happy-birthday", "Happy Birthday", .tunes, "In 3/4, starting before the barline with a dotted eighth and a sixteenth.",
                key: .c, beats: 3, tempo: 100,
                bars: [.none, .each(c(1)), .each(c(5)), .each(c(5)), .each(c(1)),
                       .each(c(1)), .each(c(4)), .split((c(1), 2), (c(5), 1)), .each(c(1))],
                melody: """
                rh G3e. G3s | A3q G3q C4q | B3h G3e. G3s | A3q G3q D4q | C4h G3e. G3s |
                G4q E4q C4q | B3q A3q F4e. F4s | E4q C4q D4q | C4h.
                """),
        example("canon-melody", "Canon in D", .tunes, "Pachelbel's falling line in half notes, then the quarter-note variation, over the Canon's chords.",
                key: .d, tempo: 76,
                bars: [.each(c(1), c(5)), .each(c(6), c(3)), .each(c(4), c(1)), .each(c(4), c(5)),
                       .each(c(1), c(5)), .each(c(6), c(3)), .each(c(4), c(1)), .each(c(4), c(5))],
                melody: """
                F#4h E4h | D4h C#4h | B3h A3h | B3h C#4h |
                D4q F#4q A4q G4q | F#4q D4q F#4q E4q | D4q B3q D4q A4q | G4q B4q A4q G4q
                """),
        example("greensleeves", "Greensleeves", .tunes, "The old English tune in A minor: dotted rhythms, sharps from outside the key, and a tie to finish.",
                key: .a, minor: true, beats: 3, tempo: 104,
                bars: [.none, .each(c(1)), .each(c(3)), .each(c(7)), .each(c(5)),
                       .each(c(1)), .each(c(6)), .each(c(5, .major)), .each(c(5, .major)),
                       .each(c(1)), .each(c(3)), .each(c(7)), .each(c(5)),
                       .each(c(1)), .each(c(5, .major)), .each(c(1)), .each(c(1))],
                melody: """
                rh A3q | C4h D4q | E4q. F4e E4q | D4h B3q | G3q. A3e B3q |
                C4h A3q | A3q. G#3e A3q | B3h G#3q | E3h A3q |
                C4h D4q | E4q. F4e E4q | D4h B3q | G3q. A3e B3q |
                C4q. B3e A3q | G#3q. F#3e G#3q | A3h.~ | A3h.
                """),
        example("fur-elise", "Für Elise", .tunes, "The opening of Beethoven's piano piece, an octave down to sit on the guitar: running eighths and rests.",
                key: .a, minor: true, beats: 3, tempo: 120,
                bars: [.none, .each(c(5, .dominant7)), .each(c(1)), .each(c(5, .major)), .each(c(1)),
                       .each(c(5, .dominant7)), .each(c(1)), .each(c(5, .major)), .each(c(1))],
                melody: """
                rh E4e D#4e | E4e D#4e E4e B3e D4e C4e | A3q re C3e E3e A3e | B3q re E3e G#3e B3e |
                C4q re E3e E4e D#4e | E4e D#4e E4e B3e D4e C4e | A3q re C3e E3e A3e | B3q re E3e C4e B3e | A3h.
                """),

        // ── Advanced ──
        template("two-five-one", .advanced, "The cadence at the heart of jazz, in seventh chords.", tempo: 120),
        example("walking-bass", "Walking Bass Line", .advanced, "Inversions let the lowest note step down the scale: C, G/B, Am, C/G, F, C/E, Dm7, G7.",
                key: .c, tempo: 88,
                bars: [.each(c(1), c(5, inversion: 1)), .each(c(6), c(1, inversion: 2)),
                       .each(c(4), c(1, inversion: 1)), .each(c(2, .seventh), c(5, .seventh))]),
        example("borrowed", "Borrowed Colours", .advanced, "Chords from the minor key in a major one: ♭VII, a minor iv, and ♭VI–♭VII back home.",
                key: .c, tempo: 92,
                bars: [.each(c(1)), .each(c(7, .major, shift: -1)), .each(c(4)), .each(c(4, .minor)),
                       .each(c(1)), .each(c(6, .major, shift: -1)), .each(c(7, .major, shift: -1)), .each(c(1))]),
        example("turnaround", "Jazz Turnaround", .advanced, "Two chords a bar, with V7/ii pulling to the ii each time round.",
                key: .c, tempo: 120,
                bars: [.each(c(1, .seventh), c(5, .dominant7, secondary: 2)), .each(c(2, .seventh), c(5, .seventh)),
                       .each(c(3, .seventh), c(5, .dominant7, secondary: 2)), .each(c(2, .seventh), c(5, .seventh))]),
        example("circle-minor", "Circle of Fifths in Minor", .advanced, "Each chord a fifth below the last, all the way home: the changes under a hundred jazz standards.",
                key: .a, minor: true, tempo: 116,
                bars: [.each(c(4, .seventh)), .each(c(7, .seventh)), .each(c(3, .seventh)), .each(c(6, .seventh)),
                       .each(c(2, .seventh)), .each(c(5, .dominant7)), .each(c(1)), .each(c(1))]),
        example("rhythm-workout", "Rhythm Workout", .advanced, "Sixteenths, triplets, a dotted eighth and ties across the beat and the barline, over I–vi–IV–V7.",
                key: .c, tempo: 84,
                bars: [.each(c(1)), .each(c(6)), .each(c(4)), .each(c(5, .seventh))],
                melody: """
                C3s D3s E3s G3s E3e G3e C4q~ C4e B3e |
                A3t C4t E4t D4q C4e. B3s A3q~ |
                A3q F3t A3t C4t A3e G3e F3q |
                G3e. A3s B3e D4e F4t D4t B3t G3q
                """),
    ].compactMap { $0 }
}

// MARK: - Melody notation

extension Composition {

    /// Writes a melody given as text, measure by measure: notes like `F#4q` (a letter, `#` or
    /// `b`, the octave it sounds in, and a length) and rests like `rq`, with `|` between
    /// measures and `~` after a note to tie it to the next. Lengths: `w` whole, `h.` dotted
    /// half, `h` half, `q.` dotted quarter, `q` quarter, `e.` dotted eighth, `e` eighth,
    /// `s` sixteenth, `t` triplet eighth.
    ///
    /// It has to say exactly what's in each measure: returns what's wrong if a measure doesn't
    /// add up, a note isn't understood or wouldn't fit as written, or a tie doesn't hold;
    /// nil if all went in.
    mutating func write(melody text: String) -> String? {
        let lengths: [(code: String, value: NoteValue)] = [
            ("h.", .dottedHalf), ("q.", .dottedQuarter), ("e.", .dottedEighth),
            ("w", .whole), ("h", .half), ("q", .quarter), ("e", .eighth), ("s", .sixteenth), ("t", .tripletEighth),
        ]
        let measures = text.split(separator: "|").map { $0.split(whereSeparator: \.isWhitespace).map(String.init) }
        guard measures.count <= measureCount else { return "\(measures.count) measures of melody for \(measureCount)" }
        var ties: [Int] = []
        for (measure, tokens) in measures.enumerated() {
            var tick = measure * ticksPerMeasure
            for token in tokens {
                var body = token
                let tied = body.hasSuffix("~")
                if tied { body.removeLast() }
                guard let length = lengths.first(where: { body.hasSuffix($0.code) }) else { return "measure \(measure + 1): \(token)?" }
                body.removeLast(length.code.count)
                if body != "r" {
                    let letters = ["C", "D", "E", "F", "G", "A", "B"]
                    guard let letter = letters.firstIndex(of: String(body.prefix(1))), let octave = Int(body.suffix(1)), body.count >= 2 else {
                        return "measure \(measure + 1): \(token)?"
                    }
                    let sign = String(body.dropFirst().dropLast())
                    guard let accidental = ["": 0, "#": 1, "b": -1][sign] else { return "measure \(measure + 1): \(token)?" }
                    let pitch = SpelledPitch(letter: letter, accidental: accidental, octave: octave)
                    guard snapped(tick, for: length.value) == tick, placeNote(pitch, at: tick, value: length.value) == length.value else {
                        return "measure \(measure + 1): \(token) doesn't fit there"
                    }
                    if tied { ties.append(tick) }
                } else if tied {
                    return "measure \(measure + 1): a rest can't be tied"
                }
                tick += length.value.ticks
            }
            guard tick == (measure + 1) * ticksPerMeasure else { return "measure \(measure + 1) doesn't add up" }
        }
        for start in ties {
            guard let note = melody.first(where: { $0.start == start }), let next = melody.first(where: { $0.start == note.end }),
                  next.pitch == note.pitch, toggleTie(ofNoteAt: start), tiesForward(note) || melody.first(where: { $0.start == start }).map(tiesForward) == true else {
                return "the tie at tick \(start) has nothing to hold on to"
            }
        }
        return nil
    }
}
