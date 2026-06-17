//
//  RomanNumeralSession.swift
//  Neck Practice
//
//  Drives the Roman Numeral exercise.
//

import Foundation
import Observation

@Observable
final class RomanNumeralSession {

    // MARK: - Settings

    /// nil = all keys
    var keyFilter: Note? = nil
    /// nil = both major and minor
    var scaleFilter: DiatonicScale? = nil
    /// Number of answer choices (3–7, default 4)
    var choiceCount: Int = 4
    /// When true, non-target cards show their chord names as hints.
    var easyMode: Bool = false

    // MARK: - State

    private(set) var currentQuestion: RomanNumeralQuestion?
    private(set) var score: Int = 0
    private(set) var streak: Int = 0
    private(set) var totalAnswered: Int = 0

    /// Weighted random: keys answered wrong get higher weight.
    private var keyWeights: [Int: Int] = [:]   // keyed by Note.rawValue

    // MARK: - Derived

    var accuracy: Double {
        guard totalAnswered > 0 else { return 0 }
        return Double(score) / Double(totalAnswered)
    }

    /// The correct answer string for the current question.
    var correctAnswer: String? {
        currentQuestion?.chordRootSpelled
    }

    // MARK: - Public API

    func start() {
        guard currentQuestion == nil else { return }
        drawNext()
    }

    /// Score the user's answer. Returns true if correct.
    @discardableResult
    func answer(_ choice: String) -> Bool {
        guard let q = currentQuestion else { return false }
        let correct = choice == q.chordRootSpelled
        totalAnswered += 1
        if correct {
            score += 1
            streak += 1
            keyWeights[q.key.rawValue] = max(1, (keyWeights[q.key.rawValue] ?? 1) - 1)
        } else {
            streak = 0
            keyWeights[q.key.rawValue] = (keyWeights[q.key.rawValue] ?? 1) + 3
        }
        return correct
    }

    /// Generate answer choices for the current question.
    func generateChoices() -> [String] {
        guard let q = currentQuestion else { return [] }
        return generateChordChoices(for: q)
    }

    func advance() { drawNext() }

    func reset() {
        score = 0; streak = 0; totalAnswered = 0; keyWeights = [:]
        drawNext()
    }

    // MARK: - Private

    private func drawNext() {
        // Pick a key (weighted)
        let keys: [Note] = {
            if let kf = keyFilter { return [kf] }
            return Note.allCases.map { $0 }
        }()

        let weightedKeys = keys.flatMap { note in
            Array(repeating: note, count: keyWeights[note.rawValue] ?? 1)
        }
        let filteredKeys = weightedKeys.filter { $0 != currentQuestion?.key }
        let keySource = filteredKeys.isEmpty ? weightedKeys : filteredKeys
        guard let key = keySource.randomElement() else { currentQuestion = nil; return }

        // Pick a scale
        let scale: DiatonicScale = scaleFilter ?? DiatonicScale.allCases.randomElement()!

        // Pick a degree (1–7), avoiding exact repeat
        let degrees = Array(1...7)
        let filteredDegrees = degrees.filter { d in
            guard let prev = currentQuestion else { return true }
            return !(d == prev.degree && key == prev.key && scale == prev.scale)
        }
        let degreeSource = filteredDegrees.isEmpty ? degrees : filteredDegrees
        guard let degree = degreeSource.randomElement() else { currentQuestion = nil; return }

        currentQuestion = RomanNumeralQuestion(key: key, scale: scale, degree: degree)
    }

    private func generateChordChoices(for q: RomanNumeralQuestion) -> [String] {
        let correct = q.chordRootSpelled
        // Pull distractors from other root note names in the same key/scale (enharmonically correct)
        var distractors = q.allChordRootsInKey.filter { $0 != correct }.shuffled()
        let needed = min(choiceCount - 1, distractors.count)
        distractors = Array(distractors.prefix(needed))
        return ([correct] + distractors).shuffled()
    }
}
