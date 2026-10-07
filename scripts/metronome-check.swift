//
//  metronome-check.swift
//
//  Offline check for the metronome's timing (BeatSchedule):
//   • beat positions never drift (10 minutes at awkward tempos land on the exact sample),
//   • a tempo change takes effect one new beat after the last scheduled click, never in the past,
//   • an AVAudioEngine rendered offline, fed the way Metronome feeds it (clicks queued 0.2 s ahead
//     from a coarse timer), plays every click on its exact sample, through a tempo change.
//     The render is paced to 40× real time: AVAudioPlayerNode takes in a scheduled buffer on
//     another thread, and unpaced, an offline render can reach a click's time before the buffer
//     has been handed over (a click queued 0.2 s ahead is due a few microseconds later), so it's
//     dropped. The app runs in real time, with 200 ms to spare against a hand-off measured well
//     under 0.5 ms; since macOS 27 the unpaced render dropped clicks in most runs.
//
//  Run from the repo root:
//    swiftc -O -parse-as-library -o /tmp/metronome-check "Guitar Man/NeckPracticeServicesBeatSchedule.swift" scripts/metronome-check.swift && /tmp/metronome-check
//

import AVFoundation
import Foundation

@main
struct MetronomeCheck {

    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        print(condition ? "ok  " : "FAIL", message)
        if !condition { failures += 1 }
    }

    static let rate = 44100.0

    static func main() {
        checkNoDrift()
        checkTempoChange()
        checkRenderedClicks()
        print(failures == 0 ? "0 failures" : "\(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }

    /// Every beat over 10 minutes is at the exact rounded position, and the accent cycles.
    static func checkNoDrift() {
        for bpm in [30, 97, 113, 120, 187, 300] {
            let first = 0.05 * rate
            var schedule = BeatSchedule(bpm: bpm, beatsPerMeasure: 4, sampleRate: rate, firstBeatAt: first)
            let beats = schedule.beats(through: Int64(600 * rate))
            let spacing = 60 / Double(bpm) * rate
            let exact = beats.enumerated().allSatisfy { k, beat in
                beat.sampleTime == Int64((first + Double(k) * spacing).rounded()) && beat.index == k % 4
            }
            check(exact && beats.count == Int((600 * rate - first) / spacing) + 1,
                  "\(bpm) BPM: \(beats.count) beats over 10 min, all on the exact sample")
        }
    }

    static func checkTempoChange() {
        // Slowing down mid-run: the next beat is one new beat after the last one handed out.
        var schedule = BeatSchedule(bpm: 120, beatsPerMeasure: 4, sampleRate: rate, firstBeatAt: 0)
        let before = schedule.beats(through: Int64(2 * rate))       // beats at 0, 0.5 … 2.0 s
        schedule.setBPM(60, earliest: Int64(2.1 * rate))
        let after = schedule.beats(through: Int64(5 * rate))
        check(after.first?.sampleTime == before.last!.sampleTime + Int64(rate),
              "120→60 BPM: next click one 60-BPM beat after the last")
        check(after.first?.index == (before.last!.index + 1) % 4, "tempo change keeps counting the measure")

        // Speeding up a lot after a long gap: never schedule into the past.
        var slow = BeatSchedule(bpm: 30, beatsPerMeasure: 4, sampleRate: rate, firstBeatAt: 0)
        _ = slow.beats(through: 0)                                   // one click at 0; next at 2 s
        let now = Int64(1.5 * rate)
        slow.setBPM(300, earliest: now + Int64(0.02 * rate))
        let next = slow.beats(through: Int64(3 * rate))
        check(next.first.map { $0.sampleTime >= now } ?? false, "30→300 BPM after 1.5 s: next click isn't in the past")
        check(next.count >= 2 && next[1].sampleTime - next[0].sampleTime == Int64((0.2 * rate).rounded()),
              "30→300 BPM: then 0.2 s apart")
    }

    /// Renders 16 s with an offline engine, scheduling the way Metronome does, and finds the clicks.
    static func checkRenderedClicks() {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
            try engine.start()
        } catch {
            check(false, "offline engine: \(error)")
            return
        }

        let click = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1323)!
        click.frameLength = 1323
        for i in 0..<1323 {
            let t = Double(i) / rate
            click.floatChannelData![0][i] = Float(exp(-t * 80) * sin(2 * .pi * 800 * t))
        }

        let lookahead = Int64(0.2 * rate)
        var schedule = BeatSchedule(bpm: 120, beatsPerMeasure: 4, sampleRate: rate, firstBeatAt: 0.05 * rate)
        var expected: [Int64] = []
        func queue(through horizon: Int64) {
            for beat in schedule.beats(through: horizon) {
                player.scheduleBuffer(click, at: AVAudioTime(sampleTime: beat.sampleTime, atRate: rate), options: [], completionHandler: nil)
                expected.append(beat.sampleTime)
            }
        }
        queue(through: lookahead)
        player.play()

        // Render in ~50 ms chunks (the app's display timer is faster; this is the worse case),
        // paced to 40× real time (see the header).
        let out = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 2205)!
        var rendered: [Float] = []
        var changedTempo = false
        while rendered.count < Int(16 * rate) {
            guard (try? engine.renderOffline(2205, to: out)) == .success else { break }
            rendered += Array(UnsafeBufferPointer(start: out.floatChannelData![0], count: Int(out.frameLength)))
            Thread.sleep(forTimeInterval: Double(out.frameLength) / rate / 40)
            guard let nodeTime = player.lastRenderTime,
                  let now = player.playerTime(forNodeTime: nodeTime)?.sampleTime else { continue }
            if !changedTempo && now >= Int64(8 * rate) {
                schedule.setBPM(97, earliest: now + Int64(0.02 * rate))
                changedTempo = true
            }
            queue(through: now + lookahead)
        }

        // Click onsets: first loud sample after a quiet stretch.
        var onsets: [Int64] = []
        var quiet = 2000
        for (i, x) in rendered.enumerated() {
            if abs(x) > 0.01 {
                if quiet >= 2000 { onsets.append(Int64(i)) }
                quiet = 0
            } else {
                quiet += 1
            }
        }
        let heard = expected.filter { $0 < Int64(rendered.count) - 2000 }
        let offset = (onsets.first ?? 0) - (heard.first ?? 0)   // the sine starts at zero
        let matches = onsets.count >= heard.count
            && zip(heard, onsets).allSatisfy { $1 - $0 == offset }
        check(changedTempo, "rendered: tempo changed at 8 s (120 → 97 BPM)")
        check(matches && (0...1).contains(offset),
              "rendered: \(onsets.count) clicks, every one on its scheduled sample (offset \(offset))")
    }
}
