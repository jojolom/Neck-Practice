//
//  BeatSchedule.swift
//  Neck Practice
//
//  Where the metronome's clicks fall on the audio player's sample timeline. Pure (Foundation
//  only) so it can be checked offline — see scripts/metronome-check.swift. Positions are kept
//  as Double and only rounded per click, so a long run never drifts.
//

import Foundation

struct BeatSchedule {

    struct Beat: Equatable {
        /// Player sample time the click starts at.
        let sampleTime: Int64
        /// Beat within the measure, 0-based (0 = accent).
        let index: Int
    }

    let sampleRate: Double
    let beatsPerMeasure: Int
    /// Where the next beat goes (not handed out yet).
    private(set) var nextPosition: Double
    private var nextIndex = 0
    /// Samples between beats at the current tempo.
    private var spacing: Double

    init(bpm: Int, beatsPerMeasure: Int, sampleRate: Double, firstBeatAt firstPosition: Double) {
        self.sampleRate = sampleRate
        self.beatsPerMeasure = max(1, beatsPerMeasure)
        self.nextPosition = firstPosition
        self.spacing = Self.spacing(bpm: bpm, sampleRate: sampleRate)
    }

    static func spacing(bpm: Int, sampleRate: Double) -> Double {
        60 / Double(max(1, bpm)) * sampleRate
    }

    /// The beats from the next one up to and including sample time `horizon`, in order.
    mutating func beats(through horizon: Int64) -> [Beat] {
        var result: [Beat] = []
        while Int64(nextPosition.rounded()) <= horizon {
            result.append(Beat(sampleTime: Int64(nextPosition.rounded()), index: nextIndex))
            nextPosition += spacing
            nextIndex = (nextIndex + 1) % beatsPerMeasure
        }
        return result
    }

    /// Changes tempo from the next beat on: it lands one new-tempo beat after the last one handed
    /// out, but not before `earliest` (so speeding up never puts a click in the past).
    mutating func setBPM(_ bpm: Int, earliest: Int64) {
        let newSpacing = Self.spacing(bpm: bpm, sampleRate: sampleRate)
        nextPosition = max(nextPosition - spacing + newSpacing, Double(earliest))
        spacing = newSpacing
    }
}
