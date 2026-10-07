//
//  sampler-check.swift
//
//  Offline check for the recorded guitar AudioPlayer plays (GuitarSampleBank + SampledNote),
//  using the files in Guitar Man/GuitarSamples: every recording decodes; every note from low E
//  (E2) to E6 plays in tune at 44.1 and 48 kHz, including the ones borrowed from a neighbouring
//  recording (pitch as the ear hears it, from the first four harmonics, and up to B4 also as the
//  app's own tuner reads it); each note's pluck lands within 2 ms of its scheduled frame (no
//  leading silence or codec delay); notes are evenly loud; notes up to C5 still ring after 3 s
//  (long chords aren't cut off) and every ring-out is smooth (no loop pulsing or clicks); fades
//  end in silence; a cancelled note is silent.
//
//  Run from the repo root:
//    swiftc -O -parse-as-library -o /tmp/sampler-check "Guitar Man/NeckPracticeServicesPluckedString.swift" "Guitar Man/NeckPracticeServicesGuitarSamples.swift" "Guitar Man/NeckPracticeServicesPitchAnalyzer.swift" scripts/sampler-check.swift && /tmp/sampler-check
//

import Foundation

@main
struct SamplerCheck {

    static var failures = 0

    static func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition {
            print("FAIL", message())
            failures += 1
        }
    }

    static func main() {
        guard let bank = GuitarSampleBank.load(from: URL(fileURLWithPath: "Guitar Man/GuitarSamples")) else {
            print("FAIL could not load Guitar Man/GuitarSamples")
            exit(1)
        }
        check(bank.recordings.count >= 40, "only \(bank.recordings.count) recordings")
        print("ok   loaded \(bank.recordings.count) recordings")
        checkTuning(bank)
        checkTiming(bank)
        checkLevels(bank)
        checkSustain(bank)
        checkRelease(bank)
        print(failures == 0 ? "All sampler checks passed." : "\(failures) failure(s).")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Helpers

    static func render(_ bank: GuitarSampleBank, midi: Int, rate: Double, seconds: Double,
                       startFrame: Int64 = 0, releaseFrame: Int64 = .max, fade: Int = 1) -> [Float] {
        let voice = SampledNote(midi: midi, recording: bank.recording(for: midi), outputRate: rate,
                                startFrame: startFrame, releaseFrame: releaseFrame, releaseFrames: fade, gain: 1)
        let total = Int(seconds * rate)
        var out = [Float](repeating: 0, count: total)
        var frame = 0
        while frame < total {
            let n = min(512, total - frame)
            out.withUnsafeMutableBufferPointer { voice.render(into: $0.baseAddress! + frame, count: n, bufferStart: Int64(frame)) }
            frame += n
        }
        return out
    }

    static func magnitude(_ x: ArraySlice<Float>, _ hz: Double, _ rate: Double) -> Double {
        let n = x.count, w = 2 * Double.pi * hz / rate, c = 2 * cos(w)
        var s1 = 0.0, s2 = 0.0
        for (i, v) in x.enumerated() {
            let s0 = Double(v) * (0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(n - 1))) + c * s1 - s2
            s2 = s1; s1 = s0
        }
        return max(s1 * s1 + s2 * s2 - c * s1 * s2, 0).squareRoot()
    }

    /// Cents off `midi`: the first four harmonics' peaks, weighted by strength (as in
    /// build-guitar-samples.swift).
    static func centsOff(_ x: ArraySlice<Float>, midi: Int, rate: Double) -> Double {
        let f = 440 * pow(2, Double(midi - 69) / 12)
        var weighted = 0.0, total = 0.0
        for k in 1...4 where Double(k) * f < rate / 2 * 0.9 {
            var lo = -80.0, hi = 80.0, peak = 0.0
            for step in [4.0, 0.4, 0.04] {
                var best = lo, bestMag = -1.0, c = lo
                while c <= hi {
                    let m = magnitude(x, Double(k) * f * pow(2, c / 1200), rate)
                    if m > bestMag { bestMag = m; best = c }
                    c += step
                }
                lo = best - step; hi = best + step; peak = bestMag
            }
            weighted += peak * (lo + hi) / 2
            total += peak
        }
        return total > 0 ? weighted / total : 0
    }

    static func rms(_ x: ArraySlice<Float>) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))).squareRoot() }

    // MARK: - Checks

    static func checkTuning(_ bank: GuitarSampleBank) {
        for rate in [44_100.0, 48_000.0] {
            var worst = 0.0, worstMidi = 0
            var tunerWorst = 0.0, tunerWorstMidi = 0
            for midi in 40...88 {
                let x = render(bank, midi: midi, rate: rate, seconds: 1.2)
                let cents = centsOff(x[Int(0.15 * rate)..<Int(1.15 * rate)], midi: midi, rate: rate)
                if abs(cents) > abs(worst) { worst = cents; worstMidi = midi }
                // The tuner's reading, averaged over the ringing part of the note.
                if midi <= 71 {
                    var readings: [Double] = []
                    var at = Int(0.2 * rate)
                    while at + 8192 <= Int(1.1 * rate) {
                        if let hz = PitchAnalyzer.detectFrequency(in: Array(x[at..<at + 8192]), sampleRate: rate) {
                            readings.append(1200 * log2(hz / (440 * pow(2, Double(midi - 69) / 12))))
                        }
                        at += 4096
                    }
                    let tuner = readings.isEmpty ? 999 : readings.sorted()[readings.count / 2]
                    if abs(tuner) > abs(tunerWorst) { tunerWorst = tuner; tunerWorstMidi = midi }
                }
            }
            check(abs(worst) <= 3, "\(Int(rate)) Hz: MIDI \(worstMidi) is \(worst) cents off")
            // The tuner listens to short windows, so a low string that beats (the A2 recording does)
            // reads a few cents either way; 6 cents is about the smallest difference heard.
            check(abs(tunerWorst) <= 6, "\(Int(rate)) Hz: the tuner reads MIDI \(tunerWorstMidi) \(tunerWorst) cents off")
            print("ok   tuning at \(Int(rate)) Hz: worst \(String(format: "%+.1f", worst)) cents (MIDI \(worstMidi)); "
                  + "tuner reads worst \(String(format: "%+.1f", tunerWorst)) (MIDI \(tunerWorstMidi))")
        }
    }

    static func checkTiming(_ bank: GuitarSampleBank) {
        let rate = 48_000.0
        var latest = 0.0, latestMidi = 0
        for recording in bank.recordings {
            let start = Int64(777)
            let x = render(bank, midi: recording.midi, rate: rate, seconds: 0.3, startFrame: start)
            check(x[..<Int(start)].allSatisfy { $0 == 0 }, "MIDI \(recording.midi) sounds before its start frame")
            let peak = x.map(abs).max() ?? 1
            let pluck = x.firstIndex { abs($0) > peak * 0.05 } ?? x.count
            let ms = Double(pluck - Int(start)) / rate * 1000
            if ms > latest { latest = ms; latestMidi = recording.midi }
        }
        check(latest <= 2, "MIDI \(latestMidi)'s pluck lands \(latest) ms after its start frame")
        print("ok   plucks land on time (latest \(String(format: "%.1f", latest)) ms after the scheduled frame, MIDI \(latestMidi))")
    }

    static func checkLevels(_ bank: GuitarSampleBank) {
        let rate = 48_000.0
        let levels = (40...84).map { midi -> Double in
            let x = render(bank, midi: midi, rate: rate, seconds: 0.3)
            return 20 * log10(Double(rms(x[...])))
        }
        let median = levels.sorted()[levels.count / 2]
        let spread = levels.map { abs($0 - median) }.max() ?? 0
        check(spread <= 4, "loudness varies \(spread) dB from the median")
        print("ok   notes evenly loud (within \(String(format: "%.1f", spread)) dB)")
    }

    static func checkSustain(_ bank: GuitarSampleBank) {
        let rate = 48_000.0, frame = Int(0.01 * rate)
        var worstRise = 0.0, riseMidi = 0, worstStep: Float = 0, stepMidi = 0
        for midi in 40...84 {
            let x = render(bank, midi: midi, rate: rate, seconds: 6)
            let attack = rms(x[0..<Int(0.25 * rate)])
            if midi <= 72 {
                let late = rms(x[Int(2.9 * rate)..<Int(3.0 * rate)])
                check(late > attack * 0.001, "MIDI \(midi) has stopped ringing by 3 s")
            }
            // 10 ms at a time from 0.3 s until it's 60 dB down: no sudden rises or jumps.
            var previous: Float = 0, at = Int(0.3 * rate)
            while at + frame < x.count {
                let level = rms(x[at..<at + frame])
                if level < attack * 0.001 { break }
                if previous > 0 {
                    let rise = 20 * log10(Double(level / previous))
                    if rise > worstRise { worstRise = rise; riseMidi = midi }
                }
                let slice = x[at..<at + frame]
                let step = (zip(slice.dropFirst(), slice).map { abs($0 - $1) }.max() ?? 0) / max(level, 1e-9)
                if step > worstStep { worstStep = step; stepMidi = midi }
                previous = level
                at += frame
            }
        }
        // (The untouched recordings beat a little on their own: up to about 3 dB.)
        check(worstRise <= 3.5, "MIDI \(riseMidi)'s ring-out jumps \(worstRise) dB")
        check(worstStep <= 2, "MIDI \(stepMidi) has a click (a step \(worstStep)× its level)")
        print("ok   notes ring out smoothly (biggest 10 ms rise \(String(format: "%.1f", worstRise)) dB, "
              + "biggest step \(String(format: "%.1f", worstStep))× level); up to C5 still ringing at 3 s")
    }

    static func checkRelease(_ bank: GuitarSampleBank) {
        let rate = 48_000.0
        let releaseAt = Int64(0.5 * rate), fade = Int(0.08 * rate)
        let x = render(bank, midi: 52, rate: rate, seconds: 0.8, releaseFrame: releaseAt, fade: fade)
        check(x[(Int(releaseAt) + fade)...].allSatisfy { $0 == 0 }, "silent after the fade")

        let voice = SampledNote(midi: 60, recording: bank.recording(for: 60), outputRate: rate,
                                startFrame: 1000, releaseFrame: 50_000, releaseFrames: 100, gain: 1)
        voice.release(at: 500, fadeFrames: 100)
        var out = [Float](repeating: 0, count: 4000)
        out.withUnsafeMutableBufferPointer { voice.render(into: $0.baseAddress!, count: 4000, bufferStart: 0) }
        check(voice.isFinished && out.allSatisfy { $0 == 0 }, "a note cancelled before it starts is silent")

        // A note left ringing stops by itself when its recording runs out.
        let high = SampledNote(midi: 84, recording: bank.recording(for: 84), outputRate: rate,
                               startFrame: 0, releaseFrame: .max, releaseFrames: 1, gain: 1)
        var long = [Float](repeating: 0, count: Int(5 * rate))
        long.withUnsafeMutableBufferPointer { high.render(into: $0.baseAddress!, count: $0.count, bufferStart: 0) }
        check(high.isFinished, "a note ends when its recording does")
        print("ok   fades end in silence; cancelled and finished notes stop")
    }
}
