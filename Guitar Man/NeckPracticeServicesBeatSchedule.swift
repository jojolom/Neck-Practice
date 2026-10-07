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
        /// Position within the beat: 0 is the beat itself, 1… the subdivisions after it.
        var subdivision: Int = 0
    }

    let sampleRate: Double
    let beatsPerMeasure: Int
    /// Clicks per beat: 1 for beats only, 2 for eighths, 3 for triplets, 4 for sixteenths.
    let subdivisions: Int
    /// Where the next click goes (not handed out yet).
    private(set) var nextPosition: Double
    private var nextIndex = 0
    private var nextSubdivision = 0
    /// Samples between clicks at the current tempo.
    private var spacing: Double

    init(bpm: Int, beatsPerMeasure: Int, subdivisions: Int = 1, sampleRate: Double,
         firstBeatAt firstPosition: Double) {
        self.sampleRate = sampleRate
        self.beatsPerMeasure = max(1, beatsPerMeasure)
        self.subdivisions = max(1, subdivisions)
        self.nextPosition = firstPosition
        self.spacing = Self.spacing(bpm: bpm, sampleRate: sampleRate) / Double(self.subdivisions)
    }

    static func spacing(bpm: Int, sampleRate: Double) -> Double {
        60 / Double(max(1, bpm)) * sampleRate
    }

    /// The clicks from the next one up to and including sample time `horizon`, in order.
    mutating func beats(through horizon: Int64) -> [Beat] {
        var result: [Beat] = []
        while Int64(nextPosition.rounded()) <= horizon {
            result.append(Beat(sampleTime: Int64(nextPosition.rounded()), index: nextIndex,
                               subdivision: nextSubdivision))
            nextPosition += spacing
            nextSubdivision += 1
            if nextSubdivision == subdivisions {
                nextSubdivision = 0
                nextIndex = (nextIndex + 1) % beatsPerMeasure
            }
        }
        return result
    }

    /// Changes tempo from the next click on: it lands one new-tempo click after the last one
    /// handed out, but not before `earliest` (so speeding up never puts a click in the past).
    mutating func setBPM(_ bpm: Int, earliest: Int64) {
        let newSpacing = Self.spacing(bpm: bpm, sampleRate: sampleRate) / Double(subdivisions)
        nextPosition = max(nextPosition - spacing + newSpacing, Double(earliest))
        spacing = newSpacing
    }
}
