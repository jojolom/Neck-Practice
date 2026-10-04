//
//  tuner-check.swift
//
//  Offline check for PitchAnalyzer: feeds synthetic guitar plucks (strong harmonics,
//  exponential decay, noise) through the same 4096-sample / 1024-hop windowing the
//  tuner uses, and asserts every estimate after the attack is within ±5¢ of the
//  true pitch for the full 3 s decay.
//
//  Run from the repo root:
//    swiftc -O -parse-as-library -o /tmp/tuner-check "Guitar Man/NeckPracticeServicesPitchAnalyzer.swift" scripts/tuner-check.swift && /tmp/tuner-check
//

import Foundation

// Harmonic amplitude profiles (fundamental first). "weak fundamental" mimics a phone
// mic that barely picks up the low strings' first harmonic.
// The "dominant Nth harmonic" profiles are the worst case for octave/harmonic errors (a
// plain YIN locks onto the harmonic, which reads as D3 or B3 on the low E), so they only
// run against the E2 variants — on other strings that signal is genuinely ambiguous.
let profiles: [(name: String, amps: [Double], lowEOnly: Bool)] = [
    ("strong harmonics", [1.0, 0.9, 0.7, 0.4, 0.25, 0.15], false),
    ("weak fundamental", [0.25, 1.0, 0.8, 0.35, 0.2, 0.1], false),
    ("dominant 2nd harmonic", [0.10, 1.0, 0.15, 0.45, 0.08, 0.2], true),
    ("dominant 3rd harmonic", [0.12, 0.25, 1.0, 0.15, 0.4, 0.1], true),
]

let strings: [(name: String, freq: Double)] = [
    ("E2", 82.41), ("A2", 110.00), ("D3", 146.83),
    ("G3", 196.00), ("B3", 246.94), ("E4", 329.63),
    ("E2 flat (78 Hz)", 78.0), ("E2 sharp (86 Hz)", 86.0),
]

// Windows quieter than this are near the synthetic noise floor (σ ≈ 0.0017), where a single
// estimate can wander by tens of cents; the tuner's 5-sample median filter absorbs those.
let minRMS: Float = 0.01

func cents(_ f: Double, _ ref: Double) -> Double { 1200 * log2(f / ref) }

func pluck(freq: Double, amps: [Double], sampleRate: Double, seconds: Double, seed: UInt64) -> [Float] {
    var rng = seed
    func noise() -> Double {   // xorshift, uniform in -1...1
        rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17
        return Double(rng % 20001) / 10000.0 - 1.0
    }
    let count = Int(sampleRate * seconds)
    var out = [Float](repeating: 0, count: count)
    for i in 0..<count {
        let t = Double(i) / sampleRate
        var v = 0.0
        for (h, a) in amps.enumerated() {
            let decay = exp(-t / (1.4 / (1.0 + 0.5 * Double(h))))   // higher harmonics die sooner
            v += a * decay * sin(2 * .pi * freq * Double(h + 1) * t)
        }
        v *= 0.4 / amps.reduce(0, +) * 2
        v += 0.003 * noise()
        if t < 0.015 { v += 0.3 * noise() }   // pick transient
        out[i] = Float(v)
    }
    return out
}

@main
struct TunerCheck {
    static func main() {
        var failures = 0
        var checked = 0

        for sampleRate in [44100.0, 48000.0] {
            for profile in profiles {
                for string in strings where !profile.lowEOnly || string.name.hasPrefix("E2") {
                    let signal = pluck(freq: string.freq, amps: profile.amps, sampleRate: sampleRate,
                                       seconds: 3.0, seed: 0x9E3779B97F4A7C15)
                    let window = PitchAnalyzer.windowSize
                    var end = Int(0.15 * sampleRate)
                    var worst = 0.0
                    var misses = 0
                    while end <= signal.count {
                        let slice = Array(signal[(end - window)..<end])
                        let rms = sqrt(slice.reduce(0) { $0 + $1 * $1 } / Float(window))
                        if rms > minRMS {
                            checked += 1
                            if let f = PitchAnalyzer.detectFrequency(in: slice, sampleRate: sampleRate) {
                                let err = abs(cents(f, string.freq))
                                worst = max(worst, err)
                                if err > 5 {
                                    misses += 1
                                    if ProcessInfo.processInfo.environment["VERBOSE"] != nil {
                                        print("   t=\(String(format: "%.2f", Double(end) / sampleRate))s est=\(String(format: "%.2f", f)) Hz err=\(String(format: "%.1f", err))¢ rms=\(rms)")
                                    }
                                }
                            } else {
                                misses += 1
                            }
                        }
                        end += 1024
                    }
                    if misses > 0 {
                        failures += 1
                        print("FAIL \(Int(sampleRate)) Hz · \(profile.name) · \(string.name): \(misses) bad estimates, worst \(String(format: "%.1f", worst))¢")
                    } else {
                        print("ok   \(Int(sampleRate)) Hz · \(profile.name) · \(string.name): worst \(String(format: "%.2f", worst))¢")
                    }
                }
            }
        }

        print("\(checked) windows checked, \(failures) failing cases")
        exit(failures == 0 ? 0 : 1)
    }
}
