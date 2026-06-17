//
//  ScaleStudySession.swift
//  Neck Practice
//
//  Manages the 4-scale study cycle: start → relative → parallel → relative.
//  Integrates rhythm assignment, BPM selection, and theory quizzing.
//

import Foundation
import Observation

// MARK: - Supporting Types

enum StudyPhase {
    case setup          // Tap "Start" to begin
    case practice       // Metronome playing, user plays along
    case quiz           // "What is the ___ of ___?"
    case reveal         // Answer shown, self-grade
    case roundComplete  // All 4 scales done
}

enum RhythmMode: CaseIterable, Codable {
    case random, fixed
}

enum Rhythm: CaseIterable, Codable {
    case quarter, eighth, triplet, sixteenth

    var label: String {
        switch self {
        case .quarter:   return "Quarter Notes"
        case .eighth:    return "Eighth Notes"
        case .triplet:   return "Triplets"
        case .sixteenth: return "16th Notes"
        }
    }

    var shortLabel: String {
        switch self {
        case .quarter:   return "1 per beat"
        case .eighth:    return "2 per beat"
        case .triplet:   return "3 per beat"
        case .sixteenth: return "4 per beat"
        }
    }

    /// Musical note symbol for display.
    var symbol: String {
        switch self {
        case .quarter:   return "♩"
        case .eighth:    return "♪"
        case .triplet:   return "♪³"
        case .sixteenth: return "𝅘𝅥𝅯"
        }
    }

    /// BPM range that keeps effective note speed reasonable.
    var bpmRange: ClosedRange<Int> {
        switch self {
        case .quarter:   return 80...130
        case .eighth:    return 65...100
        case .triplet:   return 70...110
        case .sixteenth: return 45...65
        }
    }

    /// Random BPM within the appropriate range, rounded to nearest 5.
    func randomBPM() -> Int {
        let raw = Int.random(in: bpmRange)
        return (raw / 5) * 5
    }
}

struct ScaleEntry: Identifiable {
    let id = UUID()
    let root: Note
    let isMajor: Bool
    /// How this scale relates to the previous one in the cycle.
    let relationship: String  // "Starting Scale", "Relative Minor", etc.
    /// When true, show the alternate string (used for parallel scales so you swap 5th↔6th).
    var useAlternateString: Bool = false

    var qualityLabel: String { isMajor ? "Major" : "Minor" }
    var fullLabel: String { "\(root.description) \(qualityLabel)" }

    /// Which string the default (non-alternate) position would use.
    private var defaultUses6th: Bool {
        let fret6 = fretOnLowE(for: root)
        let fret5 = fretOnAString(for: root)
        if fret6 == 0 { return true }
        if fret5 == 0 { return false }
        return fret6 <= fret5
    }

    /// Fret info for where to start on the 5th or 6th string.
    var rootFretInfo: String {
        let fret6 = fretOnLowE(for: root)
        let fret5 = fretOnAString(for: root)

        let use6th = useAlternateString ? !defaultUses6th : defaultUses6th

        if use6th {
            return fret6 == 0 ? "6th string · open" : "6th string · fret \(fret6)"
        } else {
            return fret5 == 0 ? "5th string · open" : "5th string · fret \(fret5)"
        }
    }
}

// MARK: - ScaleStudySession

@Observable
final class ScaleStudySession {

    // MARK: - Round State

    private(set) var round: [ScaleEntry] = []
    private(set) var currentIndex: Int = 0
    private(set) var phase: StudyPhase = .setup
    private(set) var roundNumber: Int = 0

    // MARK: - Tempo & Rhythm

    private(set) var rhythm: Rhythm = .quarter
    private(set) var bpm: Int = 100

    // MARK: - Settings

    var rhythmMode: RhythmMode = .random

    var fixedRhythm: Rhythm = .quarter {
        didSet {
            let range = fixedRhythm.bpmRange
            fixedBPM = max(range.lowerBound, min(range.upperBound, fixedBPM))
            fixedBPM = (fixedBPM / 5) * 5
        }
    }

    var fixedBPM: Int = 100
    var enabledRhythms: Set<Rhythm> = Set(Rhythm.allCases)

    // MARK: - Score

    private(set) var correctCount: Int = 0
    private(set) var totalQuizzed: Int = 0

    // MARK: - Computed Accessors

    var currentScale: ScaleEntry? {
        guard currentIndex < round.count else { return nil }
        return round[currentIndex]
    }

    var previousScale: ScaleEntry? {
        guard currentIndex > 0, currentIndex - 1 < round.count else { return nil }
        return round[currentIndex - 1]
    }

    /// The relationship label for the current quiz question.
    var quizRelationship: String {
        currentScale?.relationship ?? ""
    }

    // MARK: - Public API

    func startNewRound() {
        roundNumber += 1
        generateRound()

        switch rhythmMode {
        case .random:
            let eligible = Rhythm.allCases.filter { enabledRhythms.contains($0) }
            let pool = eligible.isEmpty ? [Rhythm.quarter] : eligible
            rhythm = pool.randomElement()!
            bpm = rhythm.randomBPM()
        case .fixed:
            rhythm = fixedRhythm
            bpm = fixedBPM
        }

        currentIndex = 0
        phase = .practice
    }

    /// User finished practicing the current scale.
    func donePracticing() {
        if currentIndex >= 3 {
            // Completed all 4 scales
            phase = .roundComplete
        } else {
            // Move to quiz for the next scale
            currentIndex += 1
            phase = .quiz
        }
    }

    /// User taps "Reveal" during quiz.
    func revealAnswer() {
        phase = .reveal
    }

    /// User self-grades: got it or missed it.
    func grade(correct: Bool) {
        totalQuizzed += 1
        if correct { correctCount += 1 }
        phase = .practice
    }

    /// Start a fresh round after round complete.
    func nextRound() {
        startNewRound()
    }

    // MARK: - Round Generation

    private func generateRound() {
        let startRoot = Note.allCases.randomElement()!
        let startMajor = Bool.random()

        var entries: [ScaleEntry] = []

        // Scale 1: Starting scale
        entries.append(ScaleEntry(root: startRoot, isMajor: startMajor, relationship: "Starting Scale"))

        // Scale 2: Relative of #1
        let prev1 = entries[0]
        let rel1Root: Note
        let rel1Major: Bool
        let rel1Label: String
        if prev1.isMajor {
            rel1Root = prev1.root.relativeMinor
            rel1Major = false
            rel1Label = "Relative Minor"
        } else {
            rel1Root = prev1.root.relativeMajor
            rel1Major = true
            rel1Label = "Relative Major"
        }
        entries.append(ScaleEntry(root: rel1Root, isMajor: rel1Major, relationship: rel1Label))

        // Scale 3: Parallel of #2 — swap to the other string (5th↔6th)
        let prev2 = entries[1]
        let par2Label = prev2.isMajor ? "Parallel Minor" : "Parallel Major"
        entries.append(ScaleEntry(root: prev2.root, isMajor: !prev2.isMajor, relationship: par2Label, useAlternateString: true))

        // Scale 4: Relative of #3
        let prev3 = entries[2]
        let rel3Root: Note
        let rel3Major: Bool
        let rel3Label: String
        if prev3.isMajor {
            rel3Root = prev3.root.relativeMinor
            rel3Major = false
            rel3Label = "Relative Minor"
        } else {
            rel3Root = prev3.root.relativeMajor
            rel3Major = true
            rel3Label = "Relative Major"
        }
        entries.append(ScaleEntry(root: rel3Root, isMajor: rel3Major, relationship: rel3Label))

        round = entries
    }
}
