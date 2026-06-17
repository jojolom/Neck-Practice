//
//  SightReadingSession.swift
//  Neck Practice
//
//  Generates notes on a treble clef staff for the user to locate on the fretboard.
//

import Foundation
import Observation

// MARK: - StaffPitch

/// A concrete pitch: note name + octave (e.g. G3, C#4).
struct StaffPitch: Equatable {
    let note: Note
    let octave: Int   // concert octave

    /// MIDI note number.
    var midi: Int { 12 * (octave + 1) + note.rawValue }

    /// Written octave for guitar notation (concert + 1).
    var writtenOctave: Int { octave + 1 }

    /// Staff position relative to the bottom line (E4 in written pitch).
    /// Each unit = one diatonic step = half a line-spacing on the staff.
    var staffPosition: Int {
        let pos = writtenOctave * 7 + note.diatonicIndex
        let bottomLine = 4 * 7 + 2  // E4 = bottom line of treble clef
        return pos - bottomLine
    }
}

// MARK: - SightReadingSession

@Observable
final class SightReadingSession {

    // MARK: - Settings

    var maxFret: Int = 5
    var naturalsOnly: Bool = true

    // MARK: - State

    private(set) var currentPitch: StaffPitch?
    /// All fretboard positions that produce the same MIDI pitch as currentPitch.
    private(set) var validPositions: Set<FretboardPosition> = []
    private(set) var score: Int = 0
    private(set) var streak: Int = 0
    private(set) var totalAnswered: Int = 0

    /// Spaced-repetition weights keyed by position id.
    private var weights: [String: Int] = [:]

    var accuracy: Double {
        guard totalAnswered > 0 else { return 0 }
        return Double(score) / Double(totalAnswered)
    }

    /// Pool of candidate positions (frets 1..maxFret, filtered by naturalsOnly).
    private var pool: [FretboardPosition] {
        positions(frets: 1...maxFret).filter { pos in
            naturalsOnly ? pos.note.isNatural : true
        }
    }

    // MARK: - Public API

    func start() {
        drawNext()
    }

    /// Check whether the tapped fretboard position matches the target pitch.
    @discardableResult
    func answer(position: FretboardPosition) -> Bool {
        guard let target = currentPitch else { return false }
        let correct = position.midiNote == target.midi
        totalAnswered += 1
        if correct {
            score += 1
            streak += 1
            weights[position.id] = max(1, (weights[position.id] ?? 1) - 1)
        } else {
            streak = 0
            weights[position.id] = (weights[position.id] ?? 1) + 3
        }
        return correct
    }

    func advance() {
        drawNext()
    }

    func reset() {
        score = 0
        streak = 0
        totalAnswered = 0
        weights = [:]
        drawNext()
    }

    // MARK: - Private

    private func drawNext() {
        let candidates = pool
        guard !candidates.isEmpty else { currentPitch = nil; validPositions = []; return }

        // Weighted random selection, avoid repeating the same pitch.
        let weightedPool = candidates.flatMap { pos in
            Array(repeating: pos, count: weights[pos.id] ?? 1)
        }
        let filtered = weightedPool.filter { pos in
            guard let current = currentPitch else { return true }
            return pos.midiNote != current.midi
        }
        let source = filtered.isEmpty ? weightedPool : filtered

        guard let chosen = source.randomElement() else { return }

        let pitch = StaffPitch(note: chosen.note, octave: chosen.octave)
        currentPitch = pitch

        // Find ALL positions that produce this exact pitch.
        validPositions = Set(candidates.filter { $0.midiNote == pitch.midi })
    }
}
