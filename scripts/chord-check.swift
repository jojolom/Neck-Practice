//
//  chord-check.swift
//
//  Offline check for Composition: ChordAnalyzer hears synthetic guitar strums (harmonics,
//  decay, detuning, noise, and a weak low fundamental like a phone mic gives) as the chord
//  that was played and not as its near neighbours (C vs Am, D vs Dm), seventh chords with or
//  without their 5th, and single melody notes as themselves rather than their neighbours or
//  5ths; the Play Along level bars stay in range, low for room noise, and glide rather than
//  jump; chord symbols spell right in every key (V7 in E♭ is B♭7, ♭VII in C is B♭, V/V is D,
//  C/E is I⁶); the Composition model keeps every measure adding up in both the chords and the
//  melody (their own lengths, shortened to fit, rests in the gaps) through any edits, meter
//  changes and duplicated measures; accidentals print as they should through a measure; the
//  templates fill their measures; and compositions saved before (or by an older version of the
//  app reading new ones) load as the same music.
//
//  Run from the repo root:
//    swiftc -O -parse-as-library -o /tmp/chord-check "Guitar Man/NeckPracticeModelsNote.swift" "Guitar Man/NeckPracticeModelsNotation.swift" "Guitar Man/NeckPracticeModelsRomanNumeral.swift" "Guitar Man/NeckPracticeModelsChord.swift" "Guitar Man/NeckPracticeModelsComposition.swift" "Guitar Man/NeckPracticeModelsCompositionTemplates.swift" "Guitar Man/NeckPracticeModelsCompositionHearing.swift" "Guitar Man/NeckPracticeModelsCompositionFile.swift" "Guitar Man/NeckPracticeModelsCompositionExamples.swift" "Guitar Man/NeckPracticeServicesChordAnalyzer.swift" "Guitar Man/NeckPracticeServicesPitchAnalyzer.swift" scripts/chord-check.swift && /tmp/chord-check
//

import Foundation

@main
struct ChordCheck {

    static var failures = 0

    static func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition {
            print("FAIL", message())
            failures += 1
        }
    }

    static func main() {
        checkAnalyzer()
        checkSeventhsAndNotes()
        checkDisplayLevels()
        checkComposition()
        checkChordSymbols()
        checkMelody()
        checkAccidentals()
        checkTemplates()
        print(failures == 0 ? "All chord checks passed." : "\(failures) failure(s).")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Synth

    static let sampleRate = 48_000.0

    /// One plucked string: harmonics that decay faster the higher they are.
    static func pluck(midi: Int, cents: Double, amps: [Double], seconds: Double) -> [Double] {
        let f = 440 * pow(2, (Double(midi - 69) + cents / 100) / 12)
        let n = Int(sampleRate * seconds)
        var out = [Double](repeating: 0, count: n)
        for (k, a) in amps.enumerated() {
            let fk = f * Double(k + 1)
            guard fk < sampleRate / 2 else { break }
            let decay = 1.5 + 0.8 * Double(k + 1)
            for i in 0..<n {
                let t = Double(i) / sampleRate
                out[i] += a * exp(-decay * t) * sin(2 * Double.pi * fk * t)
            }
        }
        return out
    }

    // MARK: Writing by playing

    /// What a strum of `midis` is heard as among `candidates`, on the analyzer's own window.
    static func heard(_ midis: [Int], weak: Bool, candidates: [CompositionChord]) -> CompositionChord? {
        let chroma = ChordAnalyzer.chroma(samples: strum(midis, weakLowFundamental: weak), sampleRate: sampleRate)
        return ComposeHearing.chord(in: chroma, candidates: candidates)
    }

    /// A guitar voicing of `chord`: its notes stacked from the bass up over two octaves, six strings' worth.
    static func voicing(_ chord: CompositionChord) -> [Int] {
        let classes = chord.pitches.map { $0.note.rawValue }
        var midis: [Int] = []
        var midi = 40
        while midis.count < 6 && midi < 80 {
            if midis.isEmpty ? midi % 12 == classes[0] : classes.contains(midi % 12) && midi - (midis.last ?? 0) >= 2 { midis.append(midi) }
            midi += 1
        }
        return midis
    }

    static func hearing() {
        // Spelling a heard note for the key.
        func name(_ midi: Int, _ root: Note, minor: Bool = false) -> String {
            ComposeHearing.spell(midi: midi, in: KeySignature(root: root, isMinor: minor)).name
        }
        check(name(66, .g) == "F♯" && name(65, .g) == "F" && name(63, .c) == "D♯" && name(63, .f) == "E♭"
              && name(70, .dSharp) == "B♭" && name(61, .a) == "C♯" && name(60, .cSharp) == "C",
              "heard notes are spelled for the key")
        for midi in 40...88 {
            for root in Note.allCases {
                let pitch = ComposeHearing.spell(midi: midi, in: KeySignature(root: root, isMinor: false))
                if pitch.midi != midi || abs(pitch.accidental) > 1 { check(false, "spelling \(midi) in \(root): \(pitch)") }
            }
        }

        // Single notes anywhere on the neck: the right note and octave, strong or weak fundamental.
        var right = 0, wrong: [String] = [], unheard = 0
        for midi in 40...86 {
            for weak in [false, true] {
                let amps = weak ? [0.25, 0.8, 0.6, 0.4, 0.25, 0.15, 0.1] : [1, 0.6, 0.45, 0.3, 0.2, 0.12, 0.08]
                let samples = pluck(midi: midi, cents: Double.random(in: -12...12), amps: amps, seconds: 0.45)
                    .map { Float($0 + 0.01 * Double.random(in: -1...1)) }
                let window = Array(samples[2000..<2000 + PitchAnalyzer.windowSize])
                let frequency = PitchAnalyzer.detectFrequency(in: window, sampleRate: sampleRate, maxFrequency: 1400, anyString: true)
                let chroma = ChordAnalyzer.chroma(samples: Array(samples.prefix(ChordAnalyzer.windowSize * ChordAnalyzer.decimation)),
                                                  sampleRate: sampleRate)
                switch ComposeHearing.midi(frequency: frequency, chroma: chroma) {
                case midi?:  right += 1
                case nil:    unheard += 1
                case let other?: wrong.append("\(midi)\(weak ? "w" : "") as \(other)")
                }
            }
        }
        check(wrong.isEmpty && unheard <= 4, "single notes: \(right) right, \(unheard) unheard, wrong: \(wrong)")
        // A strummed chord isn't taken for a note.
        let cChord = strum([48, 52, 55, 60, 64], weakLowFundamental: false)
        let cChroma = ChordAnalyzer.chroma(samples: cChord, sampleRate: sampleRate)
        let cFrequency = PitchAnalyzer.detectFrequency(in: Array(cChord[2000..<2000 + PitchAnalyzer.windowSize]), sampleRate: sampleRate,
                                                       maxFrequency: 1400, anyString: true)
        let asNote = ComposeHearing.midi(frequency: cFrequency, chroma: cChroma)
        check(asNote == nil || asNote! % 12 == 0, "a C chord isn't heard as some other note: \(String(describing: asNote))")

        // Chords: every chord Compose offers in a few keys is heard as itself.
        var heardRight = 0, total = 0, misheard: [String] = []
        for (root, minor) in [(Note.c, false), (.g, false), (.dSharp, false), (.a, true), (.e, true)] {
            var composition = Composition()
            composition.setKey(root: root, isMinor: minor)
            let candidates = ComposeHearing.candidates(for: composition)
            for candidate in candidates {
                for weak in [false, true] {
                    total += 1
                    let result = heard(voicing(candidate), weak: weak, candidates: candidates)
                    if result?.symbol == candidate.symbol { heardRight += 1 } else {
                        misheard.append("\(candidate.name)\(weak ? "w" : "")→\(result?.name ?? "nothing")")
                    }
                }
            }
        }
        check(Double(heardRight) >= 0.9 * Double(total), "chords heard as themselves: \(heardRight) of \(total); not: \(misheard)")
        print("     writing by playing: \(right) of 94 notes, \(heardRight) of \(total) chords\(misheard.isEmpty ? "" : " (not: \(misheard.joined(separator: " ")))")")

        // A note counts once per pluck: not while it rings on, and not without a pluck.
        var notes = NoteTracker()
        var played: [Int] = []
        func feed(_ sequence: [Int?]) { for midi in sequence { if let note = notes.hear(midi) { played.append(note) } } }
        feed([60, 60, 60])
        check(played.isEmpty, "no pluck, no note")
        notes.attack(); feed([60, 60, 60, 60, nil, 60, 60, 60, 62, 62, 62])
        check(played == [60], "one pluck, one note: \(played)")
        notes.attack(); feed([61, 60, 60, 60])
        check(played == [60, 60], "plucked again: \(played)")
        notes.attack(); feed([nil, 62, nil, 64, 64])
        check(played == [60, 60, 64], "it waits for the note to settle: \(played)")
        var chords = ChordTracker()
        let one = ChordSymbol(degree: 1), five = ChordSymbol(degree: 5)
        var strummed: [ChordSymbol] = []
        func feedChords(_ sequence: [ChordSymbol?]) { for symbol in sequence { if let chord = chords.hear(symbol) { strummed.append(chord) } } }
        feedChords([one, one, one])
        check(strummed.isEmpty, "no strum, no chord")
        chords.attack(); feedChords([five, one, one, one, one, five, five])
        check(strummed == [one], "one strum, one chord: \(strummed)")
        chords.attack(); feedChords([nil, five, five])
        check(strummed == [one, five], "the next strum: \(strummed)")

        // A take played in time goes on the nearest beat (or eighth), ringing to the next or the barline.
        var take = Composition()
        take.place(4, at: 0, value: .whole)
        take.place(4, at: 4, value: .whole)
        let written = take.write(chords: [.init(beat: 0.1, value: one), .init(beat: 1.9, value: five), .init(beat: 4.2, value: one),
                                          .init(beat: -0.3, value: five), .init(beat: 9.6, value: five)], fromMeasure: 1)
        check(written == 1...3 && take.chords.map { "\($0.start):\($0.beats):\($0.symbol.degree)" } == ["0:4:4", "4:2:5", "6:2:5", "8:4:1", "12:2:1", "14:2:5"]
              && take.chords.map(\.tied) == [false, false, false, true, false, false],
              "chords in time: \(String(describing: written)) \(take.chords.map { "\($0.start):\($0.beats):\($0.symbol.degree)" })")
        let e4 = SpelledPitch(letter: 2, octave: 4), g4 = SpelledPitch(letter: 4, octave: 4)
        let notesWritten = take.write(notes: [.init(beat: 0.02, value: e4), .init(beat: 0.55, value: g4), .init(beat: 2.2, value: e4)], fromMeasure: 0)
        check(notesWritten == 0...0 && take.melody.map { "\($0.start):\($0.length)" } == ["0:6", "6:18", "24:24"],
              "notes in time: \(take.melody.map { "\($0.start):\($0.length)" })")
        check(take.write(chords: [], fromMeasure: 0) == nil && take.write(notes: [.init(beat: 3, value: e4)], fromMeasure: 40) == nil, "nothing to write")
        var long = Composition()
        check(long.write(chords: [.init(beat: 4.0 * 40, value: one), .init(beat: 0, value: one)], fromMeasure: 0) == 0...(Composition.measureRange.upperBound - 1)
              && long.measureCount == Composition.measureRange.upperBound && long.chords.count == 1, "a take stops at the most measures")

        // Tablature: the lowest fret, unless it was entered on a string.
        var tab = Composition()
        tab.placeNote(e4, at: 0, value: .quarter)
        tab.placeNote(e4, at: 12, value: .quarter, string: 1)
        tab.placeNote(SpelledPitch(letter: 2, octave: 2), at: 24, value: .quarter)
        let positions = tab.melody.map { tab.tabPosition(of: $0) }.map { "\($0?.string ?? -1)/\($0?.fret ?? -1)" }
        check(positions == ["0/0", "1/5", "5/0"], "tab positions: \(positions)")
        let reloaded = try? JSONDecoder().decode(Composition.self, from: JSONEncoder().encode(tab))
        check(reloaded?.melody.map(\.string) == [nil, 1, nil], "the string is saved")
        tab.insertMeasure(at: 0)
        tab.setKey(root: .d, isMinor: false)
        check(tab.melody.allSatisfy { $0.string == nil } && tab.melody.allSatisfy { tab.tabPosition(of: $0) != nil }, "a key change picks new positions")
    }

    static func strum(_ midis: [Int], weakLowFundamental: Bool) -> [Float] {
        let normal = [1, 0.6, 0.45, 0.3, 0.2, 0.12, 0.08]
        let weak = [0.25, 0.8, 0.6, 0.4, 0.25, 0.15, 0.1]
        var total = [Double](repeating: 0, count: Int(sampleRate * 0.45))
        for midi in midis {
            let amps = weakLowFundamental && midi < 52 ? weak : normal
            let string = pluck(midi: midi, cents: Double.random(in: -15...15), amps: amps, seconds: 0.45)
            for i in total.indices { total[i] += string[i] }
        }
        // Gaussian-ish noise (sum of uniforms).
        return total.map { Float($0 + 0.02 * (Double.random(in: -1...1) + Double.random(in: -1...1) + Double.random(in: -1...1))) }
    }

    // MARK: - Analyzer

    static func checkAnalyzer() {
        // Common guitar voicings, low to high, with their pitch classes.
        let voicings: [(name: String, midis: [Int], tones: Set<Int>)] = [
            ("C", [48, 52, 55, 60, 64], [0, 4, 7]),
            ("Am", [45, 52, 57, 60, 64], [9, 0, 4]),
            ("G", [43, 47, 50, 55, 59, 67], [7, 11, 2]),
            ("Em", [40, 47, 52, 55, 59, 64], [4, 7, 11]),
            ("F", [41, 48, 53, 57, 60, 65], [5, 9, 0]),
            ("Dm", [50, 57, 62, 65], [2, 5, 9]),
            ("D", [50, 57, 62, 66], [2, 6, 9]),
            ("E", [40, 47, 52, 56, 59, 64], [4, 8, 11]),
            ("B°", [47, 50, 53, 59], [11, 2, 5]),
            ("A♭", [44, 51, 56, 60, 63, 68], [8, 0, 3]),
        ]
        var heard = 0, total = 0
        for weak in [false, true] {
            for played in voicings {
                for _ in 0..<2 {
                    let chroma = ChordAnalyzer.chroma(samples: strum(played.midis, weakLowFundamental: weak),
                                                      sampleRate: sampleRate)
                    check(abs(chroma.reduce(0, +) - 1) < 1e-6, "chroma sums to 1")
                    total += 1
                    if ChordAnalyzer.matches(chroma: chroma, pitchClasses: played.tones) { heard += 1 }
                    for other in voicings where other.name != played.name {
                        check(!ChordAnalyzer.matches(chroma: chroma, pitchClasses: other.tones),
                              "\(played.name)\(weak ? " (weak low end)" : "") heard as \(other.name)")
                    }
                }
            }
        }
        // Single frames can miss (the app needs two in a row while the chord rings), but nearly all should hit.
        check(Double(heard) / Double(total) >= 0.9, "heard \(heard) of \(total) strums")
        print("ok   analyzer: heard \(heard) of \(total) single-frame strums, no wrong chords")

        let silence = ChordAnalyzer.chroma(samples: [Float](repeating: 0, count: 20_000), sampleRate: sampleRate)
        check(silence.allSatisfy { $0 == 0 }, "silence has no chroma")
        check(!ChordAnalyzer.matches(chroma: silence, pitchClasses: [0, 4, 7]), "silence isn't a chord")
    }

    // MARK: - Level bars

    static func checkDisplayLevels() {
        let zeros = [Double](repeating: 0, count: 12)
        let cMajor: Set<Int> = [0, 4, 7]
        func meanChange(_ a: [Double], _ b: [Double]) -> Double {
            zip(a, b).map { abs($0 - $1) }.reduce(0, +) / 12
        }

        // Quiet room noise (about -50 dBFS) keeps the bars low.
        var levels = zeros
        for _ in 0..<30 {
            let noise = (0..<20_000).map { _ in Float(Double.random(in: -0.005...0.005)) }
            let chroma = ChordAnalyzer.chroma(samples: noise, sampleRate: sampleRate)
            levels = ChordAnalyzer.displayLevels(previous: levels, chroma: chroma, rms: 0.003)
        }
        check(levels.allSatisfy { $0 <= 0.2 }, "room noise bars stay low (max \(levels.max()!))")

        // A loud C strum ringing out: each frame a fresh, noisy analysis, getting quieter.
        levels = zeros
        var previousRaw = zeros
        var rawJitter = 0.0, smoothJitter = 0.0, maxDrop = 0.0
        var rms: Float = 0.3  // louder than full scale on the bars
        for frame in 0..<20 {
            let chroma = ChordAnalyzer.chroma(samples: strum([48, 52, 55, 60, 64], weakLowFundamental: true),
                                              sampleRate: sampleRate)
            let next = ChordAnalyzer.displayLevels(previous: levels, chroma: chroma, rms: rms)
            check(next.allSatisfy { (0...1).contains($0) }, "bars stay within 0–1")
            if frame == 2 {
                check(cMajor.allSatisfy { next[$0] >= 0.3 }, "a strum raises its notes' bars within 3 frames")
            }
            let peak = chroma.max() ?? 1
            let raw = chroma.map { $0 / peak }
            if frame > 0 {
                rawJitter += meanChange(raw, previousRaw)
                smoothJitter += meanChange(next, levels)
                maxDrop = max(maxDrop, zip(levels, next).map { $0 - $1 }.max() ?? 0)
            }
            previousRaw = raw
            levels = next
            rms *= 0.8
        }
        check(smoothJitter < rawJitter / 2,
              "bars move less than half as much as the raw analysis (\(smoothJitter) vs \(rawJitter))")
        check(maxDrop <= 0.16, "bars fall gradually (largest drop \(maxDrop))")

        // Garbage in (NaN) leaves the bars alone.
        let kept = ChordAnalyzer.displayLevels(previous: levels, chroma: [Double](repeating: .nan, count: 12), rms: 0.1)
        check(kept == levels, "NaN analysis is ignored")
        print("ok   level bars")
    }

    // MARK: - Composition

    static func checkComposition() {
        var c = Composition()
        c.keyRoot = .dSharp            // E♭ major
        check(c.keyName == "E♭ Major", "key name \(c.keyName)")
        let four = c.chord(degree: 4)
        check(four.romanNumeral == "IV" && four.name == "A♭" && four.longName == "A♭ major", "IV in E♭: \(four.longName)")
        check(four.pitches.map(\.name) == ["A♭", "C", "E♭"], "A♭ major notes \(four.pitches.map(\.name))")
        check(c.chord(degree: 7).name == "D°", "vii° in E♭: \(c.chord(degree: 7).name)")

        c.isMinor = true
        c.keyRoot = .c                 // C minor
        check(c.keyName == "C Minor", "key name \(c.keyName)")
        check(c.chord(degree: 5).name == "Gm" && c.chord(degree: 3).name == "E♭", "C minor chords")

        // Every chord in every key: three notes stacked in thirds, single accidentals, the right quality.
        for minor in [false, true] {
            for root in Note.allCases {
                var k = Composition()
                k.keyRoot = root
                k.isMinor = minor
                for degree in 1...7 {
                    let chord = k.chord(degree: degree)
                    let p = chord.pitches
                    check(p.count == 3 && p.allSatisfy { abs($0.accidental) <= 1 }, "\(k.keyName) \(degree): \(p.map(\.name))")
                    check(p[1].diatonicNumber - p[0].diatonicNumber == 2 && p[2].diatonicNumber - p[1].diatonicNumber == 2,
                          "\(k.keyName) \(degree): stacked in thirds")
                    let third = p[1].midi - p[0].midi, fifth = p[2].midi - p[0].midi
                    switch chord.quality {
                    case .major:      check(third == 4 && fifth == 7, "\(k.keyName) \(degree) major")
                    case .minor:      check(third == 3 && fifth == 7, "\(k.keyName) \(degree) minor")
                    case .diminished: check(third == 3 && fifth == 6, "\(k.keyName) \(degree) diminished")
                    }
                }
            }
        }

        // Placing chords: each its own length, shortened to fit, never crossing a barline.
        var r = Composition()
        check(r.beatsPerMeasure == 4 && r.measureCount == 4 && r.isEmpty, "defaults")
        check(r.place(1, at: 0, value: .quarter) == 1 && r.place(4, at: 1, value: .quarter) == 1
              && r.place(5, at: 2, value: .half) == 2, "two quarters and a half")
        check(r.rests(inMeasure: 0).isEmpty, "a full measure has no rests")
        check(r.place(6, at: 6, value: .whole) == 2, "a whole note on beat 3 is shortened to the barline")
        check(r.rests(inMeasure: 1) == [Composition.Rest(start: 4, beats: 2, glyph: .half)], "half rest on beat 1: \(r.rests(inMeasure: 1))")
        check(r.place(2, at: 3, value: .quarter) == 1 && r.chord(covering: 2)?.beats == 1,
              "a chord placed inside a ringing one cuts it short: \(r.chords)")
        check(r.place(3, at: 5, value: .dottedHalf) == 1, "shortened to fit before the next chord")
        r.setLength(ofChordAt: 5, to: .whole)
        check(r.chord(covering: 5)?.beats == 1, "can't grow into the next chord")
        r.removeChord(covering: 7)
        r.setLength(ofChordAt: 5, to: .whole)
        check(r.chord(covering: 5)?.beats == 3, "grows to the barline once there's room: \(r.chords)")
        check(r.place(1, at: 16, value: .quarter) == nil && r.place(9, at: 0, value: .quarter) == nil, "out of range")

        // Rests as they're written.
        var q = Composition()
        q.place(1, at: 1, value: .quarter)
        check(q.rests(inMeasure: 0) == [.init(start: 0, beats: 1, glyph: .quarter), .init(start: 2, beats: 2, glyph: .half)],
              "4/4, chord on beat 2: \(q.rests(inMeasure: 0))")
        check(q.rests(inMeasure: 1) == [.init(start: 4, beats: 4, glyph: .whole)], "empty measure: whole rest")
        q.setBeatsPerMeasure(3)
        q.clearChords()
        q.place(1, at: 0, value: .quarter)
        check(q.rests(inMeasure: 0) == [.init(start: 1, beats: 1, glyph: .quarter), .init(start: 2, beats: 1, glyph: .quarter)],
              "3/4, beats 2-3 are two quarter rests: \(q.rests(inMeasure: 0))")
        check(q.rests(inMeasure: 1) == [.init(start: 3, beats: 3, glyph: .whole)], "empty 3/4 measure: whole rest")

        // Meter and measure changes keep chords on their beats.
        var m = Composition()
        m.place(1, at: 0, value: .whole)
        m.place(4, at: 4, value: .quarter)
        m.place(5, at: 7, value: .quarter)
        m.place(6, at: 8, value: .half)
        m.setBeatsPerMeasure(3)
        check(m.chords.map(\.start) == [0, 3, 6] && m.chords.map(\.beats) == [3, 1, 2] && m.chords.map(\.symbol.degree) == [1, 4, 6],
              "4/4 → 3/4 drops beat 4, shortens the whole: \(m.chords)")
        m.setBeatsPerMeasure(4)
        check(m.chords.map(\.start) == [0, 4, 8], "3/4 → 4/4 keeps each chord in its measure: \(m.chords)")
        m.setMeasureCount(2)
        check(m.chords.map(\.start) == [0, 4], "fewer measures drop the end")
        m.setMeasureCount(1)
        check(m.measureCount == 2, "at least 2 measures")

        // Every measure adds up, whatever the edits.
        var fuzz = Composition()
        for step in 0..<2000 {
            switch Int.random(in: 0..<10) {
            case 0: fuzz.setBeatsPerMeasure(Composition.meters.randomElement()!)
            case 1: fuzz.setMeasureCount(Int.random(in: 1...9))
            case 2: fuzz.removeChord(covering: Int.random(in: 0..<fuzz.totalBeats))
            case 3: if let c = fuzz.chords.randomElement() { fuzz.setLength(ofChordAt: c.start, to: NoteValue.allCases.randomElement()!) }
            case 4: fuzz.duplicateMeasure(Int.random(in: 0..<fuzz.measureCount))
            default: fuzz.place(Int.random(in: 1...7), at: Int.random(in: 0..<fuzz.totalBeats), value: NoteValue.allCases.randomElement()!)
            }
            var ok = zip(fuzz.chords, fuzz.chords.dropFirst()).allSatisfy { $0.end <= $1.start }
            for c in fuzz.chords {
                ok = ok && (1...4).contains(c.beats) && c.end <= fuzz.totalBeats
                    && c.start / fuzz.beatsPerMeasure == (c.end - 1) / fuzz.beatsPerMeasure
            }
            for measure in 0..<fuzz.measureCount {
                let lo = measure * fuzz.beatsPerMeasure, hi = lo + fuzz.beatsPerMeasure
                let chordBeats = fuzz.chords.filter { $0.start >= lo && $0.start < hi }.reduce(0) { $0 + $1.beats }
                let restBeats = fuzz.rests(inMeasure: measure).reduce(0) { $0 + $1.beats }
                ok = ok && chordBeats + restBeats == fuzz.beatsPerMeasure
            }
            if !ok { check(false, "step \(step): \(fuzz.meterName) \(fuzz.chords)"); break }
        }

        // Saving, and compositions saved before chords had their own lengths.
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        let saved = try! decoder.decode(Composition.self, from: encoder.encode(r))
        check(saved == r, "saves and loads")
        func legacy(_ value: String, _ slots: String, measures: Int) -> Composition {
            let json = """
            {"id":"\(UUID().uuidString)","name":"Old","keyRoot":0,"isMinor":false,"measureCount":\(measures),
             "noteValue":"\(value)","slots":\(slots),"updatedAt":0}
            """
            return try! decoder.decode(Composition.self, from: Data(json.utf8))
        }
        let whole = legacy("whole", "[1,4,null,5]", measures: 4)
        check(whole.beatsPerMeasure == 4 && whole.chords.map(\.start) == [0, 4, 12] && whole.chords.allSatisfy { $0.beats == 4 },
              "old whole notes: \(whole.chords)")
        let quarters = legacy("quarter", "[1,null,6,4,5,null,null,null]", measures: 2)
        check(quarters.chords.map(\.start) == [0, 2, 3, 4] && quarters.chords.allSatisfy { $0.beats == 1 },
              "old quarters: \(quarters.chords)")
        let dotted = legacy("dottedHalf", "[1,4,5]", measures: 3)
        check(dotted.beatsPerMeasure == 3 && dotted.chords.map(\.start) == [0, 3, 6] && dotted.chords.allSatisfy { $0.beats == 3 },
              "old dotted halves become 3/4: \(dotted.chords)")
        print("ok   composition")
    }
    // MARK: - Sevenths and single notes

    static func checkSeventhsAndNotes() {
        // Seventh chords, some without their 5th as guitar shapes play them.
        let sevenths: [(name: String, midis: [Int], required: Set<Int>, optional: Set<Int>)] = [
            ("G7", [43, 47, 50, 55, 59, 65], [7, 11, 5], [2]),     // 320001
            ("C7", [48, 52, 58, 60, 64], [0, 4, 10], [7]),          // x32310 (no G)
            ("Am7", [45, 52, 55, 60, 64], [9, 0, 7], [4]),          // x02010
            ("Cmaj7", [48, 52, 55, 59, 64], [0, 4, 11], [7]),       // x32000
        ]
        var heard = 0, total = 0
        for weak in [false, true] {
            for played in sevenths {
                for _ in 0..<2 {
                    let chroma = ChordAnalyzer.chroma(samples: strum(played.midis, weakLowFundamental: weak), sampleRate: sampleRate)
                    total += 1
                    if ChordAnalyzer.matches(chroma: chroma, pitchClasses: played.required, optional: played.optional) { heard += 1 }
                }
            }
            // A plain triad isn't its seventh chord: the 7th is missing.
            let g = ChordAnalyzer.chroma(samples: strum([43, 47, 50, 55, 59, 67], weakLowFundamental: weak), sampleRate: sampleRate)
            check(!ChordAnalyzer.matches(chroma: g, pitchClasses: [7, 11, 5], optional: [2]), "G heard as G7")
            let c = ChordAnalyzer.chroma(samples: strum([48, 52, 55, 60, 64], weakLowFundamental: weak), sampleRate: sampleRate)
            check(!ChordAnalyzer.matches(chroma: c, pitchClasses: [0, 4, 11], optional: [7]), "C heard as Cmaj7")
        }
        check(Double(heard) / Double(total) >= 0.9, "heard \(heard) of \(total) seventh-chord strums")

        // Single notes across the neck: heard as themselves, not a half step off or as their 5th.
        var notesHeard = 0, notesTotal = 0
        for weak in [false, true] {
            for midi in stride(from: 40, through: 79, by: 3) {
                let samples = strum([midi], weakLowFundamental: weak)
                let chroma = ChordAnalyzer.chroma(samples: samples, sampleRate: sampleRate)
                notesTotal += 1
                if ChordAnalyzer.matchesNote(chroma: chroma, pitchClass: midi % 12) { notesHeard += 1 }
                for wrong in [midi + 1, midi - 1, midi + 7, midi + 5] {
                    check(!ChordAnalyzer.matchesNote(chroma: chroma, pitchClass: wrong % 12),
                          "note \(midi)\(weak ? " (weak)" : "") heard as pitch class \(wrong % 12)")
                }
            }
        }
        check(Double(notesHeard) / Double(notesTotal) >= 0.9, "heard \(notesHeard) of \(notesTotal) single notes")
        let chord = ChordAnalyzer.chroma(samples: strum([48, 52, 55, 60, 64], weakLowFundamental: false), sampleRate: sampleRate)
        check(!ChordAnalyzer.matchesNote(chroma: chord, pitchClass: 4) && !ChordAnalyzer.matchesNote(chroma: chord, pitchClass: 7),
              "a C chord isn't heard as its E or G: \(chord.map { Int($0 * 100) })")
        var share = 1.0
        for midi in stride(from: 40, through: 79, by: 1) {
            let chroma = ChordAnalyzer.chroma(samples: strum([midi], weakLowFundamental: true), sampleRate: sampleRate)
            share = min(share, chroma[midi % 12])
        }
        print("     single notes: smallest share on the note \(Int(share * 100))%")
        print("ok   sevenths and notes: \(heard) of \(total) seventh strums, \(notesHeard) of \(notesTotal) notes")
    }

    // MARK: - Chord symbols

    static func checkChordSymbols() {
        var c = Composition()
        func named(_ symbol: ChordSymbol) -> (String, String, [String]) {
            let chord = c.chord(symbol)
            return (chord.romanNumeral, chord.name, chord.pitches.map(\.name))
        }
        func expect(_ symbol: ChordSymbol, _ numeral: String, _ name: String, _ notes: [String]? = nil) {
            let (n, nm, p) = named(symbol)
            check(n == numeral && nm == name && (notes == nil || notes! == p),
                  "\(c.keyName) \(symbol): \(n) \(nm) \(p), wanted \(numeral) \(name) \(notes ?? [])")
        }
        // C major.
        expect(ChordSymbol(degree: 5, kind: .seventh), "V7", "G7", ["G", "B", "D", "F"])
        expect(ChordSymbol(degree: 2, kind: .seventh), "ii7", "Dm7", ["D", "F", "A", "C"])
        expect(ChordSymbol(degree: 1, kind: .seventh), "Imaj7", "Cmaj7", ["C", "E", "G", "B"])
        expect(ChordSymbol(degree: 7, kind: .seventh), "viiø7", "Bø7", ["B", "D", "F", "A"])
        expect(ChordSymbol(degree: 5, kind: .sus4), "Vsus4", "Gsus4", ["G", "C", "D"])
        expect(ChordSymbol(degree: 7, shift: -1, kind: .major), "♭VII", "B♭", ["B♭", "D", "F"])
        expect(ChordSymbol(degree: 6, shift: -1, kind: .major), "♭VI", "A♭", ["A♭", "C", "E♭"])
        expect(ChordSymbol(degree: 4, kind: .minor), "iv", "Fm", ["F", "A♭", "C"])
        expect(ChordSymbol(degree: 5, kind: .major, secondary: 5), "V/V", "D", ["D", "F♯", "A"])
        expect(ChordSymbol(degree: 5, kind: .dominant7, secondary: 6), "V7/vi", "E7", ["E", "G♯", "B", "D"])
        expect(ChordSymbol(degree: 1, inversion: 1), "I⁶", "C/E", ["E", "G", "C"])
        expect(ChordSymbol(degree: 1, inversion: 2), "I⁶₄", "C/G", ["G", "C", "E"])
        expect(ChordSymbol(degree: 5, kind: .seventh, inversion: 1), "V⁶₅", "G7/B")
        expect(ChordSymbol(degree: 5, kind: .seventh, inversion: 3), "V⁴₂", "G7/F")
        check(c.chord(ChordSymbol(degree: 5, kind: .seventh)).requiredPitchClasses == [7, 11, 5], "G7 can leave out its D")
        check(c.chord(ChordSymbol(degree: 7, kind: .seventh)).requiredPitchClasses.count == 4, "Bø7 needs its F")
        // E♭ major and A minor.
        c.keyRoot = .dSharp
        expect(ChordSymbol(degree: 5, kind: .seventh), "V7", "B♭7", ["B♭", "D", "F", "A♭"])
        expect(ChordSymbol(degree: 7, shift: -1, kind: .major), "♭VII", "D♭")
        c.keyRoot = .cSharp
        expect(ChordSymbol(degree: 6, shift: -1, kind: .major), "♭VI", "A", ["A", "C♯", "E"])
        c.keyRoot = .a
        c.isMinor = true
        expect(ChordSymbol(degree: 5), "v", "Em")
        expect(ChordSymbol(degree: 5, kind: .major), "V", "E", ["E", "G♯", "B"])
        expect(ChordSymbol(degree: 5, kind: .dominant7), "V7", "E7")
        expect(ChordSymbol(degree: 7, shift: 1, kind: .diminished), "vii°", "G♯°", ["G♯", "B", "D"])
        expect(ChordSymbol(degree: 2, shift: -1, kind: .major), "♭II", "B♭")
        expect(ChordSymbol(degree: 7), "VII", "G")
        expect(ChordSymbol(degree: 2, kind: .seventh), "iiø7", "Bø7")
        check(CompositionChord.variants(degree: 5, keySignature: c.keySignature, isMinor: true)
                .contains(ChordSymbol(degree: 5, kind: .major)), "minor v offers a major V")

        // Every palette choice in every key: stacked by letter, the right sound, near the staff.
        for minor in [false, true] {
            for root in Note.allCases {
                var k = Composition()
                k.keyRoot = root
                k.isMinor = minor
                var symbols = (1...7).flatMap { CompositionChord.variants(degree: $0, keySignature: k.keySignature, isMinor: minor) }
                symbols += CompositionChord.borrowed(isMinor: minor).flatMap { [$0.chord, $0.seventh] }
                for base in symbols {
                    let maxInversion = k.chord(base).maxInversion
                    for inversion in 0...maxInversion {
                        var symbol = base
                        symbol.inversion = inversion
                        let chord = k.chord(symbol)
                        let p = chord.pitches
                        let label = "\(k.keyName) \(chord.romanNumeral) \(chord.name) \(p.map(\.name))"
                        check(p.count == (chord.kind.isSeventh ? 4 : 3), "\(label): note count")
                        check(p.allSatisfy { abs($0.accidental) <= 2 }, "\(label): accidentals")
                        check(zip(p, p.dropFirst()).allSatisfy { $0.midi < $1.midi }, "\(label): low to high")
                        check(p.allSatisfy { (-4...14).contains($0.staffPosition) }, "\(label): near the staff \(p.map(\.staffPosition))")
                        let rootPosition = k.chord(symbol.rootPosition).pitches
                        let semitones = rootPosition.dropFirst().map { $0.midi - rootPosition[0].midi }
                        check(chord.kind.intervals?.map(\.semitones) == semitones, "\(label): sound \(semitones)")
                        check(chord.bass.name == rootPosition[inversion].name, "\(label): bass")
                        check(abs(chord.root.accidental) <= 1, "\(label): root needs no double accidental")
                        check(Set(rootPosition.map { $0.note.rawValue }) == chord.pitchClasses, "\(label): inversion keeps the notes")
                    }
                }
            }
        }

        // Dragging a chord carries all of it; an old bare degree still works.
        let symbol = ChordSymbol(degree: 7, shift: -1, kind: .dominant7, inversion: 2)
        check(ChordSymbol(dragText: symbol.dragText) == symbol, "drag text round trip")
        check(ChordSymbol(dragText: "4") == ChordSymbol(degree: 4), "bare degree")
        check(ChordSymbol(dragText: "9") == nil && ChordSymbol(dragText: "nope") == nil, "bad drag text")
        print("ok   chord symbols")
    }

    // MARK: - Melody

    static func checkMelody() {
        var m = Composition()
        let e = SpelledPitch(letter: 2, octave: 4), g = SpelledPitch(letter: 4, octave: 4)
        check(m.placeNote(e, at: 0, value: .quarter) == .quarter, "quarter on beat 1")
        check(m.placeNote(g, at: 12, value: .eighth) == .eighth, "eighth on beat 2")
        check(m.placeNote(e, at: 18, value: .whole) == .half, "a whole note on the and of 2 is cut to a half (5 eighths left)")
        check(m.melodyRests(inMeasure: 0).isEmpty == false, "and an eighth rest fills the rest: \(m.melodyRests(inMeasure: 0))")
        let restEighths = m.melodyRests(inMeasure: 0).reduce(0) { $0 + $1.length }
        check(restEighths + m.melody.reduce(0) { $0 + $1.length } == 48, "measure adds up")
        check(m.melodyRests(inMeasure: 1) == [.init(start: 48, length: 48, glyph: .whole)], "empty measure: whole rest")
        var r = Composition()
        r.placeNote(e, at: 6, value: .eighth)
        check(r.melodyRests(inMeasure: 0) == [.init(start: 0, length: 6, glyph: .eighth), .init(start: 12, length: 12, glyph: .quarter),
                                              .init(start: 24, length: 24, glyph: .half)], "rests on the beat: \(r.melodyRests(inMeasure: 0))")
        check(m.placeNote(g, at: 6, value: .quarter) == .eighth && m.note(covering: 0)?.length == 6,
              "a note inside a ringing one cuts it short: \(m.melody)")
        check(m.placeNote(e, at: 64 * 6, value: .quarter) == nil, "out of range")
        m.isMinor = false
        check(m.isEmpty == false && m.hasMelody, "a melody makes it not empty")

        // Duplicating a measure copies chords and notes, adding a measure at the end.
        var d = Composition()
        d.setMeasureCount(2)
        d.place(1, at: 4, value: .half)
        d.placeNote(e, at: 54, value: .eighth)
        d.duplicateMeasure(1)
        check(d.measureCount == 3 && d.chords.map(\.start) == [4, 8] && d.melody.map(\.start) == [54, 102], "duplicate the last measure: \(d.chords) \(d.melody)")
        d.duplicateMeasure(0)
        check(d.isMeasureEmpty(1) && d.chords.map(\.start) == [8], "duplicating an empty measure clears the next")
        let most = Composition.measureRange.upperBound
        d.setMeasureCount(most)
        check(!d.canDuplicateMeasure(most - 1) && d.canDuplicateMeasure(most - 2), "no measure past the most")
        d.clearMeasure(2)
        check(d.isMeasureEmpty(2), "clear measure")

        // Every measure adds up in both lines, whatever the edits.
        var fuzz = Composition()
        let pitches = fuzz.scalePitches(octave: 3)
        var fuzzClip = fuzz.clip(0...0)
        func someMeasures() -> ClosedRange<Int> {
            let a = Int.random(in: 0..<fuzz.measureCount)
            return a...min(a + Int.random(in: 0...3), fuzz.measureCount - 1)
        }
        for step in 0..<6000 {
            let lastOp = Int.random(in: 0..<22)
            switch lastOp {
            case 0: fuzz.setBeatsPerMeasure(Composition.meters.randomElement()!)
            case 1: fuzz.setMeasureCount(Int.random(in: 1...33))
            case 2: fuzz.removeNote(covering: Int.random(in: 0..<fuzz.totalTicks))
            case 3: if let n = fuzz.melody.randomElement() { fuzz.setLength(ofNoteAt: n.start, to: NoteValue.allCases.randomElement()!) }
            case 4: fuzz.duplicateMeasure(Int.random(in: 0..<fuzz.measureCount))
            case 5: fuzz.clearMeasure(Int.random(in: 0..<fuzz.measureCount))
            case 12: fuzzClip = fuzz.clip(someMeasures())
            case 13: fuzz.paste(fuzzClip, at: Int.random(in: 0..<fuzz.measureCount))
            case 14: fuzz.repeatMeasures(someMeasures())
            case 15: fuzz.moveMeasures(someMeasures(), by: Bool.random() ? 1 : -1)
            case 16: fuzz.insertMeasure(at: Int.random(in: 0...fuzz.measureCount))
            case 17: fuzz.deleteMeasures(someMeasures())
            case 18: fuzz.setKey(root: Note.allCases.randomElement()!, isMinor: Bool.random())
            case 19: let a = Int.random(in: 0..<fuzz.totalTicks); fuzz.clearNotes(from: a, to: min(a + Int.random(in: 1...48), fuzz.totalTicks))
            case 20: let a = Int.random(in: 0..<fuzz.totalBeats); fuzz.clearChords(from: a, to: min(a + Int.random(in: 1...4), fuzz.totalBeats))
            case 6: fuzz.place(Int.random(in: 1...7), at: Int.random(in: 0..<fuzz.totalBeats), value: NoteValue.chordValues.randomElement()!)
            default: fuzz.placeNote(pitches.randomElement()!, at: Int.random(in: 0..<fuzz.totalTicks), value: NoteValue.allCases.randomElement()!)
            }
            var ok = zip(fuzz.melody, fuzz.melody.dropFirst()).allSatisfy { $0.end <= $1.start }
            ok = ok && Composition.measureRange.contains(fuzz.measureCount)
            ok = ok && zip(fuzz.chords, fuzz.chords.dropFirst()).allSatisfy { $0.end <= $1.start }
            ok = ok && fuzz.chords.allSatisfy { $0.end <= fuzz.totalBeats && $0.start / fuzz.beatsPerMeasure == ($0.end - 1) / fuzz.beatsPerMeasure }
            ok = ok && fuzz.melody.allSatisfy { abs($0.pitch.accidental) <= 2 }
            for n in fuzz.melody {
                ok = ok && NoteValue(ticks: n.length) != nil && n.end <= fuzz.totalTicks
                    && n.start / fuzz.ticksPerMeasure == (n.end - 1) / fuzz.ticksPerMeasure
            }
            for measure in 0..<fuzz.measureCount {
                let lo = measure * fuzz.ticksPerMeasure, hi = lo + fuzz.ticksPerMeasure
                let noteEighths = fuzz.melody.filter { $0.start >= lo && $0.start < hi }.reduce(0) { $0 + $1.length }
                let rests = fuzz.melodyRests(inMeasure: measure)
                ok = ok && noteEighths + rests.reduce(0) { $0 + $1.length } == fuzz.ticksPerMeasure
                ok = ok && rests.allSatisfy { $0.glyph == .whole || NoteValue(ticks: $0.length) == $0.glyph }
                // A beat is in halves and quarters, or in thirds: never both, and nothing rings across a triplet.
                for beat in stride(from: lo, to: hi, by: 12) {
                    let inBeat = fuzz.melody.filter { $0.start < beat + 12 && $0.end > beat }
                    if inBeat.contains(where: \.isTriplet) {
                        ok = ok && inBeat.allSatisfy { $0.isTriplet && $0.start >= beat && ($0.start - beat) % 4 == 0 }
                    } else {
                        ok = ok && inBeat.allSatisfy { $0.start % 3 == 0 && $0.length % 3 == 0 }
                    }
                }
                ok = ok && [1, 2, 3, 6].contains(fuzz.columnTicks(inMeasure: measure))
                let chordBeats = fuzz.chords.filter { $0.start >= lo / 12 && $0.start < hi / 12 }.reduce(0) { $0 + $1.beats }
                ok = ok && chordBeats + fuzz.rests(inMeasure: measure).reduce(0) { $0 + $1.beats } == fuzz.beatsPerMeasure
            }
            if !ok {
                var why: [String] = []
                if !zip(fuzz.melody, fuzz.melody.dropFirst()).allSatisfy({ $0.end <= $1.start }) { why.append("overlap") }
                for n in fuzz.melody where NoteValue(ticks: n.length) == nil || n.end > fuzz.totalTicks
                    || n.start / fuzz.ticksPerMeasure != (n.end - 1) / fuzz.ticksPerMeasure { why.append("note \(n.start):\(n.length)") }
                for measure in 0..<fuzz.measureCount {
                    let lo = measure * fuzz.ticksPerMeasure, hi = lo + fuzz.ticksPerMeasure
                    let notes = fuzz.melody.filter { $0.start >= lo && $0.start < hi }
                    let rests = fuzz.melodyRests(inMeasure: measure)
                    if notes.reduce(0, { $0 + $1.length }) + rests.reduce(0, { $0 + $1.length }) != fuzz.ticksPerMeasure
                        || !rests.allSatisfy({ $0.glyph == .whole || NoteValue(ticks: $0.length) == $0.glyph }) {
                        why.append("measure \(measure): notes \(notes.map { "\($0.start - lo):\($0.length)" }) rests \(rests.map { "\($0.start - lo):\($0.length)" })")
                    }
                }
                check(false, "melody step \(step), after \(lastOp): \(fuzz.meterName) \(why)"); break
            }
        }

        // Whole measures: copy, paste, repeat, move, insert, delete.
        var w = Composition()
        w.setMeasureCount(4)
        for measure in 0..<4 { w.place(measure + 1, at: measure * 4, value: .whole) }
        w.placeNote(e, at: 54, value: .quarter)
        func degrees(_ c: Composition) -> [Int] {
            (0..<c.measureCount).map { m in c.chords.first { $0.start == m * c.beatsPerMeasure }?.symbol.degree ?? 0 }
        }
        var w1 = w
        check(w1.repeatMeasures(1...2) && degrees(w1) == [1, 2, 3, 2, 3, 4] && w1.melody.map(\.start) == [54, 150], "repeat: \(degrees(w1)) \(w1.melody)")
        w1 = w
        check(w1.moveMeasures(1...2, by: 1) == 2...3 && degrees(w1) == [1, 4, 2, 3] && w1.melody.map(\.start) == [102], "move later: \(degrees(w1))")
        check(w1.moveMeasures(2...3, by: 1) == nil && w1.moveMeasures(0...0, by: -1) == nil, "can't move past the ends")
        check(w1.moveMeasures(2...3, by: -1) == 1...2 && w1 == w, "and back")
        w1 = w
        check(w1.insertMeasure(at: 1) && degrees(w1) == [1, 0, 2, 3, 4] && w1.melody.map(\.start) == [102], "insert: \(degrees(w1))")
        w1.deleteMeasures(1...1)
        check(w1 == w, "delete the inserted measure")
        w1.deleteMeasures(0...2)
        check(w1.measureCount == 2 && degrees(w1) == [4, 0], "a piece keeps two measures: \(degrees(w1))")
        w1 = w
        let copied = w.clip(0...1)
        check(w1.pasteOverwrites(copied, at: 2) && w1.paste(copied, at: 3) == 3...4 && degrees(w1) == [1, 2, 3, 1, 2]
              && w1.melody.map(\.start) == [54, 198], "paste past the end adds a measure: \(degrees(w1)) \(w1.melody)")
        var empty = Composition()
        check(!empty.pasteOverwrites(copied, at: 0) && empty.paste(copied, at: 0) == 0...1, "paste on empty measures")
        empty.setBeatsPerMeasure(3)
        check(!empty.canPaste(copied, at: 0) && empty.paste(copied, at: 0) == nil, "not into another meter")
        var full = Composition()
        full.setMeasureCount(most)
        full.place(1, at: 0, value: .whole)
        check(!full.repeatMeasures(0...0) && !full.insertMeasure(at: 0), "no room past the most measures")
        check(full.paste(w.clip(0...3), at: most - 2) == (most - 2)...(most - 1) && full.measureCount == most, "paste is cut at the end")

        // Rest: clears a span, cutting short what rings into it.
        var q = Composition()
        q.place(1, at: 0, value: .whole)
        q.clearChords(from: 2, to: 4)
        check(q.chords.map(\.beats) == [2], "a rest cuts a ringing chord short: \(q.chords)")
        q.placeNote(e, at: 0, value: .whole)
        q.clearNotes(from: 18, to: 30)
        check(q.melody.map(\.length) == [18], "and a ringing note: \(q.melody)")

        // Changing the key moves the melody with the chords, each note keeping its scale degree.
        func names(_ c: Composition) -> String { c.melody.map { "\($0.pitch.name)\($0.pitch.octave)" }.joined(separator: " ") }
        var t = Composition()
        for (i, pitch) in [SpelledPitch(letter: 0, octave: 4), SpelledPitch(letter: 2, octave: 4), SpelledPitch(letter: 4, octave: 4),
                           SpelledPitch(letter: 3, accidental: 1, octave: 4), SpelledPitch(letter: 6, accidental: -1, octave: 3)].enumerated() {
            t.placeNote(pitch, at: i * 6, value: .eighth)
        }
        let inC = t
        t.setKey(root: .g, isMinor: false)
        check(names(t) == "G3 B3 D4 C♯4 F3", "C to G goes down a fourth: \(names(t))")
        t.setKey(root: .d, isMinor: false)
        check(Set(t.melody.map { $0.pitch.midi - t.melody[0].pitch.midi }) == Set(inC.melody.map { $0.pitch.midi - inC.melody[0].pitch.midi }),
              "G to D keeps the tune: \(names(t))")
        t.setKey(root: .c, isMinor: false)
        check(names(t) == names(inC), "and back to C, where it started: \(names(t))")
        t.setKey(root: .c, isMinor: true)
        check(names(t) == "C4 E♭4 G4 F♯4 B♭3", "to C minor, the 3rd follows the key and the rest stay: \(names(t))")
        for _ in 0..<200 {
            var round = inC
            let keys = (0..<4).map { _ in (Note.allCases.randomElement()!, Bool.random()) }
            for key in keys { round.setKey(root: key.0, isMinor: false) }
            round.setKey(root: .c, isMinor: false)
            if names(round) != names(inC) { check(false, "round the keys and back: \(keys) \(names(round))"); break }
        }
        t = inC
        t.setKey(root: .dSharp, isMinor: false)
        check(names(t) == "E♭3 G3 B♭3 A3 D♭3" || names(t) == "E♭4 G4 B♭4 A4 D♭4", "to E♭: \(names(t))")
        var low = Composition()
        low.placeNote(SpelledPitch(letter: 2, octave: 2), at: 0, value: .quarter)    // low E
        low.setKey(root: .b, isMinor: false)
        check(low.melody.allSatisfy { $0.pitch.midi >= 40 }, "kept on the guitar: \(names(low))")
        hearing()

        var tempo = Composition()
        tempo.place(1, at: 0, value: .whole)
        tempo.tempo = 132
        check((try? JSONDecoder().decode(Composition.self, from: JSONEncoder().encode(tempo)))?.tempo == 132, "tempo is saved")

        // Saving: chords with kinds and a melody round-trip; chords saved as bare degrees load.
        var s = Composition()
        s.place(ChordSymbol(degree: 5, kind: .dominant7, secondary: 2, inversion: 1), at: 0, value: .half)
        s.place(ChordSymbol(degree: 7, shift: -1, kind: .major), at: 2, value: .half)
        s.placeNote(SpelledPitch(letter: 3, accidental: 1, octave: 4), at: 18, value: .dottedQuarter)
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        let data = try! encoder.encode(s)
        check(try! decoder.decode(Composition.self, from: data) == s, "chord kinds and melody save and load")
        let bare = """
        {"id":"\(UUID().uuidString)","name":"Before kinds","keyRoot":0,"isMinor":false,"measureCount":2,"beatsPerMeasure":4,
         "chords":[{"start":0,"beats":4,"degree":4},{"start":4,"beats":2,"degree":5}],"updatedAt":0}
        """
        let loaded = try! decoder.decode(Composition.self, from: Data(bare.utf8))
        check(loaded.chords.map(\.symbol) == [ChordSymbol(degree: 4), ChordSymbol(degree: 5)] && !loaded.hasMelody, "chords saved as degrees")
        // An older version of the app reads what this one saves (its chords as plain degrees).
        struct OldChord: Decodable { let start: Int; let beats: Int; let degree: Int }
        struct OldComposition: Decodable { let chords: [OldChord]; let measureCount: Int }
        let old = try? decoder.decode(OldComposition.self, from: data)
        check(old?.chords.map(\.degree) == [5, 7], "an older app reads the chords: \(String(describing: old?.chords.map(\.degree)))")
        rhythms()
        files()
        examples()
        print("ok   melody")
    }

    /// Every example is built as it's written: nothing shortened, dropped or out of range.
    static func examples() {
        let all = CompositionExample.all
        check(CompositionExample.problems.isEmpty, "examples: \(CompositionExample.problems)")
        check(all.count == 25 && Set(all.map(\.id)).count == all.count, "\(all.count) examples, each with its own id")
        check(CompositionExample.Level.allCases.allSatisfy { level in all.filter { $0.level == level }.count >= 4 }, "every level has examples")
        for example in all {
            let c = example.composition
            check(!c.chords.isEmpty && c.tempo != nil && !example.detail.isEmpty && !example.numerals.isEmpty, "\(example.id): chords, tempo, detail")
            check(c.melody.allSatisfy { (40...84).contains($0.pitch.midi) && c.tabPosition(of: $0) != nil }, "\(example.id): on the guitar")
            // Every measure with a melody is full of it (the notation says so), and chords fill their measures or leave them empty.
            for measure in 0..<c.measureCount {
                let chordBeats = c.chords.filter { $0.start / c.beatsPerMeasure == measure }.reduce(0) { $0 + $1.beats }
                check(chordBeats == 0 || chordBeats == c.beatsPerMeasure, "\(example.id): chords fill measure \(measure + 1)")
            }
            // It survives saving, and being sent as a file.
            let saved = try? JSONDecoder().decode(Composition.self, from: JSONEncoder().encode(c))
            check(saved == c, "\(example.id): saves and loads")
            // Every chord can be heard by Play Along's listener as one of the chords on offer, or is at least spelled.
            check(c.chords.allSatisfy { c.chord($0.symbol).pitches.count >= 3 }, "\(example.id): chords spell")
        }
        func find(_ id: String) -> Composition { all.first { $0.id == id }!.composition }
        check(find("rhythm-workout").melody.filter(\.isTriplet).count == 9 && find("rhythm-workout").melody.filter { find("rhythm-workout").tiesForward($0) }.count == 2,
              "the workout has its triplets and ties")
        check(find("greensleeves").melody.filter { find("greensleeves").tiesForward($0) }.count == 1 && find("greensleeves").measureCount == 17, "Greensleeves ends on a tie")
        check(find("walking-bass").chords.map { find("walking-bass").chord($0.symbol).name } == ["C", "G/B", "Am", "C/G", "F", "C/E", "Dm7", "G7"],
              "the bass walks: \(find("walking-bass").chords.map { find("walking-bass").chord($0.symbol).name })")
        check(find("rising-sun").chords.map { find("rising-sun").chord($0.symbol).name }.prefix(8) == ["Am", "C", "D", "F", "Am", "C", "E", "E"],
              "Rising Sun: \(find("rising-sun").chords.map { find("rising-sun").chord($0.symbol).name })")
        check(find("circle-minor").chords.map { find("circle-minor").chord($0.symbol).name } == ["Dm7", "G7", "Cmaj7", "Fmaj7", "Bø7", "E7", "Am", "Am"],
              "circle of fifths: \(find("circle-minor").chords.map { find("circle-minor").chord($0.symbol).name })")
        check(find("borrowed").chords.map { find("borrowed").chord($0.symbol).name } == ["C", "B♭", "F", "Fm", "C", "A♭", "B♭", "C"],
              "borrowed: \(find("borrowed").chords.map { find("borrowed").chord($0.symbol).name })")
        check(find("turnaround").chords.map { find("turnaround").chord($0.symbol).name } == ["Cmaj7", "A7", "Dm7", "G7", "Em7", "A7", "Dm7", "G7"],
              "turnaround: \(find("turnaround").chords.map { find("turnaround").chord($0.symbol).name })")
        // The notation turns away what doesn't add up or fit.
        var bad = Composition()
        check(bad.write(melody: "C4q C4q C4q") != nil && bad.write(melody: "C4q C4q C4q C4q C4q") != nil && bad.write(melody: "H4q rq rh") != nil
              && bad.write(melody: "C4t rq rh") != nil && bad.write(melody: "C4q~ D4q rh") != nil && bad.write(melody: "rw | rw | rw | rw | rw") != nil
              && bad.write(melody: "C4t D4t E4t rq rh") == nil, "melody notation checks itself")
    }

    /// A composition sent as a file comes back as the same music, as a new composition; anything
    /// else is turned away.
    static func files() {
        var c = Composition()
        c.name = "  My Song\nwith a line break  "
        c.setKey(root: .dSharp, isMinor: false)
        c.setMeasureCount(3)
        c.place(ChordSymbol(degree: 5, kind: .dominant7), at: 0, value: .whole)
        c.toggleTie(ofChordAt: 0)
        c.placeNote(SpelledPitch(letter: 2, accidental: -1, octave: 4), at: 0, value: .sixteenth, string: 1)
        c.placeNote(SpelledPitch(letter: 4, octave: 4), at: 12, value: .tripletEighth)
        c.tempo = 132
        let data = CompositionFile.data(for: c)!
        guard case .success(let back) = CompositionFile.composition(from: data) else { return check(false, "a composition file reads back") }
        check(back.id != c.id && back.name == "My Song with a line break", "it comes in as a new composition, its name tidied: \(back.name)")
        var same = back
        same.id = c.id; same.name = c.name; same.updatedAt = c.updatedAt
        check(same == c, "and the same music")
        func read(_ text: String) -> CompositionFile.ReadError? {
            if case .failure(let error) = CompositionFile.composition(from: Data(text.utf8)) { return error }
            return nil
        }
        check(read("hello") == .notAComposition && read("{}") == .notAComposition
              && read(#"{"format":"something.else","version":1,"composition":{}}"#) == .notAComposition
              && read(#"{"format":"guitarman.composition","version":1,"composition":{"name":3}}"#) == .notAComposition, "other files are turned away")
        check(read(#"{"format":"guitarman.composition","version":99,"composition":{}}"#) == .newerVersion, "a newer version says so")
        check(CompositionFile.composition(from: Data(count: CompositionFile.maxBytes + 1)) == .failure(.tooBig), "too big")
        // A file that's been tampered with can't bring in music that breaks the rules.
        let bad = String(data: data, encoding: .utf8)!
            .replacingOccurrences(of: "\"measureCount\":3", with: "\"measureCount\":9000")
            .replacingOccurrences(of: "\"beats\":4", with: "\"beats\":400")
            .replacingOccurrences(of: "\"tempo\":132", with: "\"tempo\":100000")
        if case .success(let tamed) = CompositionFile.composition(from: Data(bad.utf8)) {
            check(tamed.measureCount == Composition.measureRange.upperBound && tamed.chords.allSatisfy { $0.beats <= 4 } && tamed.tempo == 200,
                  "out-of-range values are brought back in: \(tamed.measureCount) \(tamed.chords.map(\.beats)) \(String(describing: tamed.tempo))")
        } else {
            check(false, "a tampered file still reads, tamed")
        }
        check(CompositionFile.tidied("   ") == "Untitled" && CompositionFile.tidied(String(repeating: "a", count: 200)).count == CompositionFile.maxNameLength
              && CompositionFile.fileName(for: "AC/DC: live?") == "AC-DC- live-", "names: \(CompositionFile.fileName(for: "AC/DC: live?"))")
    }

    /// Sixteenths, triplets, ties, and what an older version of the app is left with.
    static func rhythms() {
        let e = SpelledPitch(letter: 2, octave: 4), g = SpelledPitch(letter: 4, octave: 4)
        func shape(_ c: Composition) -> [String] { c.melody.map { "\($0.start):\($0.length)" } }
        func restShape(_ c: Composition, _ measure: Int = 0) -> [String] { c.melodyRests(inMeasure: measure).map { "\($0.start):\($0.glyph.rawValue)" } }

        // Sixteenths sit on any quarter of a beat; the gaps are sixteenth and eighth rests.
        var x = Composition()
        check(x.placeNote(e, at: 0, value: .sixteenth) == .sixteenth && x.placeNote(g, at: 3, value: .sixteenth) == .sixteenth
              && x.placeNote(e, at: 9, value: .dottedEighth) == .dottedEighth, "sixteenths and a dotted eighth: \(shape(x))")
        check(shape(x) == ["0:3", "3:3", "9:9"] && restShape(x) == ["6:sixteenth", "18:eighth", "24:half"], "sixteenth rests: \(restShape(x))")
        check(x.columnTicks(inMeasure: 0) == 3 && x.columnTicks(inMeasure: 1) == 6, "a measure with sixteenths is laid out in sixteenths")
        check(x.placeNote(e, at: 13, value: .dottedEighth) == .dottedEighth && x.melody.last?.start == 12, "a dotted eighth, snapped to the sixteenth")
        check(x.snapped(17, for: .eighth) == 15 && x.snapped(17, for: .tripletEighth) == 16 && x.snapped(23, for: .tripletEighth) == 20, "snapping")

        // A triplet takes its beat: three to the beat, plain notes in the beat go, rests are triplet rests.
        var t = Composition()
        t.placeNote(e, at: 0, value: .half)
        t.placeNote(g, at: 30, value: .eighth)
        check(t.placeNote(g, at: 12, value: .tripletEighth) == .tripletEighth && shape(t) == ["0:12", "12:4", "30:6"],
              "a triplet cuts the half note at its beat: \(shape(t))")
        t.placeNote(e, at: 20, value: .tripletEighth)
        check(shape(t) == ["0:12", "12:4", "20:4", "30:6"] && restShape(t) == ["16:tripletEighth", "24:eighth", "36:quarter"], "triplet rest in the gap: \(restShape(t))")
        check(t.isTripletBeat(at: 14) && !t.isTripletBeat(at: 0) && t.columnTicks(inMeasure: 0) == 2, "its beat is in three")
        check(t.placeNote(g, at: 26, value: .tripletEighth) == .tripletEighth && shape(t) == ["0:12", "12:4", "20:4", "24:4"],
              "a triplet replaces the plain notes in its beat: \(shape(t))")
        var plain = t
        check(plain.placeNote(e, at: 16, value: .half) == .quarter && shape(plain) == ["0:12", "12:12", "24:4"],
              "a plain note replaces a beat's triplets, and stops at the next triplet beat: \(shape(plain))")
        var longNote = t
        check(longNote.placeNote(e, at: 0, value: .whole) == .quarter, "a long note stops where triplets start")
        t.setLength(ofNoteAt: 12, to: .quarter)
        check(t.melody[1].length == 4, "a triplet keeps its length")
        t.clearNotes(from: 12, to: 24)
        check(!t.isTripletBeat(at: 12) && restShape(t) == ["12:quarter", "28:tripletEighth", "32:tripletEighth", "36:quarter"], "with its triplets gone the beat is plain again: \(restShape(t))")
        var both = Composition()
        both.placeNote(e, at: 0, value: .sixteenth)
        both.placeNote(e, at: 12, value: .tripletEighth)
        check(both.columnTicks(inMeasure: 0) == 1, "sixteenths and triplets in one measure")
        var waltz = both
        waltz.placeNote(e, at: 36, value: .tripletEighth)
        waltz.setBeatsPerMeasure(3)
        check(shape(waltz) == ["0:3", "12:4"], "to 3/4: \(shape(waltz))")

        // Ties: to the same note or chord right after, made if there's nothing there; across a barline too.
        var tie = Composition()
        tie.placeNote(e, at: 36, value: .quarter)
        check(tie.toggleTie(ofNoteAt: 36) && shape(tie) == ["36:12", "48:12"] && tie.tiesForward(tie.melody[0]) && tie.isTiedOver(tie.melody[1]),
              "a tie over the barline writes the note it's tied to: \(shape(tie))")
        check(tie.soundingTicks(of: tie.melody[0]) == 24 && tie.struckMelody.map(\.start) == [36], "tied notes sound as one")
        tie.placeNote(g, at: 60, value: .quarter)
        check(!tie.toggleTie(ofNoteAt: 48) && !tie.tiesForward(tie.melody[1]), "no tie to a different note")
        tie.setPitch(ofNoteAt: 48, to: g)
        check(!tie.tiesForward(tie.melody[0]) && tie.struckMelody.count == 3, "changing the second note breaks the tie")
        check(tie.toggleTie(ofNoteAt: 48) && tie.tiesForward(tie.melody[1]) && tie.toggleTie(ofNoteAt: 48) && !tie.tiesForward(tie.melody[1]), "tie the next two, and untie")
        tie.place(5, at: 4, value: .whole)
        check(tie.toggleTie(ofChordAt: 4) && tie.measureCount == 4 + 0 && tie.chords.map { "\($0.start):\($0.beats)" } == ["4:4", "8:4"]
              && tie.soundingBeats(of: tie.chords[0]) == 8 && tie.struckChords.count == 1, "a chord tied into the next measure: \(tie.chords)")
        var last = Composition()
        last.setMeasureCount(2)
        last.place(1, at: 4, value: .whole)
        check(last.toggleTie(ofChordAt: 4) && last.measureCount == 3, "at the end, a tie adds a measure")
        let saved = try! JSONEncoder().encode(tie)
        let back = try! JSONDecoder().decode(Composition.self, from: saved)
        check(back == tie && back.tiesForward(back.chords[0]), "ties are saved")
        var moved = tie
        moved.insertMeasure(at: 0)
        check(moved.tiesForward(moved.chords[0]), "ties move with their measures")

        // Saving: the new rhythms round-trip; an older version reads what's on its eighths.
        var mixed = Composition()
        mixed.placeNote(e, at: 0, value: .sixteenth)
        mixed.placeNote(g, at: 3, value: .sixteenth)
        mixed.placeNote(e, at: 6, value: .eighth)
        mixed.placeNote(g, at: 12, value: .tripletEighth)
        mixed.placeNote(e, at: 16, value: .tripletEighth)
        mixed.placeNote(g, at: 24, value: .dottedQuarter)
        let data = try! JSONEncoder().encode(mixed)
        check(try! JSONDecoder().decode(Composition.self, from: data) == mixed, "sixteenths and triplets save and load")
        struct OldNote: Decodable { let start: Int; let length: Int }
        struct OldComposition: Decodable { let melody: [OldNote] }
        let old = try? JSONDecoder().decode(OldComposition.self, from: data)
        check(old?.melody.map { "\($0.start):\($0.length)" } == ["0:1", "1:1", "2:1", "4:3"], "an older app reads the melody on its eighths: \(String(describing: old?.melody.map { "\($0.start):\($0.length)" }))")
        let before = """
        {"id":"\(UUID().uuidString)","name":"In eighths","keyRoot":0,"isMinor":false,"measureCount":2,"beatsPerMeasure":4,"chords":[],
         "melody":[{"start":1,"length":3,"pitch":{"letter":2,"accidental":0,"octave":4}},{"start":9,"length":1,"pitch":{"letter":4,"accidental":0,"octave":4}}],"updatedAt":0}
        """
        let loaded = try! JSONDecoder().decode(Composition.self, from: Data(before.utf8))
        check(shape(loaded) == ["6:18", "54:6"], "a melody saved in eighths loads as the same music: \(shape(loaded))")
    }

    // MARK: - Accidentals

    static func checkAccidentals() {
        let fSharp = SpelledPitch(letter: 3, accidental: 1, octave: 4), f = SpelledPitch(letter: 3, octave: 4)
        var c = MeasureAccidentals(keySignature: .cMajor)
        check(c.printed(for: fSharp) == 1, "F♯ in C: sharp")
        check(c.printed(for: fSharp) == nil, "F♯ again: no sign")
        check(c.printed(for: f) == 0, "back to F: natural")
        check(c.printed(for: SpelledPitch(letter: 3, accidental: 1, octave: 5)) == 1, "F♯ an octave up still needs its sharp")
        var g = MeasureAccidentals(keySignature: KeySignature(fifths: 1))
        check(g.printed(for: fSharp) == nil && g.printed(for: f) == 0 && g.printed(for: fSharp) == 1, "in G: F♯, F♮, F♯")
        // A chord's notes sound together: B♭ D F then G B D in C prints the natural on B.
        var chords = MeasureAccidentals(keySignature: .cMajor)
        let bFlat = SpelledPitch(letter: 6, accidental: -1, octave: 3), b = SpelledPitch(letter: 6, octave: 3)
        check(chords.printed(for: [bFlat, SpelledPitch(letter: 1, octave: 4), SpelledPitch(letter: 3, octave: 4)]) == [-1, nil, nil], "B♭ chord")
        check(chords.printed(for: [SpelledPitch(letter: 4, octave: 3), b, SpelledPitch(letter: 1, octave: 4)]) == [nil, 0, nil], "then G: B♮")
        print("ok   accidentals")
    }

    // MARK: - Templates

    static func checkTemplates() {
        for template in CompositionTemplate.all {
            let c = template.makeComposition()
            check(c.measureCount == template.measures.count && c.beatsPerMeasure == template.beatsPerMeasure, "\(template.name): size")
            check((0..<c.measureCount).allSatisfy { c.rests(inMeasure: $0).isEmpty }, "\(template.name): every measure full")
            check(c.chords.count == template.measures.reduce(0) { $0 + $1.count }, "\(template.name): every chord placed")
            check(!template.numerals.isEmpty, "\(template.name): numerals")
        }
        let blues = CompositionTemplate.all.first { $0.id == "blues" }!
        check(blues.makeComposition().measureCount == 12 && blues.numerals.hasPrefix("I7 – IV7"), "blues: \(blues.numerals)")
        print("ok   templates: " + CompositionTemplate.all.map { "\($0.name) (\($0.numerals))" }.joined(separator: "; "))
    }
}
