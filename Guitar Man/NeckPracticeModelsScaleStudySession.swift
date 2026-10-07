//
//  ScaleStudySession.swift
//  Neck Practice
//
//  Manages the 4-scale study cycle: start → relative → parallel → relative.
//  Strings follow a 6-5-5-6 or 5-6-6-5 pattern (X, Y, Y, X): the relative moves to
//  the opposite string, the parallel stays on the same string as the scale before it.
//  Keys are chosen so every scale's root sits between frets 2 and 12 on its string (no
//  open-string positions). Tempos keep every rhythm at or under 3 notes a second.
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

    /// Notes played per beat.
    var notesPerBeat: Int {
        switch self {
        case .quarter:   return 1
        case .eighth:    return 2
        case .triplet:   return 3
        case .sixteenth: return 4
        }
    }

    /// BPM range for this rhythm: the top of each keeps you at or under 3 notes a second
    /// (quarters stop at 2, since 180 BPM quarters would be a different exercise).
    var bpmRange: ClosedRange<Int> {
        switch self {
        case .quarter:   return 60...120
        case .eighth:    return 50...90
        case .triplet:   return 40...60
        case .sixteenth: return 40...45
        }
    }

    /// `bpm` moved into this rhythm's range, on a multiple of 5.
    func clamped(_ bpm: Int) -> Int {
        (max(bpmRange.lowerBound, min(bpmRange.upperBound, bpm)) / 5) * 5
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
    /// Which string to play this scale on: 5 (A string) or 6 (low E).
    let string: Int

    /// Lowest and highest fret a scale's root may sit on: no open-string positions.
    static let fretRange = 2...12

    /// The fret the root is played at on `string`: an open-string root (fret 0) is played at
    /// the 12th fret instead.
    var rootFret: Int { Self.rootFret(of: root, onString: string) }

    static func rootFret(of root: Note, onString string: Int) -> Int {
        let fret = string == 6 ? fretOnLowE(for: root) : fretOnAString(for: root)
        return fret == 0 ? 12 : fret
    }

    var qualityLabel: String { isMajor ? "Major" : "Minor" }
    /// Key name with conventional spelling, e.g. "Bb Major" rather than "A# Major".
    var fullLabel: String { "\(root.keyName(asMinor: !isMajor)) \(qualityLabel)" }

    /// Fret info for where to start on the assigned string.
    var rootFretInfo: String {
        "\(string == 6 ? "6th" : "5th") string · fret \(rootFret)"
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
        didSet { fixedBPM = fixedRhythm.clamped(fixedBPM) }
    }

    /// Always within `fixedRhythm`'s range (a Daily Practice override can ask for anything).
    var fixedBPM: Int = 100 {
        didSet {
            let clamped = fixedRhythm.clamped(fixedBPM)
            if clamped != fixedBPM { fixedBPM = clamped }
        }
    }

    /// Also click each note of the rhythm (quietly) between the beats.
    var clickSubdivisions = false
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
        // Every starting key, quality and string pattern whose four scales all have their
        // roots within the fret range; pick one at random.
        var candidates: [[ScaleEntry]] = []
        for root in Note.allCases {
            for isMajor in [true, false] {
                for x in [6, 5] {
                    let chain = Self.chain(startRoot: root, startMajor: isMajor, startString: x)
                    if chain.allSatisfy({ ScaleEntry.fretRange.contains($0.rootFret) }) {
                        candidates.append(chain)
                    }
                }
            }
        }
        let entries = candidates.randomElement()
            ?? Self.chain(startRoot: .c, startMajor: true, startString: 5)
        let x = entries[0].string, y = entries[1].string

        #if DEBUG
        assert(entries.map(\.string) == [x, y, y, x], "String pattern must be X, Y, Y, X")
        for string in [5, 6] {
            let onString = entries.filter { $0.string == string }
            assert(onString.count == 2 && onString.filter(\.isMajor).count == 1,
                   "Each string needs exactly one major and one minor scale")
        }
        #endif

        round = entries
    }

    /// Starting scale → its relative → that one's parallel → that one's relative, on strings
    /// X, Y, Y, X.
    static func chain(startRoot: Note, startMajor: Bool, startString x: Int) -> [ScaleEntry] {
        let y = x == 6 ? 5 : 6
        func relative(of scale: ScaleEntry, string: Int) -> ScaleEntry {
            scale.isMajor
                ? ScaleEntry(root: scale.root.relativeMinor, isMajor: false, relationship: "Relative Minor", string: string)
                : ScaleEntry(root: scale.root.relativeMajor, isMajor: true, relationship: "Relative Major", string: string)
        }
        let first = ScaleEntry(root: startRoot, isMajor: startMajor, relationship: "Starting Scale", string: x)
        let second = relative(of: first, string: y)
        let third = ScaleEntry(root: second.root, isMajor: !second.isMajor,
                               relationship: second.isMajor ? "Parallel Minor" : "Parallel Major", string: y)
        return [first, second, third, relative(of: third, string: x)]
    }
}
