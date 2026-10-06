//
//  ChordAnalyzer.swift
//  Guitar Man
//
//  Pure chord analysis (no AVFoundation): how much of a strum's sound falls on each of the 12
//  pitch classes (a chroma vector), and a forgiving check of whether that's a given triad — the
//  "did you play the right chord?" for Composition play-along. It isn't a transcriber: it only
//  asks "is it this chord?", so a buzzed string or a slightly out-of-tune guitar still counts.
//  Kept separate from ChordListener so it can be checked offline — see scripts/chord-check.swift.
//

import Foundation

enum ChordAnalyzer {

    /// Samples averaged into one before analysis (a crude low-pass + 4× downsample): guitar
    /// fundamentals and the harmonics that matter sit well under 6 kHz.
    static let decimation = 4
    /// Downsampled samples analyzed: ~340 ms at 48 kHz, long enough to separate low-E semitones.
    static let windowSize = 4096
    /// MIDI pitches measured: low E (E2) to E6.
    static let pitchRange = 40...88

    /// Share of the sound on each pitch class (C = 0 … B = 11), summing to 1; all zeros for silence.
    /// `samples` is raw input at `sampleRate`; the most recent `windowSize × decimation` are used.
    static func chroma(samples: [Float], sampleRate: Double) -> [Double] {
        var chroma = [Double](repeating: 0, count: 12)
        let needed = windowSize * decimation
        let recent = samples.count > needed ? Array(samples.suffix(needed)) : samples
        let n = recent.count / decimation
        guard n >= 256, sampleRate > 0 else { return chroma }

        // Downsample, then a Hann window so energy doesn't leak into neighbouring semitones.
        var x = [Double](repeating: 0, count: n)
        for i in 0..<n {
            var sum: Float = 0
            for j in 0..<decimation { sum += recent[i * decimation + j] }
            let hann = 0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(n - 1))
            x[i] = Double(sum) / Double(decimation) * hann
        }
        let rate = sampleRate / Double(decimation)

        // Goertzel: the strength of each exact pitch, folded onto its pitch class.
        for midi in pitchRange {
            let frequency = 440 * pow(2, Double(midi - 69) / 12)
            let coefficient = 2 * cos(2 * Double.pi * frequency / rate)
            var s1 = 0.0, s2 = 0.0
            for value in x {
                let s0 = value + coefficient * s1 - s2
                s2 = s1
                s1 = s0
            }
            let power = s1 * s1 + s2 * s2 - coefficient * s1 * s2
            // Magnitude rather than power, so one loud string doesn't drown out the rest.
            chroma[midi % 12] += max(power, 0).squareRoot()
        }

        let total = chroma.reduce(0, +)
        guard total > 0 else { return chroma }
        return chroma.map { $0 / total }
    }

    /// Whether `chroma` sounds like the chord made of `pitchClasses`: at least half the sound is
    /// on chord notes, and every chord note is clearly present (a quarter of the loudest one).
    /// That's what tells C (C E G) from Am (A C E): an A minor strum has a strong A, a C doesn't.
    static func matches(chroma: [Double], pitchClasses: Set<Int>) -> Bool {
        guard chroma.count == 12, let peak = chroma.max(), peak > 0, !pitchClasses.isEmpty else { return false }
        let inChord = pitchClasses.reduce(0.0) { $0 + chroma[(($1 % 12) + 12) % 12] }
        let everyNote = pitchClasses.allSatisfy { chroma[(($0 % 12) + 12) % 12] >= 0.25 * peak }
        return inChord >= 0.5 && everyNote
    }
}
