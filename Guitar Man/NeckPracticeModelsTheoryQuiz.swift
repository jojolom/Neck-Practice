//
//  TheoryQuiz.swift
//  Guitar Man
//
//  Theory Basics: multiple-choice questions on the circle of fifths, key signatures, relative
//  and parallel keys, and scales, drawn at random from the topics switched on in Settings.
//  Every key is a KeySignature plus major or minor, so names are spelled from the signature
//  (F♯ major's relative is D♯ minor, never E♭ minor). No UI here, so every question can be
//  checked offline — see scripts/theory-quiz-check.swift.
//

import Foundation
import Observation

// MARK: - TheoryTopic

enum TheoryTopic: String, CaseIterable, Identifiable, Codable {
    case circleOfFifths, keySignatures, relativeKeys, scales

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .circleOfFifths: return "Circle of Fifths"
        case .keySignatures:  return "Key Signatures"
        case .relativeKeys:   return "Relative & Parallel Keys"
        case .scales:         return "Scales"
        }
    }
}

// MARK: - TheoryKey

/// A major or natural-minor key, named by its signature.
struct TheoryKey: Equatable {
    let signature: KeySignature
    let isMinor: Bool

    init(fifths: Int, isMinor: Bool) {
        signature = KeySignature(fifths: fifths)
        self.isMinor = isMinor
    }

    var fifths: Int { signature.fifths }

    var tonic: (letter: Int, accidental: Int) {
        isMinor ? signature.minorTonic : signature.majorTonic
    }

    /// "E♭".
    var tonicName: String { Self.noteName(letter: tonic.letter, accidental: tonic.accidental) }

    /// "E♭ Major", "C Minor".
    var name: String { isMinor ? signature.minorKeyName : signature.majorKeyName }

    /// "E♭ major scale", "C natural minor scale": scale questions say natural minor, so the
    /// harmonic minor's raised 7th can't also count as right.
    var scaleTitle: String { "\(tonicName) \(isMinor ? "natural minor" : "major") scale" }

    /// As written on the wheel: "E♭", "Cm".
    var shortName: String { tonicName + (isMinor ? "m" : "") }

    /// The tonic's pitch class, so F♯ major and G♭ major are never both answer choices.
    var tonicPitchClass: Int { (SpelledPitch.naturalSemitones[tonic.letter] + tonic.accidental + 12) % 12 }

    /// The scale's seven notes from the tonic, as (letter, accidental).
    var scale: [(letter: Int, accidental: Int)] {
        (0..<7).map { i in
            let letter = (tonic.letter + i) % 7
            return (letter, signature.accidental(forLetter: letter))
        }
    }

    /// "A", "B", "C♯", …
    var scaleNames: [String] { scale.map { Self.noteName(letter: $0.letter, accidental: $0.accidental) } }

    /// Slot on the circle of fifths: 0 = C at the top, counting clockwise.
    var wheelPosition: Int { ((fifths % 12) + 12) % 12 }

    /// Same signature, other mode.
    var relative: TheoryKey { TheoryKey(fifths: fifths, isMinor: !isMinor) }

    /// Same tonic, other mode: the minor key has three more flats (three fewer sharps).
    /// Nil past seven sharps or flats (D♭ minor, G♯ major).
    var parallel: TheoryKey? {
        let f = fifths + (isMinor ? 3 : -3)
        return (-7...7).contains(f) ? TheoryKey(fifths: f, isMinor: !isMinor) : nil
    }

    /// One key on each of the 12 notes, spelled the way the rest of the app spells it
    /// (D♭ to F♯ major, E♭ to G♯ minor).
    static func usual(isMinor: Bool) -> [TheoryKey] {
        Note.allCases.map { TheoryKey(fifths: KeySignature(root: $0, isMinor: isMinor).fifths, isMinor: isMinor) }
    }

    /// The key on wheel slot `position` as the circle usually names it: F♯ and D♯m at 6, D♭ and B♭m at 7.
    static func onWheel(_ position: Int, isMinor: Bool) -> TheoryKey {
        let p = ((position % 12) + 12) % 12
        return TheoryKey(fifths: p <= 6 ? p : p - 12, isMinor: isMinor)
    }

    static func noteName(letter: Int, accidental: Int) -> String {
        SpelledPitch.letterNames[letter] + SpelledPitch.accidentalSymbol(accidental)
    }
}

extension KeySignature {
    /// "No sharps or flats", "1 sharp", "3 flats".
    var countName: String {
        switch fifths {
        case 0:  return "No sharps or flats"
        case 1:  return "1 sharp"
        case -1: return "1 flat"
        default: return fifths > 0 ? "\(fifths) sharps" : "\(-fifths) flats"
        }
    }

    /// The sharps or flats in the order they're written: ["F♯", "C♯"].
    var accidentalNames: [String] {
        let letters = fifths > 0 ? Self.sharpLetters.prefix(fifths) : Self.flatLetters.prefix(-fifths)
        return letters.map { TheoryKey.noteName(letter: $0, accidental: fifths > 0 ? 1 : -1) }
    }
}

// MARK: - KeyRelationship

/// How two keys are related, for "E♭ Major and C Minor are…".
enum KeyRelationship: CaseIterable {
    case relative, parallel, neighbors, enharmonic

    var choice: String {
        switch self {
        case .relative:   return "Relative: same key signature"
        case .parallel:   return "Parallel: same starting note"
        case .neighbors:  return "Next to each other on the circle"
        case .enharmonic: return "Enharmonic: same sound, different name"
        }
    }

    /// The relationship between `a` and `b`, or nil if they're none of these.
    static func between(_ a: TheoryKey, _ b: TheoryKey) -> KeyRelationship? {
        if a.isMinor != b.isMinor {
            if a.fifths == b.fifths { return .relative }
            if a.tonic == b.tonic { return .parallel }
            return nil
        }
        if a.fifths != b.fifths && a.tonicPitchClass == b.tonicPitchClass { return .enharmonic }
        if abs(a.fifths - b.fifths) == 1 { return .neighbors }
        return nil
    }
}

// MARK: - Questions

enum TheoryQuestionKind: Equatable {
    /// The wheel shows `key`: which key is `step` slices clockwise (1) or counterclockwise (−1)?
    case circleNeighbor(key: TheoryKey, step: Int)
    /// The wheel shows `key`: which key is in the other ring on its slice (its relative)?
    case circleRelative(key: TheoryKey)
    /// How many sharps or flats does `key` have?
    case accidentalCount(key: TheoryKey)
    /// Which major (or minor) key has `key`'s signature?
    case keyForSignature(key: TheoryKey)
    /// Which is the `n`th sharp (or flat), 1–7?
    case nthAccidental(n: Int, sharps: Bool)
    /// Which notes are sharp (or flat) in `key`? Never a key with none.
    case accidentalsInKey(key: TheoryKey)
    case relativeKey(key: TheoryKey)
    /// Only for a key whose parallel exists.
    case parallelKey(key: TheoryKey)
    /// Are `first` and `second` relative, parallel, neighbours on the circle, or enharmonic?
    case relationship(first: TheoryKey, second: TheoryKey)
    case scaleNotes(key: TheoryKey)
    /// The `degree`th note (2–7) of `key`.
    case scaleDegree(key: TheoryKey, degree: Int)
    /// Which notes of `key` (a major key with a parallel minor) go down in its parallel minor?
    case majorToMinor(key: TheoryKey)
    case stepPattern(isMinor: Bool)

    var topic: TheoryTopic {
        switch self {
        case .circleNeighbor, .circleRelative:                                     return .circleOfFifths
        case .accidentalCount, .keyForSignature, .nthAccidental, .accidentalsInKey: return .keySignatures
        case .relativeKey, .parallelKey, .relationship:                            return .relativeKeys
        case .scaleNotes, .scaleDegree, .majorToMinor, .stepPattern:               return .scales
        }
    }
}

/// The circle of fifths for a question: the slice shown and the slice asked about.
struct TheoryWheel: Equatable {
    struct Slice: Equatable {
        /// 0 = C at the top, clockwise.
        let position: Int
        /// Inner ring (minor keys) or outer (major).
        let isMinor: Bool
        let label: String
    }

    let shown: Slice
    /// Drawn as "?" until answered; its label is the answer.
    let asked: Slice
}

extension TheoryWheel.Slice {
    init(_ key: TheoryKey) {
        self.init(position: key.wheelPosition, isMinor: key.isMinor, label: key.shortName)
    }
}

struct TheoryQuestion {
    let kind: TheoryQuestionKind
    let prompt: String
    let answer: String
    let choices: [String]
    /// Shown once answered.
    let explanation: String
    /// For circle-of-fifths questions.
    var wheel: TheoryWheel? = nil
}

extension TheoryQuestion {

    static let majorSteps = "W W H W W W H"
    static let minorSteps = "W H W W H W W"

    static func make(_ kind: TheoryQuestionKind) -> TheoryQuestion {
        switch kind {
        case .circleNeighbor(let key, let step):
            let answer = TheoryKey(fifths: key.fifths + step, isMinor: key.isMinor)
            let wrong = [-step, 2 * step, -2 * step, 3 * step, -3 * step]
                .map { TheoryKey.onWheel(key.fifths + $0, isMinor: key.isMinor) }
            let move = step > 0
                ? "One slice clockwise is a fifth up: one more sharp or one fewer flat."
                : "One slice counterclockwise is a fifth down: one more flat or one fewer sharp."
            return TheoryQuestion(
                kind: kind, prompt: "Which key goes in the ? slice?",
                answer: answer.name, choices: keyChoices(answer, wrong),
                explanation: "\(move) \(key.name) has \(key.signature.countName.lowercased()); \(answer.name) has \(answer.signature.countName.lowercased()).",
                wheel: TheoryWheel(shown: .init(key), asked: .init(answer)))

        case .circleRelative(let key):
            let answer = key.relative
            var wrong: [TheoryKey] = key.parallel.map { [$0] } ?? []
            wrong += [1, -1, 2, -2].map { TheoryKey.onWheel(key.fifths + $0, isMinor: answer.isMinor) }
            let ring = answer.isMinor ? "The inner ring holds the minor keys." : "The outer ring holds the major keys."
            return TheoryQuestion(
                kind: kind, prompt: "\(ring) Which key goes in the ? slice?",
                answer: answer.name, choices: keyChoices(answer, wrong),
                explanation: "\(relativeSentence(key)) Relative keys share a slice because they share a key signature: \(key.signature.countName.lowercased()).",
                wheel: TheoryWheel(shown: .init(key), asked: .init(answer)))

        case .accidentalCount(let key):
            let f = key.fifths
            let wrong = [-f, f + 1, f - 1, f + 2, f - 2]
                .filter { $0 != f && (-7...7).contains($0) }
                .map { KeySignature(fifths: $0).countName }
            return TheoryQuestion(
                kind: kind, prompt: "How many sharps or flats does \(key.name) have?",
                answer: key.signature.countName, choices: choices(key.signature.countName, wrong),
                explanation: signatureSentence(key))

        case .keyForSignature(let key):
            let f = key.fifths
            let wrong = [-f, f + 1, f - 1, f + 2, f - 2]
                .filter { $0 != f && (-7...7).contains($0) }
                .map { TheoryKey(fifths: $0, isMinor: key.isMinor) }
            return TheoryQuestion(
                kind: kind,
                prompt: "Which \(key.isMinor ? "minor" : "major") key has \(key.signature.countName.lowercased())?",
                answer: key.name, choices: keyChoices(key, wrong),
                explanation: signatureSentence(key))

        case .nthAccidental(let n, let sharps):
            let names = KeySignature(fifths: sharps ? 7 : -7).accidentalNames
            let answer = names[n - 1]
            let wrong = [n, n - 2, n + 1, n - 3, n + 2, n - 4]
                .filter { (0..<7).contains($0) }
                .map { names[$0] }
            let order = sharps
                ? "Sharps always come in this order: \(names.joined(separator: " ")) (Father Charles Goes Down And Ends Battle)."
                : "Flats always come in this order: \(names.joined(separator: " ")), the sharps' order backwards (Battle Ends And Down Goes Charles's Father)."
            return TheoryQuestion(
                kind: kind,
                prompt: "Which is the \(ordinal(n)) \(sharps ? "sharp" : "flat") in a key signature?",
                answer: answer, choices: choices(answer, wrong), explanation: order)

        case .accidentalsInKey(let key):
            let f = key.fifths
            let sign = f > 0 ? 1 : -1
            let n = abs(f)
            let answer = key.signature.accidentalNames.joined(separator: ", ")
            let wrong = [sign * (n - 1), sign * (n + 1), -f, sign * (n + 2)]
                .filter { $0 != 0 && $0 != f && (-7...7).contains($0) }
                .map { KeySignature(fifths: $0).accidentalNames.joined(separator: ", ") }
            let kindName = f > 0 ? "sharp" : "flat"
            let order = KeySignature(fifths: 7 * sign).accidentalNames.joined(separator: " ")
            return TheoryQuestion(
                kind: kind, prompt: "Which notes are \(kindName) in \(key.name)?",
                answer: answer, choices: choices(answer, wrong),
                explanation: "\(key.name) has \(key.signature.countName.lowercased()). They're always the first ones in the order \(order).")

        case .relativeKey(let key):
            let answer = key.relative
            var wrong: [TheoryKey] = key.parallel.map { [$0] } ?? []
            // 6 slices round is three half steps the wrong way: E♭ minor for C major.
            wrong += [1, -1, 6, 2].map { TheoryKey.onWheel(key.fifths + $0, isMinor: answer.isMinor) }
            return TheoryQuestion(
                kind: kind, prompt: "What is the relative \(answer.isMinor ? "minor" : "major") of \(key.name)?",
                answer: answer.name, choices: keyChoices(answer, wrong),
                explanation: "\(relativeSentence(key)) Both have \(key.signature.countName.lowercased()).")

        case .parallelKey(let key):
            guard let answer = key.parallel else { return make(.relativeKey(key: key)) }
            let wrong = [key.relative] + [1, -1, 2].map { TheoryKey.onWheel(answer.fifths + $0, isMinor: answer.isMinor) }
            return TheoryQuestion(
                kind: kind, prompt: "What is the parallel \(answer.isMinor ? "minor" : "major") of \(key.name)?",
                answer: answer.name, choices: keyChoices(answer, wrong),
                explanation: "Parallel keys start on the same note. \(key.name) has \(key.signature.countName.lowercased()); \(answer.name) has \(answer.signature.countName.lowercased()).")

        case .relationship(let first, let second):
            let relation = KeyRelationship.between(first, second) ?? .neighbors
            let a = first.signature.countName.lowercased(), b = second.signature.countName.lowercased()
            let why: String
            switch relation {
            case .relative:   why = "They share a key signature (\(a)) but start on different notes."
            case .parallel:   why = "They start on the same note, with different key signatures: \(a) and \(b)."
            case .neighbors:  why = "They're one slice apart on the circle of fifths: \(a) and \(b)."
            case .enharmonic: why = "They sound the same and use the same frets, spelled two ways: \(a) and \(b)."
            }
            return TheoryQuestion(
                kind: kind, prompt: "\(first.name) and \(second.name) are…",
                answer: relation.choice, choices: KeyRelationship.allCases.map(\.choice).shuffled(),
                explanation: why)

        case .scaleNotes(let key):
            let answer = key.scaleNames.joined(separator: " ")
            var wrong: [String] = key.parallel.map { [$0.scaleNames.joined(separator: " ")] } ?? []
            // The same scale with one note a half step off: its 3rd, 4th, 6th or 7th.
            for degree in [2, 3, 5, 6].shuffled() {
                var names = key.scaleNames
                let note = key.scale[degree]
                names[degree] = TheoryKey.noteName(letter: note.letter, accidental: altered(note))
                wrong.append(names.joined(separator: " "))
            }
            return TheoryQuestion(
                kind: kind, prompt: "Which notes are in the \(key.scaleTitle)?",
                answer: answer, choices: choices(answer, wrong), explanation: signatureSentence(key))

        case .scaleDegree(let key, let degree):
            let names = key.scaleNames
            let i = degree - 1
            let note = key.scale[i]
            let answer = names[i]
            let wrong = [TheoryKey.noteName(letter: note.letter, accidental: altered(note)),
                         names[i - 1], names[(i + 1) % 7]]
            return TheoryQuestion(
                kind: kind, prompt: "What is the \(ordinal(degree)) note of the \(key.scaleTitle)?",
                answer: answer, choices: choices(answer, wrong),
                explanation: "\(key.name): \(names.joined(separator: " ")). Count \(names[0]) as 1.")

        case .majorToMinor(let key):
            guard let minor = key.parallel else { return make(.scaleNotes(key: key)) }
            let names = key.scaleNames
            func list(_ degrees: [Int]) -> String { degrees.map { names[$0 - 1] }.joined(separator: ", ") }
            let answer = list([3, 6, 7])
            let wrong = [[3, 7], [3, 6], [2, 3, 6], [3, 4, 7], [6, 7]].shuffled().map(list)
            return TheoryQuestion(
                kind: kind, prompt: "From \(key.name) to \(minor.name), which notes go down a half step?",
                answer: answer, choices: choices(answer, wrong),
                explanation: "Natural minor lowers the 3rd, 6th and 7th notes: \(minor.name) is \(minor.scaleNames.joined(separator: " ")).")

        case .stepPattern(let isMinor):
            let answer = isMinor ? minorSteps : majorSteps
            // The other one first, then three modes' patterns (Lydian, Dorian, Mixolydian).
            let wrong = [isMinor ? majorSteps : minorSteps] + ["W W W H W W H", "W H W W W H W", "W W H W W H W"].shuffled()
            return TheoryQuestion(
                kind: kind, prompt: "What is the step pattern of the \(isMinor ? "natural minor" : "major") scale?",
                answer: answer, choices: choices(answer, wrong),
                explanation: "W is a whole step (2 frets), H a half step (1 fret). Major: \(majorSteps). Natural minor: \(minorSteps).")
        }
    }

    /// A random question on `topic`.
    static func randomKind(in topic: TheoryTopic) -> TheoryQuestionKind {
        let isMinor = Bool.random()
        let keys = TheoryKey.usual(isMinor: isMinor)
        let key = keys.randomElement() ?? TheoryKey(fifths: 0, isMinor: isMinor)
        func pick(_ pool: [TheoryKey]) -> TheoryKey { pool.randomElement() ?? key }

        switch topic {
        case .circleOfFifths:
            return Int.random(in: 0..<3) < 2
                ? .circleNeighbor(key: key, step: Bool.random() ? 1 : -1)
                : .circleRelative(key: key)
        case .keySignatures:
            switch Int.random(in: 0..<4) {
            case 0:  return .accidentalCount(key: key)
            case 1:  return .keyForSignature(key: key)
            case 2:  return .nthAccidental(n: Int.random(in: 1...7), sharps: Bool.random())
            default: return .accidentalsInKey(key: pick(keys.filter { $0.fifths != 0 }))
            }
        case .relativeKeys:
            switch Int.random(in: 0..<3) {
            case 0:  return .relativeKey(key: key)
            case 1:  return .parallelKey(key: pick(keys.filter { $0.parallel != nil }))
            default:
                let pair = randomPair(keys: keys)
                return Bool.random() ? .relationship(first: pair.0, second: pair.1) : .relationship(first: pair.1, second: pair.0)
            }
        case .scales:
            switch Int.random(in: 0..<7) {
            case 0, 1: return .scaleNotes(key: key)
            case 2, 3: return .scaleDegree(key: key, degree: Int.random(in: 2...7))
            case 4, 5: return .majorToMinor(key: pick(TheoryKey.usual(isMinor: false).filter { $0.parallel != nil }))
            default:   return .stepPattern(isMinor: isMinor)
            }
        }
    }

    /// Two keys of `keys`' mode (or one and its relative or parallel), related one of the four ways.
    private static func randomPair(keys: [TheoryKey]) -> (TheoryKey, TheoryKey) {
        let fallback = TheoryKey(fifths: 0, isMinor: false)
        let key = keys.randomElement() ?? fallback
        switch KeyRelationship.allCases.randomElement() ?? .relative {
        case .relative:
            return (key, key.relative)
        case .parallel:
            let k = keys.filter { $0.parallel != nil }.randomElement() ?? fallback
            return (k, k.parallel ?? k.relative)
        case .neighbors:
            return (key, TheoryKey(fifths: key.fifths + (Bool.random() ? 1 : -1), isMinor: key.isMinor))
        case .enharmonic:
            // B / C♭, F♯ / G♭, D♭ / C♯ (and their relative minors): the slices with two names.
            let k = keys.filter { abs($0.fifths) >= 5 }.randomElement() ?? fallback
            return (k, TheoryKey(fifths: k.fifths > 0 ? k.fifths - 12 : k.fifths + 12, isMinor: k.isMinor))
        }
    }

    // MARK: Helpers

    /// `answer` and up to three of `wrong`, in order and without repeats, shuffled.
    private static func choices(_ answer: String, _ wrong: [String]) -> [String] {
        var picked = [answer]
        for choice in wrong where picked.count < 4 && !picked.contains(choice) {
            picked.append(choice)
        }
        return picked.shuffled()
    }

    /// Key names for `answer` and up to three of `wrong`, skipping any that sound the same as one
    /// already picked (F♯ major and G♭ major are never both choices).
    private static func keyChoices(_ answer: TheoryKey, _ wrong: [TheoryKey]) -> [String] {
        var picked = [answer]
        for key in wrong where picked.count < 4 {
            if picked.contains(where: { $0.isMinor == key.isMinor && $0.tonicPitchClass == key.tonicPitchClass }) { continue }
            picked.append(key)
        }
        return picked.map(\.name).shuffled()
    }

    /// The accidental for `note` a half step off: a sharp or flat made natural, a natural made
    /// sharp or flat (never F♭, C♭, E♯ or B♯, which would just be another natural note).
    private static func altered(_ note: (letter: Int, accidental: Int)) -> Int {
        if note.accidental != 0 { return 0 }
        switch note.letter {
        case 0, 3: return 1    // C, F
        case 2, 6: return -1   // E, B
        default:   return Bool.random() ? 1 : -1
        }
    }

    private static func relativeSentence(_ key: TheoryKey) -> String {
        key.isMinor
            ? "\(key.relative.name) is the relative major of \(key.name): it starts on the minor scale's 3rd note."
            : "\(key.relative.name) is the relative minor of \(key.name): it starts on the major scale's 6th note."
    }

    private static func signatureSentence(_ key: TheoryKey) -> String {
        key.fifths == 0
            ? "\(key.name) has no sharps or flats: \(key.scaleNames.joined(separator: " "))."
            : "\(key.name) has \(key.signature.countName.lowercased()) (\(key.signature.accidentalNames.joined(separator: " "))): \(key.scaleNames.joined(separator: " "))."
    }

    /// "1st", "2nd", "7th".
    static func ordinal(_ n: Int) -> String {
        switch n {
        case 1:  return "1st"
        case 2:  return "2nd"
        case 3:  return "3rd"
        default: return "\(n)th"
        }
    }
}

// MARK: - TheoryQuizSession

@Observable
final class TheoryQuizSession {

    static let topicsKey = "theoryQuiz.topics"

    // MARK: Settings

    /// Topics questions are drawn from. Saved, so the choice sticks between visits.
    var topics: Set<TheoryTopic> {
        didSet { UserDefaults.standard.set(topics.map(\.rawValue).sorted(), forKey: Self.topicsKey) }
    }

    // MARK: State

    private(set) var currentQuestion: TheoryQuestion?
    private(set) var questionNumber = 0
    private(set) var score = 0
    private(set) var streak = 0
    private(set) var totalAnswered = 0

    var accuracy: Double {
        guard totalAnswered > 0 else { return 0 }
        return Double(score) / Double(totalAnswered)
    }

    init() {
        let saved = (UserDefaults.standard.stringArray(forKey: Self.topicsKey) ?? []).compactMap(TheoryTopic.init(rawValue:))
        topics = saved.isEmpty ? Set(TheoryTopic.allCases) : Set(saved)
    }

    // MARK: Public API

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

    // MARK: Private

    private func drawNext() {
        let enabled = TheoryTopic.allCases.filter { topics.contains($0) }
        let pool = enabled.isEmpty ? TheoryTopic.allCases : enabled
        let previous = currentQuestion?.kind
        var question = TheoryQuestion.make(TheoryQuestion.randomKind(in: pool.randomElement() ?? .circleOfFifths))
        // Don't ask the same thing twice in a row.
        for _ in 0..<5 where question.kind == previous {
            question = TheoryQuestion.make(TheoryQuestion.randomKind(in: pool.randomElement() ?? .circleOfFifths))
        }
        currentQuestion = question
        questionNumber += 1
    }
}
