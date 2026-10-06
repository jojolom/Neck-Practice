//
//  chord-check.swift
//
//  Offline check for Composition: ChordAnalyzer hears synthetic guitar strums (harmonics,
//  decay, detuning, noise, and a weak low fundamental like a phone mic gives) as the chord
//  that was played and not as its near neighbours (C vs Am, D vs Dm); and the Composition
//  model names chords in the key (IV in E♭ is A♭) and keeps chords in place when reshaped.
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

        // Slots: 4 measures of whole notes = 4 slots; reshape keeps chords where they fall in time.
        var r = Composition()
        check(r.slotCount == 4 && r.slots.count == 4, "default slots")
        r.slots = [1, 4, 5, 1]
        r.reshape(measureCount: 4, noteValue: .quarter)
        check(r.slots.count == 16 && r.slots[0] == 1 && r.slots[4] == 4 && r.slots[8] == 5 && r.slots[12] == 1
              && r.slots.compactMap { $0 }.count == 4, "whole → quarter keeps each chord on its downbeat")
        r.slots[2] = 6
        r.reshape(measureCount: 4, noteValue: .half)
        check(r.slots == [1, 6, 4, nil, 5, nil, 1, nil], "quarter → half: \(r.slots)")
        r.reshape(measureCount: 2, noteValue: .half)
        check(r.slots == [1, 6, 4, nil], "fewer measures drops the end: \(r.slots)")
        r.reshape(measureCount: 3, noteValue: .dottedHalf)
        check(r.beatsPerMeasure == 3 && r.slots == [1, 4, nil], "dotted half is 3/4, one chord a bar: \(r.slots)")
        r.reshape(measureCount: 1, noteValue: .whole)
        check(r.measureCount == 2, "at least 2 measures")
        print("ok   composition")
    }
}
