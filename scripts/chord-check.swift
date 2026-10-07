//
//  chord-check.swift
//
//  Offline check for Composition: ChordAnalyzer hears synthetic guitar strums (harmonics,
//  decay, detuning, noise, and a weak low fundamental like a phone mic gives) as the chord
//  that was played and not as its near neighbours (C vs Am, D vs Dm); the Play Along level
//  bars stay in range, low for room noise, and glide rather than jump; and the Composition
//  model names chords in the key (IV in E♭ is A♭), keeps every measure adding up (chords of
//  their own lengths, shortened to fit, rests in the gaps), and loads compositions saved before.
//
//  Run from the repo root:
//    swiftc -O -parse-as-library -o /tmp/chord-check "Guitar Man/NeckPracticeModelsNote.swift" "Guitar Man/NeckPracticeModelsNotation.swift" "Guitar Man/NeckPracticeModelsRomanNumeral.swift" "Guitar Man/NeckPracticeModelsComposition.swift" "Guitar Man/NeckPracticeServicesChordAnalyzer.swift" scripts/chord-check.swift && /tmp/chord-check
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
        checkDisplayLevels()
        checkComposition()
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
        check(m.chords.map(\.start) == [0, 3, 6] && m.chords.map(\.beats) == [3, 1, 2] && m.chords.map(\.degree) == [1, 4, 6],
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
}
