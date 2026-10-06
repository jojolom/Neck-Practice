//
//  IntervalSession.swift
//  Guitar Man
//
//  Drives the Interval Trainer. Each question writes two notes on a staff in a random key;
//  you name the interval (multiple choice). Get it right and the fretboard opens: the first
//  note is placed at a random spot and you find the second — any spot at the right pitch
//  counts, so a different fingering gets drilled each time. Sometimes the higher note comes
//  first, to practise measuring from the lower note. A bonus question can follow: invert it,
//  or add / remove an octave.
//

import Foundation
import Observation

// MARK: - IntervalQuestion

struct IntervalQuestion {
    let keySignature: KeySignature
    let lower: SpelledPitch
    let upper: SpelledPitch
    let interval: Interval
    /// The higher note is written (and played) first.
    let descending: Bool
    let choices: [Interval]

    /// The notes in the order they're written.
    var first: SpelledPitch { descending ? upper : lower }
    var second: SpelledPitch { descending ? lower : upper }
}

// MARK: - IntervalBonus

/// The follow-up question after finding the interval on the neck.
struct IntervalBonus {
    enum Kind {
        case inversion   // a major 6th inverts to a…
        case compound    // a major 3rd plus an octave is a…
        case simple      // a major 10th minus an octave is a…
    }

    let kind: Kind
    let from: Interval
    let answer: Interval
    let choices: [Interval]

    var prompt: String {
        switch kind {
        case .inversion: return "Flip it: what does a \(from.name.lowercased()) invert to?"
        case .compound:  return "Add an octave: a \(from.name.lowercased()) becomes a…"
        case .simple:    return "Take away the octave: a \(from.name.lowercased()) becomes a…"
        }
    }

    var hint: String {
        switch kind {
        case .inversion: return "Inversions add up to 9. Major ↔ minor, augmented ↔ diminished, perfect stays perfect."
        case .compound:  return "Add 7 to the number. The quality stays the same."
        case .simple:    return "Subtract 7 from the number. The quality stays the same."
        }
    }
}

// MARK: - IntervalSession

@Observable
final class IntervalSession {

    // MARK: - Settings

    /// Most sharps or flats in the key signature (0 = C major only, up to 6).
    var maxAccidentals: Int = 4
    /// Sometimes write the higher note first.
    var includeDescending: Bool = true
    /// Add 9ths through 13ths to the pool.
    var includeCompound: Bool = false
    /// Follow some questions with an inversion / compound question.
    var bonusQuestions: Bool = true
    /// Answer choices shown (3 to 6).
    var choiceCount: Int = 4

    // MARK: - State

    private(set) var currentQuestion: IntervalQuestion?
    /// Goes up with every new question, so views can reset when it changes.
    private(set) var questionNumber: Int = 0
    /// Where the first-written note sits on the neck once the fretboard opens.
    private(set) var anchorPosition: FretboardPosition?
    /// Every spot (frets 0–12) where the second note can be played.
    private(set) var targetPositions: Set<FretboardPosition> = []
    /// The bonus question for this round, if there is one.
    private(set) var bonus: IntervalBonus?

    private(set) var score: Int = 0
    private(set) var streak: Int = 0
    private(set) var totalAnswered: Int = 0

    /// Wrong-answer boost per interval (shortName).
    private var weights: [String: Int] = [:]

    var accuracy: Double {
        guard totalAnswered > 0 else { return 0 }
        return Double(score) / Double(totalAnswered)
    }

    private var pool: [Interval] {
        includeCompound ? Interval.simplePool + Interval.compoundPool : Interval.simplePool
    }

    /// Fret range the fretboard step uses.
    static let maxFret = 12

    // MARK: - Public API

    func start() { drawNext() }

    func advance() { drawNext() }

    func reset() {
        score = 0; streak = 0; totalAnswered = 0; weights = [:]
        drawNext()
    }

    /// Step 1: name the interval. Returns true if correct.
    @discardableResult
    func answerInterval(_ interval: Interval) -> Bool {
        guard let q = currentQuestion else { return false }
        let correct = interval == q.interval
        record(correct)
        let key = q.interval.shortName
        weights[key] = correct ? max(1, (weights[key] ?? 1) - 1) : (weights[key] ?? 1) + 3
        return correct
    }

    /// Step 2: find the second note on the neck. Returns true if the tapped spot has its pitch.
    @discardableResult
    func answerPosition(_ position: FretboardPosition) -> Bool {
        let correct = targetPositions.contains(position)
        record(correct)
        return correct
    }

    /// Step 3 (sometimes): the bonus question. Returns true if correct.
    @discardableResult
    func answerBonus(_ interval: Interval) -> Bool {
        guard let bonus else { return false }
        let correct = interval == bonus.answer
        record(correct)
        return correct
    }

    // MARK: - Private

    private func record(_ correct: Bool) {
        totalAnswered += 1
        if correct {
            score += 1
            streak += 1
        } else {
            streak = 0
        }
    }

    private func drawNext() {
        let candidates = pool
        let weighted = candidates.flatMap { Array(repeating: $0, count: weights[$0.shortName] ?? 1) }
        let fresh = weighted.filter { $0 != currentQuestion?.interval }
        let source = fresh.isEmpty ? weighted : fresh

        for _ in 0..<200 {
            guard let interval = source.randomElement(),
                  let question = makeQuestion(for: interval),
                  let placement = Self.placement(for: question) else { continue }
            currentQuestion = question
            anchorPosition = placement.anchor
            targetPositions = placement.targets
            bonus = bonusQuestions && Bool.random() ? Self.makeBonus(for: interval) : nil
            questionNumber += 1
            return
        }
        currentQuestion = nil
        anchorPosition = nil
        targetPositions = []
        bonus = nil
    }

    /// A random key and a lower note from its scale, kept to the staff and the first 12 frets
    /// (written A3 to B5, concert A2 to B4), or nil if this try didn't fit.
    private func makeQuestion(for interval: Interval) -> IntervalQuestion? {
        let limit = max(0, min(6, maxAccidentals))
        let key = KeySignature(fifths: Int.random(in: -limit...limit))
        let letter = Int.random(in: 0..<7)
        let octaves = (2...4).filter { octave in
            let lower = key.pitch(letter: letter, octave: octave)
            return lower.staffPosition >= -4 && lower.staffPosition + interval.number - 1 <= 11
        }
        guard let octave = octaves.randomElement() else { return nil }
        let lower = key.pitch(letter: letter, octave: octave)
        // Single sharps and flats only: no double accidentals in the answer.
        guard let upper = lower.transposed(by: interval), abs(upper.accidental) <= 1 else { return nil }

        let descending = includeDescending && Bool.random()
        let count = max(3, min(6, choiceCount))
        let choices = ([interval] + interval.distractors(count - 1)).shuffled()
        return IntervalQuestion(keySignature: key, lower: lower, upper: upper, interval: interval,
                                descending: descending, choices: choices)
    }

    /// Places the first-written note somewhere on the neck from which the second is in reach
    /// (within 4 frets), and lists every spot that plays the second.
    static func placement(for question: IntervalQuestion) -> (anchor: FretboardPosition, targets: Set<FretboardPosition>)? {
        let all = positions(frets: 0...maxFret)
        let anchors = all.filter { $0.midiNote == question.first.midi }
        let targets = all.filter { $0.midiNote == question.second.midi }
        guard !anchors.isEmpty, !targets.isEmpty else { return nil }
        let reachable = anchors.filter { anchor in
            targets.contains { abs($0.fret - anchor.fret) <= 4 }
        }
        guard let anchor = (reachable.isEmpty ? anchors : reachable).randomElement() else { return nil }
        return (anchor, Set(targets))
    }

    static func makeBonus(for interval: Interval) -> IntervalBonus? {
        let kind: IntervalBonus.Kind
        let answer: Interval
        if interval.isCompound {
            kind = .simple
            answer = interval.simple
        } else if let inversion = interval.inversion, let compound = interval.compound {
            if Bool.random() {
                kind = .inversion
                answer = inversion
            } else {
                kind = .compound
                answer = compound
            }
        } else {
            return nil   // an octave: nothing interesting to ask
        }

        // The classic slip for an inversion is flipping the number but not the quality.
        var wrong: [Interval] = []
        if kind == .inversion {
            let unflipped = Interval(interval.quality, answer.number)
            if unflipped.isValid && unflipped != answer { wrong.append(unflipped) }
        }
        for other in answer.distractors(4) where !wrong.contains(other) && wrong.count < 3 {
            wrong.append(other)
        }
        return IntervalBonus(kind: kind, from: interval, answer: answer,
                             choices: ([answer] + wrong.prefix(3)).shuffled())
    }
}
