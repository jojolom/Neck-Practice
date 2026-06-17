//
//  QuizSession.swift
//  Neck Practice
//

import Foundation
import Observation

/// Tracks performance per fretboard position for lightweight spaced repetition.
@Observable
final class QuizSession {

    // MARK: - Settings

    /// The highest fret included in this session.
    var maxFret: Int = 5

    /// When true, only natural notes are quizzed.
    var naturalsOnly: Bool = true

    /// Number of answer choices shown (4 to pool size).
    var choiceCount: Int = 4

    // MARK: - State

    private(set) var currentPosition: FretboardPosition?
    private(set) var score: Int = 0
    private(set) var streak: Int = 0
    private(set) var totalAnswered: Int = 0

    /// Wrong-answer weight per position id. Higher = shown more often.
    private var weights: [String: Int] = [:]

    /// Pool of candidate positions based on current settings (open strings excluded).
    private var pool: [FretboardPosition] {
        positions(frets: 1...maxFret).filter { pos in
            naturalsOnly ? pos.note.isNatural : true
        }
    }

    // MARK: - Public API

    func start() {
        drawNextPosition()
    }

    /// Score the user's answer. Returns `true` if correct.
    /// The view is responsible for calling `advance()` after showing feedback.
    @discardableResult
    func answer(_ note: Note) -> Bool {
        guard let current = currentPosition else { return false }
        let correct = note == current.note
        totalAnswered += 1
        if correct {
            score += 1
            streak += 1
            weights[current.id] = max(1, (weights[current.id] ?? 1) - 1)
        } else {
            streak = 0
            weights[current.id] = (weights[current.id] ?? 1) + 3
        }
        // The view always calls advance() after showing feedback.
        return correct
    }

    /// Move to the next question after a wrong-answer delay.
    func advance() {
        drawNextPosition()
    }

    func reset() {
        score = 0
        streak = 0
        totalAnswered = 0
        weights = [:]
        drawNextPosition()
    }

    var accuracy: Double {
        guard totalAnswered > 0 else { return 0 }
        return Double(score) / Double(totalAnswered)
    }

    // MARK: - Private

    private func drawNextPosition() {
        let candidates = pool
        guard !candidates.isEmpty else { currentPosition = nil; return }

        // Build a weighted array for random selection.
        let weightedPool = candidates.flatMap { pos in
            Array(repeating: pos, count: weights[pos.id] ?? 1)
        }
        // Avoid repeating the same position twice in a row.
        let filtered = weightedPool.filter { $0 != currentPosition }
        let source = filtered.isEmpty ? weightedPool : filtered
        currentPosition = source.randomElement()
    }
}
