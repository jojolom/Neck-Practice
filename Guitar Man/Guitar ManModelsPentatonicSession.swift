//
//  PentatonicSession.swift
//  Guitar Man
//

import Foundation
import Observation

/// Drives the Pentatonic Trainer exercise.
///
/// Each question shows one of the 5 box shapes at a random key and fret position.
/// Two-step answer: first identify the position number (1–5), then name the root note.
@Observable
final class PentatonicSession {

    // MARK: - Settings

    /// nil = randomize quality per question
    var qualityFilter: PentatonicQuality? = nil
    /// nil = all 5 positions; 1–5 = drill that position only
    var positionFilter: Int? = nil
    /// Upper bound on fret positions shown
    var maxFret: Int = 12

    // MARK: - State

    private(set) var currentQuestion: PentatonicQuestion?
    private(set) var score: Int = 0
    private(set) var streak: Int = 0
    private(set) var totalAnswered: Int = 0

    private var weights: [Int: Int] = [:]   // keyed by shape.id (1–5)

    // MARK: - Derived

    var accuracy: Double {
        guard totalAnswered > 0 else { return 0 }
        return Double(score) / Double(totalAnswered)
    }

    private var pool: [PentatonicShape] {
        allPentatonicShapes.filter { shape in
            if let pf = positionFilter { return shape.id == pf }
            return true
        }
    }

    // MARK: - Public API

    func start() { drawNext() }

    /// Step 1: score the position-number answer. Returns true if correct.
    @discardableResult
    func answerPosition(_ position: Int) -> Bool {
        guard let q = currentQuestion else { return false }
        let correct = position == q.shape.id
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
    @discardableResult
    func answerRoot(_ note: Note) -> Bool {
        guard let q = currentQuestion else { return false }
        return note == q.rootNote
    }

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

        // Pick a quality
        let quality: PentatonicQuality = qualityFilter ?? PentatonicQuality.allCases.randomElement()!

        // Build a question: try up to 20 random root notes until one gives a valid fret range
        for _ in 0..<20 {
            guard let rootNote = Note.allCases.randomElement() else { continue }
            guard let question = makeQuestion(shape: shape, quality: quality, rootNote: rootNote) else { continue }
            currentQuestion = question
            return
        }

        // Fallback: try every note
        for rootNote in Note.allCases {
            if let question = makeQuestion(shape: shape, quality: quality, rootNote: rootNote) {
                currentQuestion = question
                return
            }
        }

        currentQuestion = nil
    }

    private func makeQuestion(shape: PentatonicShape, quality: PentatonicQuality, rootNote: Note) -> PentatonicQuestion? {
        // Determine the anchorFret from the root note and the shape's root location on low E.
        // If the shape has a root on low E, use that; otherwise use the A-string root.
        let anchorFret: Int

        if let rootOffsetOnLowE = shape.rootOffsetOnLowE {
            // anchor = fret on low E that sounds rootNote - rootOffsetOnLowE
            let rawFretOnLowE = fretOnLowE(for: rootNote)
            // Try the base octave first, then +12 if needed
            let candidate = rawFretOnLowE - rootOffsetOnLowE
            anchorFret = candidate < 1 ? candidate + 12 : candidate
        } else if let rootOffsetOnA = shape.rootOffsetOnAString {
            let rawFretOnA = fretOnAString(for: rootNote)
            let candidate = rawFretOnA - rootOffsetOnA
            anchorFret = candidate < 1 ? candidate + 12 : candidate
        } else {
            return nil
        }

        let question = PentatonicQuestion(
            shape: shape,
            quality: quality,
            rootNote: rootNote,
            anchorFret: anchorFret
        )

        // Validate all frets are in playable range
        guard question.minFret >= 1, question.maxFret <= maxFret else { return nil }

        return question
    }
}
