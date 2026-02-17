//
//  TriadSession.swift
//  Guitar Man
//

import Foundation
import Observation

/// Drives the Triad Trainer exercise.
///
/// Each question is a TriadQuestion drawn from the pool of 12 shapes at a random fret.
/// Answering is two steps: first identify Major/Minor, then name the root note.
/// The view calls `answerQuality(_:)` and `answerRoot(_:)` in order, then `advance()`.
@Observable
final class TriadSession {

    // MARK: - Settings

    /// nil = show both string groups
    var stringGroupFilter: StringGroup? = nil
    /// nil = show both qualities
    var qualityFilter: TriadQuality? = nil
    /// Shapes will be placed so that all frets fall within 1...maxFret
    var maxFret: Int = 9

    // MARK: - State

    private(set) var currentQuestion: TriadQuestion?
    private(set) var score: Int = 0
    private(set) var streak: Int = 0
    private(set) var totalAnswered: Int = 0

    /// Wrong-answer boost weight per shape id.
    private var weights: [String: Int] = [:]

    // MARK: - Derived

    var accuracy: Double {
        guard totalAnswered > 0 else { return 0 }
        return Double(score) / Double(totalAnswered)
    }

    private var pool: [TriadShape] {
        allTriadShapes.filter { shape in
            if let gf = stringGroupFilter, shape.stringGroup != gf { return false }
            if let qf = qualityFilter,     shape.quality     != qf { return false }
            return true
        }
    }

    // MARK: - Public API

    func start() { drawNext() }

    /// Step 1: score the quality answer. Returns true if correct.
    /// Does NOT advance — the view handles feedback then calls advance().
    @discardableResult
    func answerQuality(_ quality: TriadQuality) -> Bool {
        guard let q = currentQuestion else { return false }
        let correct = quality == q.shape.quality
        totalAnswered += 1
        if correct {
            score += 1
            streak += 1
            weights[q.shape.id] = max(1, (weights[q.shape.id] ?? 1) - 1)
        } else {
            streak = 0
            weights[q.shape.id] = (weights[q.shape.id] ?? 1) + 3
        }
        return correct
    }

    /// Step 2: score the root-note answer. Returns true if correct.
    /// Does NOT advance — the view handles feedback then calls advance().
    @discardableResult
    func answerRoot(_ note: Note) -> Bool {
        guard let q = currentQuestion else { return false }
        return note == q.rootNote
    }

    /// Move to the next question.
    func advance() { drawNext() }

    func reset() {
        score = 0; streak = 0; totalAnswered = 0; weights = [:]
        drawNext()
    }

    // MARK: - Private

    private func drawNext() {
        let candidates = pool
        guard !candidates.isEmpty else { currentQuestion = nil; return }

        let weighted = candidates.flatMap { shape in
            Array(repeating: shape, count: weights[shape.id] ?? 1)
        }
        let filtered = weighted.filter { $0.id != currentQuestion?.shape.id }
        let source   = filtered.isEmpty ? weighted : filtered
        guard let shape = source.randomElement() else { currentQuestion = nil; return }

        // Pick a baseFret so the highest offset fret ≤ maxFret and baseFret ≥ 1
        let maxOffset = shape.fretOffsets.max() ?? 0
        let highestBase = max(1, maxFret - maxOffset)
        guard highestBase >= 1 else { currentQuestion = nil; return }
        let baseFret = Int.random(in: 1...highestBase)

        currentQuestion = TriadQuestion(shape: shape, baseFret: baseFret)
    }
}
