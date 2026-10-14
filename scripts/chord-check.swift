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
//    swiftc -O -parse-as-library -o /tmp/chord-check "Guitar Man/NeckPracticeModelsNote.swift" "Guitar Man/NeckPracticeModelsNotation.swift" "Guitar Man/NeckPracticeModelsRomanNumeral.swift" "Guitar Man/NeckPracticeModelsChord.swift" "Guitar Man/NeckPracticeModelsComposition.swift" "Guitar Man/NeckPracticeModelsCompositionTemplates.swift" "Guitar Man/NeckPracticeServicesChordAnalyzer.swift" scripts/chord-check.swift && /tmp/chord-check
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
        check(m.placeNote(g, at: 2, value: .eighth) == .eighth, "eighth on beat 2")
        check(m.placeNote(e, at: 3, value: .whole) == .half, "a whole note on the and of 2 is cut to a half (5 eighths left)")
        check(m.melodyRests(inMeasure: 0).isEmpty == false, "and an eighth rest fills the rest: \(m.melodyRests(inMeasure: 0))")
        let restEighths = m.melodyRests(inMeasure: 0).reduce(0) { $0 + $1.length }
        check(restEighths + m.melody.reduce(0) { $0 + $1.length } == 8, "measure adds up")
        check(m.melodyRests(inMeasure: 1) == [.init(start: 8, length: 8, glyph: .whole)], "empty measure: whole rest")
        var r = Composition()
        r.placeNote(e, at: 1, value: .eighth)
        check(r.melodyRests(inMeasure: 0) == [.init(start: 0, length: 1, glyph: .eighth), .init(start: 2, length: 2, glyph: .quarter),
                                              .init(start: 4, length: 4, glyph: .half)], "rests on the beat: \(r.melodyRests(inMeasure: 0))")
        check(m.placeNote(g, at: 1, value: .quarter) == .eighth && m.note(covering: 0)?.length == 1,
              "a note inside a ringing one cuts it short: \(m.melody)")
        check(m.placeNote(e, at: 64, value: .quarter) == nil, "out of range")
        m.isMinor = false
        check(m.isEmpty == false && m.hasMelody, "a melody makes it not empty")

        // Duplicating a measure copies chords and notes, adding a measure at the end.
        var d = Composition()
        d.setMeasureCount(2)
        d.place(1, at: 4, value: .half)
        d.placeNote(e, at: 9, value: .eighth)
        d.duplicateMeasure(1)
        check(d.measureCount == 3 && d.chords.map(\.start) == [4, 8] && d.melody.map(\.start) == [9, 17], "duplicate the last measure: \(d.chords) \(d.melody)")
        d.duplicateMeasure(0)
        check(d.isMeasureEmpty(1) && d.chords.map(\.start) == [8], "duplicating an empty measure clears the next")
        d.setMeasureCount(16)
        check(!d.canDuplicateMeasure(15) && d.canDuplicateMeasure(14), "no 17th measure")
        d.clearMeasure(2)
        check(d.isMeasureEmpty(2), "clear measure")

        // Every measure adds up in both lines, whatever the edits.
        var fuzz = Composition()
        let pitches = fuzz.scalePitches(octave: 3)
        for step in 0..<3000 {
            switch Int.random(in: 0..<12) {
            case 0: fuzz.setBeatsPerMeasure(Composition.meters.randomElement()!)
            case 1: fuzz.setMeasureCount(Int.random(in: 1...17))
            case 2: fuzz.removeNote(covering: Int.random(in: 0..<fuzz.totalEighths))
            case 3: if let n = fuzz.melody.randomElement() { fuzz.setLength(ofNoteAt: n.start, to: NoteValue.allCases.randomElement()!) }
            case 4: fuzz.duplicateMeasure(Int.random(in: 0..<fuzz.measureCount))
            case 5: fuzz.clearMeasure(Int.random(in: 0..<fuzz.measureCount))
            case 6: fuzz.place(Int.random(in: 1...7), at: Int.random(in: 0..<fuzz.totalBeats), value: NoteValue.chordValues.randomElement()!)
            default: fuzz.placeNote(pitches.randomElement()!, at: Int.random(in: 0..<fuzz.totalEighths), value: NoteValue.allCases.randomElement()!)
            }
            var ok = zip(fuzz.melody, fuzz.melody.dropFirst()).allSatisfy { $0.end <= $1.start }
            for n in fuzz.melody {
                ok = ok && NoteValue(eighths: n.length) != nil && n.end <= fuzz.totalEighths
                    && n.start / fuzz.eighthsPerMeasure == (n.end - 1) / fuzz.eighthsPerMeasure
            }
            for measure in 0..<fuzz.measureCount {
                let lo = measure * fuzz.eighthsPerMeasure, hi = lo + fuzz.eighthsPerMeasure
                let noteEighths = fuzz.melody.filter { $0.start >= lo && $0.start < hi }.reduce(0) { $0 + $1.length }
                let rests = fuzz.melodyRests(inMeasure: measure)
                ok = ok && noteEighths + rests.reduce(0) { $0 + $1.length } == fuzz.eighthsPerMeasure
                ok = ok && rests.allSatisfy { $0.glyph == .whole || NoteValue(eighths: $0.length) == $0.glyph }
                let chordBeats = fuzz.chords.filter { $0.start >= lo / 2 && $0.start < hi / 2 }.reduce(0) { $0 + $1.beats }
                ok = ok && chordBeats + fuzz.rests(inMeasure: measure).reduce(0) { $0 + $1.beats } == fuzz.beatsPerMeasure
            }
            if !ok { check(false, "melody step \(step): \(fuzz.meterName) \(fuzz.melody)"); break }
        }

        // Saving: chords with kinds and a melody round-trip; chords saved as bare degrees load.
        var s = Composition()
        s.place(ChordSymbol(degree: 5, kind: .dominant7, secondary: 2, inversion: 1), at: 0, value: .half)
        s.place(ChordSymbol(degree: 7, shift: -1, kind: .major), at: 2, value: .half)
        s.placeNote(SpelledPitch(letter: 3, accidental: 1, octave: 4), at: 3, value: .dottedQuarter)
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
        print("ok   melody")
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
