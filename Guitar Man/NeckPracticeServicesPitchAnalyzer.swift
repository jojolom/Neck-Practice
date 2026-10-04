//
//  PitchAnalyzer.swift
//  Neck Practice
//
//  Pure pitch analysis (no AVFoundation): YIN autocorrelation plus a subharmonic
//  check so a string's 2nd/3rd harmonic isn't mistaken for the fundamental
//  (low E's harmonics land on D3 and B3).  Kept separate from PitchDetector so it
//  can be compiled and tested offline — see scripts/tuner-check.swift.
//

import Accelerate
import Foundation

struct PitchAnalyzer {

    /// Number of most-recent samples to analyze (≥3.5 low-E periods at 48 kHz).
    static let windowSize = 4096

    /// Standard-tuning open string frequencies, used to sanity-check subharmonic candidates.
    private static let stringFrequencies: [Double] = [329.63, 246.94, 196.00, 146.83, 110.00, 82.41]

    private static let threshold: Float = 0.20
    /// A longer period only wins if its interpolated difference minimum is below this fraction
    /// of the first dip's.  (Raw `d`, not cmndf: cmndf's running-mean normalization is biased
    /// toward longer lags.  Interpolated, because a period that isn't a whole number of samples
    /// leaves a different integer-lag residue at τ than at 3τ.)
    private static let subharmonicRatio: Float = 0.5
    /// A longer-period candidate must land within this many cents of an open string.
    private static let subharmonicStringToleranceCents: Double = 150

    /// Returns the fundamental frequency in Hz, or nil if no confident pitch is found.
    static func detectFrequency(in samples: [Float], sampleRate: Double) -> Double? {
        let halfLength = samples.count / 2
        let minTau = max(2, Int(sampleRate / 600))
        let maxTau = min(Int(sampleRate / 60), halfLength - 1)
        guard maxTau > minTau + 8 else { return nil }

        // Compute a little past maxTau so the local-minimum search near k·tau has headroom.
        let limit = min(maxTau + 8, halfLength - 1)
        let windowSize = vDSP_Length(halfLength)
        var diff = [Float](repeating: 0, count: limit + 1)
        var cmndf = [Float](repeating: 0, count: limit + 1)
        var temp = [Float](repeating: 0, count: halfLength)
        cmndf[0] = 1.0

        var runningSum: Float = 0
        samples.withUnsafeBufferPointer { ptr in
            let base = ptr.baseAddress!
            for tau in 1...limit {
                vDSP_vsub(base + tau, 1, base, 1, &temp, 1, windowSize)
                var sum: Float = 0
                vDSP_svesq(temp, 1, &sum, windowSize)
                diff[tau] = sum
                runningSum += sum
                cmndf[tau] = runningSum > 0 ? sum / (runningSum / Float(tau)) : 1.0
            }
        }

        // First dip below the threshold, descended to its local minimum.
        var bestTau = -1
        for tau in minTau...maxTau where cmndf[tau] < threshold {
            var localMin = tau
            while localMin + 1 <= limit && cmndf[localMin + 1] < cmndf[localMin] {
                localMin += 1
            }
            bestTau = localMin
            break
        }
        guard bestTau > 0 else { return nil }

        // Subharmonic check: if the first dip was really a harmonic, the true period
        // (2× or 3× longer) will be clearly better — and sit near an open string.
        var chosenTau = bestTau
        var chosenValue = refinedMinimum(diff, at: bestTau, limit: limit).value
        let firstValue = chosenValue
        for k in 2...3 {
            let center = bestTau * k
            let window = max(4, center / 40)
            guard center + window <= limit else { continue }
            var m = center - window
            for t in (center - window)...(center + window) where diff[t] < diff[m] { m = t }
            let candidate = refinedMinimum(diff, at: m, limit: limit).value
            guard cmndf[m] < threshold * 1.5,
                  candidate < firstValue * subharmonicRatio,
                  candidate < chosenValue else { continue }
            let frequency = sampleRate / Double(m)
            guard frequency >= 60, isNearOpenString(frequency) else { continue }
            chosenTau = m
            chosenValue = candidate
        }

        let frequency = sampleRate / refinedMinimum(cmndf, at: chosenTau, limit: limit).position

        // Sanity check: guitar fundamental range (generous bounds)
        guard frequency >= 60 && frequency <= 500 else { return nil }
        return frequency
    }

    // MARK: - Helpers

    private static func isNearOpenString(_ frequency: Double) -> Bool {
        stringFrequencies.contains {
            abs(1200.0 * log2(frequency / $0)) <= subharmonicStringToleranceCents
        }
    }

    /// Sub-sample position and value of the minimum near `index`, from a least-squares
    /// parabola over ±w samples (w grows with the lag).  Fitting several points is far less
    /// sensitive to noise than a 3-point parabola on a shallow, noisy dip.
    private static func refinedMinimum(_ values: [Float], at index: Int, limit: Int) -> (position: Double, value: Float) {
        let w = max(2, min(5, index / 60))
        guard index - w >= 1 && index + w <= limit else { return (Double(index), values[index]) }

        let n = Double(2 * w + 1)
        var sx2 = 0.0, sx4 = 0.0, sy = 0.0, sxy = 0.0, sx2y = 0.0
        for x in -w...w {
            let xd = Double(x)
            let y = Double(values[index + x])
            sx2 += xd * xd
            sx4 += xd * xd * xd * xd
            sy += y
            sxy += xd * y
            sx2y += xd * xd * y
        }
        let b = sxy / sx2
        let c = (sx2y - sx2 * sy / n) / (sx4 - sx2 * sx2 / n)
        guard c > 1e-12 else { return (Double(index), values[index]) }
        let a = (sy - c * sx2) / n
        let offset = -b / (2 * c)
        guard abs(offset) <= Double(w) else { return (Double(index), values[index]) }
        return (Double(index) + offset, Float(max(0, a - b * b / (4 * c))))
    }
}
