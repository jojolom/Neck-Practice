//
//  synth-check.swift
//
//  Offline check for PluckedString, the note synth behind AudioPlayer: every note from low E
//  (E2) to E6 plays in tune at 44.1 and 48 kHz; notes up to E5 ring for about their ring time; a note
//  starts on exactly the frame it was scheduled for; the fade at the end is smooth and ends
//  in silence; and a note cancelled before it starts makes no sound.
//
//  Run from the repo root:
//    swiftc -O -parse-as-library -o /tmp/synth-check "Guitar Man/NeckPracticeServicesPluckedString.swift" scripts/synth-check.swift && /tmp/synth-check
//

import Foundation

@main
struct SynthCheck {

    static var failures = 0

    static func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition {
            print("FAIL", message())
            failures += 1
        }
    }

    static func main() {
        checkTuning()
        checkRing()
        checkTiming()
        checkRelease()
        print(failures == 0 ? "All synth checks passed." : "\(failures) failure(s).")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Helpers

    static func frequency(midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

    /// Renders `seconds` of one note that starts at frame 0 and isn't released.
    static func render(midi: Int, sampleRate: Double, seconds: Double,
                       startFrame: Int64 = 0, releaseFrame: Int64 = .max, releaseFrames: Int = 1) -> [Float] {
        let voice = PluckedString(midi: midi, sampleRate: sampleRate, startFrame: startFrame,
                                  releaseFrame: releaseFrame, releaseFrames: releaseFrames, gain: 0.5)
        let total = Int(seconds * sampleRate)
        var out = [Float](repeating: 0, count: total)
        var frame = 0
        while frame < total {
            let count = min(512, total - frame)  // render in buffers, like the audio thread
            out.withUnsafeMutableBufferPointer { buf in
                voice.render(into: buf.baseAddress! + frame, count: count, bufferStart: Int64(frame))
            }
            frame += count
        }
        return out
    }

    /// Magnitude of `samples` (Hann-windowed) at `hz`.
    static func magnitude(_ samples: ArraySlice<Float>, at hz: Double, sampleRate: Double) -> Double {
        let n = samples.count
        let w = 2 * Double.pi * hz / sampleRate
        var re = 0.0, im = 0.0
        for (k, x) in samples.enumerated() {
            let hann = 0.5 - 0.5 * cos(2 * Double.pi * Double(k) / Double(n - 1))
            let v = Double(x) * hann
            re += v * cos(w * Double(k))
            im -= v * sin(w * Double(k))
        }
        return (re * re + im * im).squareRoot()
    }

    /// The frequency near `around` (±60 cents) where the spectrum peaks, to about 0.1 cent.
    static func peakFrequency(_ samples: ArraySlice<Float>, around: Double, sampleRate: Double) -> Double {
        var lo = -60.0, hi = 60.0
        for step in [5.0, 0.5, 0.05] {
            var best = lo, bestMag = -1.0
            var c = lo
            while c <= hi {
                let m = magnitude(samples, at: around * pow(2, c / 1200), sampleRate: sampleRate)
                if m > bestMag { bestMag = m; best = c }
                c += step
            }
            lo = best - step; hi = best + step
        }
        return around * pow(2, (lo + hi) / 2 / 1200)
    }

    // MARK: - Checks

    static func checkTuning() {
        for sampleRate in [44_100.0, 48_000.0] {
            var worst = 0.0, worstMidi = 0
            for midi in 40...88 {
                let f = frequency(midi: midi)
                let samples = render(midi: midi, sampleRate: sampleRate, seconds: 0.5)
                let measured = peakFrequency(samples[Int(0.02 * sampleRate)...], around: f, sampleRate: sampleRate)
                let cents = 1200 * log2(measured / f)
                if abs(cents) > abs(worst) { worst = cents; worstMidi = midi }
            }
            check(abs(worst) <= 2, "\(Int(sampleRate)) Hz: MIDI \(worstMidi) is \(worst) cents off")
            print("ok   tuning at \(Int(sampleRate)) Hz: worst \(String(format: "%+.2f", worst)) cents (MIDI \(worstMidi))")
        }
    }

    static func checkRing() {
        let sampleRate = 48_000.0
        // (Up around E6 the string's low-pass alone fades it faster than ringTime, as on a real guitar.)
        for midi in [40, 52, 64, 76] {
            let f = frequency(midi: midi)
            let samples = render(midi: midi, sampleRate: sampleRate, seconds: 1.0)
            let window = Int(0.1 * sampleRate)
            let a = magnitude(samples[Int(0.2 * sampleRate)..<Int(0.2 * sampleRate) + window], at: f, sampleRate: sampleRate)
            let b = magnitude(samples[Int(0.7 * sampleRate)..<Int(0.7 * sampleRate) + window], at: f, sampleRate: sampleRate)
            let measuredDrop = 20 * log10(a / b)  // over 0.5 s
            let expectedDrop = 60 * 0.5 / PluckedString.ringTime(midi: midi)
            check(abs(measuredDrop - expectedDrop) <= expectedDrop * 0.3,
                  "MIDI \(midi): fundamental falls \(measuredDrop) dB in 0.5 s, expected about \(expectedDrop)")
        }
        let mean = render(midi: 52, sampleRate: sampleRate, seconds: 0.5).reduce(0, +) / Float(0.5 * sampleRate)
        check(abs(mean) < 0.002, "no DC offset (mean \(mean))")
        print("ok   ring times and no DC offset")
    }

    static func checkTiming() {
        let sampleRate = 48_000.0
        for start in [Int64(0), 1, 511, 512, 1000, 4097] {
            let samples = render(midi: 64, sampleRate: sampleRate, seconds: 0.2, startFrame: start)
            let first = samples.firstIndex { $0 != 0 } ?? -1
            check(first == Int(start), "note scheduled for frame \(start) starts at \(first)")
        }
        print("ok   notes start on their exact frame")
    }

    static func checkRelease() {
        let sampleRate = 48_000.0
        let releaseAt = Int64(0.5 * sampleRate)
        let fade = Int(0.08 * sampleRate)
        let samples = render(midi: 45, sampleRate: sampleRate, seconds: 0.8,
                             releaseFrame: releaseAt, releaseFrames: fade)
        let afterFade = samples[(Int(releaseAt) + fade)...]
        check(afterFade.allSatisfy { $0 == 0 }, "silent after the fade")
        // No click: the biggest sample-to-sample step at the fade isn't bigger than while ringing.
        func maxStep(_ s: ArraySlice<Float>) -> Float {
            zip(s.dropFirst(), s).map { abs($0 - $1) }.max() ?? 0
        }
        let ringing = maxStep(samples[Int(releaseAt) - 2000..<Int(releaseAt)])
        let fading = maxStep(samples[Int(releaseAt) - 10..<Int(releaseAt) + fade])
        check(fading <= ringing * 1.05, "fade is smooth (step \(fading) vs \(ringing) while ringing)")

        // Cancelled before it starts: no sound at all.
        let voice = PluckedString(midi: 60, sampleRate: sampleRate, startFrame: 1000, releaseFrame: 50_000,
                                  releaseFrames: 100, gain: 0.5)
        voice.release(at: 500, fadeFrames: 100)
        var out = [Float](repeating: 0, count: 4000)
        out.withUnsafeMutableBufferPointer { voice.render(into: $0.baseAddress!, count: 4000, bufferStart: 0) }
        check(voice.isFinished && out.allSatisfy { $0 == 0 }, "a note cancelled before it starts is silent")

        // Stopped early while ringing: fades out within the stop fade.
        let ringingVoice = PluckedString(midi: 60, sampleRate: sampleRate, startFrame: 0, releaseFrame: 100_000,
                                         releaseFrames: 4000, gain: 0.5)
        var buffer = [Float](repeating: 0, count: 2000)
        buffer.withUnsafeMutableBufferPointer { ringingVoice.render(into: $0.baseAddress!, count: 2000, bufferStart: 0) }
        ringingVoice.release(at: 2000, fadeFrames: 1200)
        var tail = [Float](repeating: 0, count: 2000)
        tail.withUnsafeMutableBufferPointer { ringingVoice.render(into: $0.baseAddress!, count: 2000, bufferStart: 2000) }
        check(ringingVoice.isFinished && tail[1200...].allSatisfy { $0 == 0 }, "a stopped note is silent after the stop fade")
        print("ok   fades are smooth and end in silence")
    }
}
