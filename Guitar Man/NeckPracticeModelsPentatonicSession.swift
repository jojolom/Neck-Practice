//
//  PentatonicSession.swift
//  Neck Practice
//

import Foundation
import Observation

/// Drives the Pentatonic Trainer exercise.
///
/// Each question shows one of the 5 box shapes at a random key and fret position.
/// Two-step answer: first select the root dots on the fretboard, then name the root note.
@Observable
final class PentatonicSession {

    // MARK: - Settings

    /// nil = randomize quality per question
    var qualityFilter: PentatonicQuality? = nil
    /// Upper bound on fret positions shown
    var maxFret: Int = 12

    /// Number of root-note answer choices shown (4 to 12).
    var rootChoiceCount: Int = 4

    // MARK: - State

    private(set) var currentQuestion: PentatonicQuestion?
    /// Increments every time a new question is drawn; lets the view detect question changes
    /// even when the same position id is drawn back-to-back.
    private(set) var questionGeneration: Int = 0
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
        allPentatonicShapes
    }

    // MARK: - Public API

    func start() {
        guard currentQuestion == nil else { return }
        drawNext()
    }

    /// Step 1: score the root-dot selection. Returns true if the selected positions
    /// match the effective root positions exactly.
    @discardableResult
    func answerRoots(_ selected: Set<FretboardPosition>) -> Bool {
        guard let q = currentQuestion else { return false }
        let correct = selected == q.effectiveRootPositions
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
    /// Uses the effective root note (adjusted for major/minor quality).
    @discardableResult
    func answerRoot(_ note: Note) -> Bool {
        guard let q = currentQuestion else { return false }
        return note == q.effectiveRootNote
    }

    func advance() { drawNext() }

    func reset() {
        score = 0; streak = 0; totalAnswered = 0; weights = [:]
        drawNext()
    }

    // MARK: - Private

    private func drawNext() {
        // Only shapes that fit within frets 1...maxFret in some key (a low max fret rules some out).
        let candidates = pool.filter { !validRoots(for: $0).isEmpty }
        guard !candidates.isEmpty else { currentQuestion = nil; return }

        let weighted = candidates.flatMap { shape in
            Array(repeating: shape, count: weights[shape.id] ?? 1)
        }
        let filtered = weighted.filter { $0.id != currentQuestion?.shape.id }
        let source   = filtered.isEmpty ? weighted : filtered
        guard let shape = source.randomElement(),
              let rootNote = validRoots(for: shape).randomElement() else { currentQuestion = nil; return }

        // Pick a quality
        let quality: PentatonicQuality = qualityFilter ?? PentatonicQuality.allCases.randomElement()!

        currentQuestion = PentatonicQuestion(
            shape: shape,
            quality: quality,
            rootNote: rootNote,
            anchorFret: shape.anchorFret(forMinorRoot: rootNote)
        )
        questionGeneration += 1
    }

    /// Minor roots for which every fret of `shape` falls within 1...maxFret.
    private func validRoots(for shape: PentatonicShape) -> [Note] {
        Note.allCases.filter { root in
            let anchor = shape.anchorFret(forMinorRoot: root)
            return anchor + shape.minOffset >= 1 && anchor + shape.maxOffset <= maxFret
        }
    }
}
