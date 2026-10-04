//
//  loop-library-check.swift
//
//  Offline check for LoopLibrary: CAF write/read round trip, delete, sample-rate conversion
//  (length + pitch preserved), and the preview WAV. Uses a temp directory, never the real library.
//
//  Run from the repo root:
//    swiftc -O -parse-as-library -o /tmp/loop-library-check "Guitar Man/NeckPracticeServicesLoopLibrary.swift" scripts/loop-library-check.swift && /tmp/loop-library-check
//

import AVFoundation
import Foundation

@main
struct LoopLibraryCheck {

    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        print(condition ? "ok  " : "FAIL", message)
        if !condition { failures += 1 }
    }

    static func sine(_ freq: Double, rate: Double, seconds: Double) -> [Float] {
        (0..<Int(rate * seconds)).map { Float(0.5 * sin(2 * .pi * freq * Double($0) / rate)) }
    }

    /// Frequency from upward zero crossings in the middle of the signal (ignores converter edges).
    static func measuredFrequency(_ x: [Float], rate: Double) -> Double {
        let lo = x.count / 4, hi = x.count * 3 / 4
        var crossings: [Double] = []
        for i in lo..<hi where x[i - 1] < 0 && x[i] >= 0 {
            // linear interpolation for a sub-sample crossing position
            crossings.append(Double(i - 1) + Double(-x[i - 1]) / Double(x[i] - x[i - 1]))
        }
        guard crossings.count > 2 else { return 0 }
        return Double(crossings.count - 1) * rate / (crossings.last! - crossings.first!)
    }

    static func main() {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("loop-library-check-\(UUID().uuidString)")
        LoopLibrary.directory = tmp
        defer { try? FileManager.default.removeItem(at: tmp) }

        // --- write / read round trip
        for rate in [44100.0, 48000.0] {
            let samples = sine(220, rate: rate, seconds: 1.5)
            do {
                let name = try LoopLibrary.write(samples: samples, sampleRate: rate)
                check(name.hasSuffix(".caf") && FileManager.default.fileExists(atPath: LoopLibrary.fileURL(for: name).path),
                      "write \(Int(rate)) Hz creates a .caf file")
                let back = try LoopLibrary.read(fileName: name)
                check(back.sampleRate == rate, "read returns the stored sample rate (\(Int(rate)))")
                check(back.samples == samples, "read returns identical samples (\(samples.count) frames)")
                LoopLibrary.delete(fileName: name)
                check(!FileManager.default.fileExists(atPath: LoopLibrary.fileURL(for: name).path), "delete removes the file")
            } catch {
                check(false, "round trip at \(Int(rate)) Hz threw \(error)")
            }
        }

        do {
            _ = try LoopLibrary.write(samples: [], sampleRate: 48000)
            check(false, "writing empty audio should throw")
        } catch {
            check(true, "writing empty audio throws")
        }

        // --- resample
        let a = sine(440, rate: 44100, seconds: 2)
        check(LoopLibrary.resample(a, from: 44100, to: 44100) == a, "same rate is a no-op")

        for (from, to) in [(44100.0, 48000.0), (48000.0, 44100.0)] {
            let input = sine(440, rate: from, seconds: 2)
            let out = LoopLibrary.resample(input, from: from, to: to)
            let expected = Int((Double(input.count) * to / from).rounded())
            check(out.count == expected, "resample \(Int(from))→\(Int(to)) length is exactly \(expected) (got \(out.count))")
            let f = measuredFrequency(out, rate: to)
            check(abs(f - 440) < 1.0, "resample \(Int(from))→\(Int(to)) keeps pitch (440 Hz → \(String(format: "%.2f", f)) Hz)")
            let peak = out[(out.count / 4)..<(out.count * 3 / 4)].map { abs($0) }.max() ?? 0
            check(abs(peak - 0.5) < 0.03, "resample \(Int(from))→\(Int(to)) keeps level (peak \(String(format: "%.3f", peak)))")
        }

        // --- preview WAV
        let wav = LoopLibrary.wavData(samples: sine(330, rate: 48000, seconds: 0.5), sampleRate: 48000)
        check(wav.count == 44 + 24000 * 2, "wav is header + 16-bit mono data (\(wav.count) bytes)")
        if let player = try? AVAudioPlayer(data: wav) {
            check(abs(player.duration - 0.5) < 0.01, "AVAudioPlayer opens the WAV (duration \(String(format: "%.3f", player.duration)) s)")
        } else {
            check(false, "AVAudioPlayer could not open the WAV")
        }

        print("\(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
