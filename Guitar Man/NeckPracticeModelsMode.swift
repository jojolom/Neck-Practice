//
//  Mode.swift
//  Guitar Man
//
//  The seven diatonic modes: formulas, how each differs from major or natural minor, spelling,
//  and a three-notes-per-string fingering. Plus the Mode Quiz session.
//
//  The descriptions and song examples are a first draft for Daniel to review.
//

import Foundation
import Observation

// MARK: - Mode

enum Mode: Int, CaseIterable, Identifiable, Codable {
    case ionian, dorian, phrygian, lydian, mixolydian, aeolian, locrian

    var id: Int { rawValue }

    static let majorScale = [0, 2, 4, 5, 7, 9, 11]
    static let naturalMinorScale = [0, 2, 3, 5, 7, 8, 10]

    var name: String {
        switch self {
        case .ionian:     return "Ionian"
        case .dorian:     return "Dorian"
        case .phrygian:   return "Phrygian"
        case .lydian:     return "Lydian"
        case .mixolydian: return "Mixolydian"
        case .aeolian:    return "Aeolian"
        case .locrian:    return "Locrian"
        }
    }

    /// Which note of the major scale it starts on: 1 (Ionian) to 7 (Locrian).
    var degree: Int { rawValue + 1 }

    /// "2nd mode", for "D Dorian is the 2nd mode of C major".
    var ordinalName: String { "\(Interval.ordinal(degree)) mode" }

    /// Semitones above the root for each of the 7 notes.
    var semitones: [Int] {
        (0..<7).map { (Self.majorScale[(rawValue + $0) % 7] - Self.majorScale[rawValue] + 12) % 12 }
    }

    /// Scale degrees measured against major: 1 2 ♭3 4 5 6 ♭7 for Dorian.
    var degreeLabels: [String] {
        (0..<7).map { i in
            let difference = semitones[i] - Self.majorScale[i]
            return (difference < 0 ? "♭" : difference > 0 ? "♯" : "") + "\(i + 1)"
        }
    }

    /// Ionian, Lydian and Mixolydian have a major 3rd and are compared with the major scale;
    /// the rest with natural minor.
    var isMajorFamily: Bool { semitones[2] == 4 }

    var comparisonName: String { isMajorFamily ? "Major" : "Natural Minor" }

    private var comparisonScale: [Int] { isMajorFamily ? Self.majorScale : Self.naturalMinorScale }

    /// Degrees (0-based) where this mode differs from major / natural minor.
    var characteristicDegrees: [Int] {
        (0..<7).filter { semitones[$0] != comparisonScale[$0] }
    }

    /// How the characteristic degrees are written: "♯4", "♮6" (Dorian's 6th, raised from minor's ♭6).
    var characteristicLabels: [String] {
        characteristicDegrees.map { i in
            let label = degreeLabels[i]
            return label.first?.isNumber == true ? "♮" + label : label
        }
    }

    /// "Major with a ♯4", "Natural minor with a ♭2 and ♭5", "The major scale".
    var comparison: String {
        switch self {
        case .ionian:  return "The major scale itself"
        case .aeolian: return "The natural minor scale itself"
        default:
            let base = isMajorFamily ? "Major" : "Natural minor"
            return "\(base) with a " + characteristicLabels.joined(separator: " and ")
        }
    }

    /// What it sounds like and where you've heard it. Draft for Daniel to review.
    var sound: String {
        switch self {
        case .ionian:
            return "Bright, settled, and resolved. Every other mode is measured against it."
        case .dorian:
            return "Minor, but the raised 6th keeps it from sounding sad: soulful, jazzy, a little hopeful. Heard in \"Oye Como Va\" (Santana) and \"Scarborough Fair.\""
        case .phrygian:
            return "Minor with a half step just above the root. Dark and Spanish-sounding: flamenco and heavy metal riffs."
        case .lydian:
            return "Major with a raised 4th. Dreamy and floating: film scores, \"Flying in a Blue Dream\" (Joe Satriani), The Simpsons theme."
        case .mixolydian:
            return "Major with a flat 7th. Bluesy, classic-rock major: \"Sweet Home Alabama,\" \"Norwegian Wood.\""
        case .aeolian:
            return "Sad and serious: the natural minor scale. Heard in \"All Along the Watchtower.\""
        case .locrian:
            return "Its own root chord is diminished, so it never quite feels at home. Rare outside metal and jazz, but worth knowing."
        }
    }

    /// Quality of the triad built on the root.
    var tonicChord: String {
        switch self {
        case .ionian, .lydian, .mixolydian: return "Major"
        case .dorian, .phrygian, .aeolian:  return "Minor"
        case .locrian:                      return "Diminished"
        }
    }
}

// MARK: - ModeScale

/// One mode on one root, spelled: e.g. D Dorian = D E F G A B C, the notes of C major.
struct ModeScale: Equatable {
    let mode: Mode
    let root: Note
    /// The root's letter (0 = C … 6 = B) and accidental.
    let rootLetter: Int
    let rootAccidental: Int
    /// The parent major key's signature (D Dorian → C major, no sharps or flats).
    let parentKey: KeySignature

    /// Spells `mode` on `root` with whichever enharmonic name needs the fewest sharps or flats
    /// (D♭ Lydian, not C♯ Lydian). Ties go to the spelling the rest of the app uses for that key.
    init(mode: Mode, root: Note) {
        self.mode = mode
        self.root = root
        let parentPitchClass = (root.rawValue - Mode.majorScale[mode.rawValue] + 12) % 12
        let preferredLetter = root.keyLetterInfo(asMinor: !mode.isMajorFamily).letterIndex

        var best: (letter: Int, accidental: Int, key: KeySignature)? = nil
        for letter in 0..<7 {
            var accidental = root.rawValue - SpelledPitch.naturalSemitones[letter]
            if accidental > 6 { accidental -= 12 }
            if accidental < -6 { accidental += 12 }
            guard abs(accidental) <= 1 else { continue }
            let parentLetter = (letter - mode.rawValue + 7) % 7
            var parentAccidental = parentPitchClass - SpelledPitch.naturalSemitones[parentLetter]
            if parentAccidental > 6 { parentAccidental -= 12 }
            if parentAccidental < -6 { parentAccidental += 12 }
            guard let key = KeySignature.major(letter: parentLetter, accidental: parentAccidental) else { continue }
            if let current = best {
                let better = abs(key.fifths) < abs(current.key.fifths)
                    || (abs(key.fifths) == abs(current.key.fifths) && letter == preferredLetter)
                if !better { continue }
            }
            best = (letter, accidental, key)
        }
        let found = best ?? (letter: preferredLetter, accidental: 0, key: KeySignature.cMajor)
        rootLetter = found.letter
        rootAccidental = found.accidental
        parentKey = found.key
    }

    /// "D♭".
    var rootName: String {
        SpelledPitch.letterNames[rootLetter] + SpelledPitch.accidentalSymbol(rootAccidental)
    }

    /// "D♭ Lydian".
    var name: String { "\(rootName) \(mode.name)" }

    /// "A♭ Major", the key whose notes this mode uses.
    var parentKeyName: String { parentKey.majorKeyName }

    /// The scale written up an octave from the root (8 notes), starting in concert `octave`.
    func pitches(octave: Int = 3) -> [SpelledPitch] {
        (0...7).map { i in
            let letter = (rootLetter + i) % 7
            let wraps = (rootLetter + i) / 7
            return parentKey.pitch(letter: letter, octave: octave + wraps)
        }
    }

    /// The comparison scale (major or natural minor) on the same root, for "B♭ instead of B".
    func comparisonPitch(degree: Int, octave: Int = 3) -> SpelledPitch? {
        let scale = mode.isMajorFamily ? Mode.majorScale : Mode.naturalMinorScale
        let root = SpelledPitch(letter: rootLetter, accidental: rootAccidental, octave: octave)
        return SpelledPitch(midi: root.midi + scale[degree], letter: (rootLetter + degree) % 7)
    }

    /// Three notes per string from the root on the low E string, 6th string to 1st:
    /// each position paired with its degree index (0 = root).
    var threeNotesPerString: [(position: FretboardPosition, degree: Int)] {
        let rootFret = (root.rawValue - Note.e.rawValue + 12) % 12
        let rootMidi = 40 + rootFret
        let openMidi = [64, 59, 55, 50, 45, 40]
        var result: [(position: FretboardPosition, degree: Int)] = []
        for (row, stringIndex) in (0..<6).reversed().enumerated() {
            for k in 0..<3 {
                let n = row * 3 + k
                let midi = rootMidi + 12 * (n / 7) + mode.semitones[n % 7]
                result.append((FretboardPosition(stringIndex: stringIndex, fret: midi - openMidi[stringIndex]), n % 7))
            }
        }
        return result
    }
}

// MARK: - Mode Quiz

enum ModeQuestionKind: String, CaseIterable, Codable {
    /// The scale on the staff (and played): which mode is it?
    case nameIt
    /// "E Phrygian uses the notes of which major key?"
    case parentKey
    /// "Which describes Lydian?" — Major with a ♯4.
    case compare
}

struct ModeQuestion {
    let kind: ModeQuestionKind
    let scale: ModeScale
    let prompt: String
    let answer: String
    let choices: [String]
}

@Observable
final class ModeQuizSession {

    // MARK: - Settings

    var includeNameIt = true
    var includeParentKey = true
    var includeCompare = true
    /// Answer choices shown (3 to 7).
    var choiceCount = 4

    // MARK: - State

    private(set) var currentQuestion: ModeQuestion?
    private(set) var questionNumber = 0
    private(set) var score = 0
    private(set) var streak = 0
    private(set) var totalAnswered = 0

    var accuracy: Double {
        guard totalAnswered > 0 else { return 0 }
        return Double(score) / Double(totalAnswered)
    }

    private var kinds: [ModeQuestionKind] {
        var kinds: [ModeQuestionKind] = []
        if includeNameIt { kinds.append(.nameIt) }
        if includeParentKey { kinds.append(.parentKey) }
        if includeCompare { kinds.append(.compare) }
        return kinds.isEmpty ? [.nameIt] : kinds
    }

    // MARK: - Public API

    func start() { drawNext() }
    func advance() { drawNext() }

    func reset() {
        score = 0; streak = 0; totalAnswered = 0
        drawNext()
    }

    @discardableResult
    func answer(_ choice: String) -> Bool {
        guard let q = currentQuestion else { return false }
        let correct = choice == q.answer
        totalAnswered += 1
        if correct {
            score += 1
            streak += 1
        } else {
            streak = 0
        }
        return correct
    }

    // MARK: - Private

    private func drawNext() {
        let previous = currentQuestion?.scale.mode
        let modes = Mode.allCases.filter { $0 != previous }
        let mode = modes.randomElement() ?? .dorian
        let scale = ModeScale(mode: mode, root: Note.allCases.randomElement() ?? .c)
        let kind = kinds.randomElement() ?? .nameIt
        currentQuestion = Self.makeQuestion(kind: kind, scale: scale, choiceCount: max(3, min(7, choiceCount)))
        questionNumber += 1
    }

    static func makeQuestion(kind: ModeQuestionKind, scale: ModeScale, choiceCount: Int) -> ModeQuestion {
        switch kind {
        case .nameIt:
            let answer = scale.mode.name
            // Modes from the same family sound closest, so they make the trickiest wrong answers.
            let others = Mode.allCases.filter { $0 != scale.mode }
            let sameFamily = others.filter { $0.isMajorFamily == scale.mode.isMajorFamily }.shuffled()
            let otherFamily = others.filter { $0.isMajorFamily != scale.mode.isMajorFamily }.shuffled()
            let wrong = (sameFamily + otherFamily).map(\.name)
            return ModeQuestion(kind: kind, scale: scale, prompt: "Which mode is this?",
                                answer: answer, choices: ([answer] + wrong.prefix(choiceCount - 1)).shuffled())
        case .parentKey:
            let answer = scale.parentKeyName
            // Neighbouring keys on the circle of fifths, and the major key on the same root.
            var others: [String] = []
            let sameRoot = KeySignature.major(letter: scale.rootLetter, accidental: scale.rootAccidental)?.majorKeyName
            if let sameRoot, sameRoot != answer { others.append(sameRoot) }
            for step in [1, -1, 2, -2, 3, -3, 4, -4] {
                let fifths = scale.parentKey.fifths + step
                guard (-7...7).contains(fifths) else { continue }
                let name = KeySignature(fifths: fifths).majorKeyName
                if name != answer && !others.contains(name) { others.append(name) }
            }
            let wrong = Array(others.prefix(1)) + others.dropFirst().shuffled()
            return ModeQuestion(kind: kind, scale: scale,
                                prompt: "\(scale.name) uses the notes of which major key?",
                                answer: answer, choices: ([answer] + wrong.prefix(choiceCount - 1)).shuffled())
        case .compare:
            let answer = scale.mode.comparison
            let others = Mode.allCases.filter { $0 != scale.mode }.shuffled().map(\.comparison)
            return ModeQuestion(kind: kind, scale: scale, prompt: "Which describes \(scale.mode.name)?",
                                answer: answer, choices: ([answer] + others.prefix(choiceCount - 1)).shuffled())
        }
    }
}
