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
    private(set) var subdivisions: Int
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

    /// Changes clicks per beat from the next click on, keeping the beats where they are: the next
    /// click is the first of the new grid at or after `earliest` and the last one handed out.
    mutating func setSubdivisions(_ subdivisions: Int, earliest: Int64) {
        let new = max(1, subdivisions)
        guard new != self.subdivisions else { return }
        let beatSpacing = spacing * Double(self.subdivisions)
        var beatStart = nextPosition - Double(nextSubdivision) * spacing
        let newSpacing = beatSpacing / Double(new)
        let target = max(nextPosition, Double(earliest))
        // (The small nudge: a target already on the new grid mustn't round up past its click.)
        var slot = max(Int(((target - beatStart) / newSpacing - 1e-6).rounded(.up)), 0)
        while slot >= new {
            slot -= new
            beatStart += beatSpacing
            nextIndex = (nextIndex + 1) % beatsPerMeasure
        }
        nextPosition = beatStart + Double(slot) * newSpacing
        nextSubdivision = slot
        spacing = newSpacing
        self.subdivisions = new
    }
}
