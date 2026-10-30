//
//  theory-quiz-check.swift
//
//  Offline check for Theory Basics (TheoryQuestion): every question the game can ask, each made
//  30 times (choices are random), is checked against theory worked out here independently — scales
//  spelled from the tonic by whole and half steps, signatures counted from those scales, the order
//  of sharps and flats found by walking the circle — rather than from KeySignature. Also: the
//  answer is one of the choices, there are 4 distinct choices, no two key choices sound the same
//  (F♯ and G♭ major), every key named is a real key (at most 7 sharps or flats), and no wrong
//  choice is also right.
//
//  Run from the repo root:
//    swiftc -O -parse-as-library -o /tmp/theory-quiz-check "Guitar Man/NeckPracticeModelsNote.swift" "Guitar Man/NeckPracticeModelsNotation.swift" "Guitar Man/NeckPracticeModelsTheoryQuiz.swift" scripts/theory-quiz-check.swift && /tmp/theory-quiz-check
//

import Foundation

@main
struct TheoryQuizCheck {

    typealias Spelled = (letter: Int, accidental: Int)

    static var failures = 0
    static let letters = ["C", "D", "E", "F", "G", "A", "B"]
    static let naturals = [0, 2, 4, 5, 7, 9, 11]

    static func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition {
            print("FAIL", message())
            failures += 1
        }
    }

    static func main() {
        checkReference()
        checkQuestions()
        print(failures == 0 ? "All theory quiz checks passed." : "\(failures) failure(s).")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: - Independent theory

    static func name(_ n: Spelled) -> String { letters[n.letter] + (n.accidental == 1 ? "♯" : n.accidental == -1 ? "♭" : "") }
    static func pitchClass(_ n: Spelled) -> Int { (naturals[n.letter] + n.accidental + 12) % 12 }

    /// The scale on `tonic`, one letter per step, from the major or natural-minor step pattern.
    static func scale(_ tonic: Spelled, minor: Bool) -> [Spelled] {
        let steps = minor ? [0, 2, 3, 5, 7, 8, 10] : [0, 2, 4, 5, 7, 9, 11]
        let tonicPitch = naturals[tonic.letter] + tonic.accidental
        return (0..<7).map { i in
            let letter = (tonic.letter + i) % 7
            var accidental = (tonicPitch + steps[i] - naturals[letter] + 24) % 12
            if accidental > 6 { accidental -= 12 }
            return (letter, accidental)
        }
    }

    /// Sharps (positive) or flats (negative) in the key; nil if it isn't a real key.
    static func signature(_ tonic: Spelled, minor: Bool) -> Int? {
        let accidentals = scale(tonic, minor: minor).map(\.accidental)
        guard accidentals.allSatisfy({ abs($0) <= 1 }), !(accidentals.contains(1) && accidentals.contains(-1)) else { return nil }
        return accidentals.reduce(0, +)
    }

    /// "E♭ Major" → (E♭, false).
    static func parseKey(_ text: String) -> (tonic: Spelled, minor: Bool)? {
        let parts = text.split(separator: " ")
        guard parts.count == 2, let first = parts[0].first, let letter = letters.firstIndex(of: String(first)) else { return nil }
        let rest = parts[0].dropFirst()
        let accidental = rest == "♯" ? 1 : rest == "♭" ? -1 : rest.isEmpty ? 0 : 99
        guard accidental != 99, parts[1] == "Major" || parts[1] == "Minor" else { return nil }
        return ((letter, accidental), parts[1] == "Minor")
    }

    static func tonic(_ key: TheoryKey) -> Spelled { (key.tonic.letter, key.tonic.accidental) }

    /// Order of sharps: the sharp each new key a fifth up adds (its 7th note). Flats: each key a
    /// fifth down adds its 4th note.
    static let sharpOrder: [String] = {
        var key: Spelled = (0, 0)
        return (0..<7).map { _ in key = scale(key, minor: false)[4]; return name(scale(key, minor: false)[6]) }
    }()
    static let flatOrder: [String] = {
        var key: Spelled = (0, 0)
        return (0..<7).map { _ in key = scale(key, minor: false)[3]; return name(scale(key, minor: false)[3]) }
    }()

    static func countName(_ n: Int) -> String {
        n == 0 ? "No sharps or flats" : n == 1 ? "1 sharp" : n == -1 ? "1 flat" : n > 0 ? "\(n) sharps" : "\(-n) flats"
    }

    static func checkReference() {
        check(sharpOrder == ["F♯", "C♯", "G♯", "D♯", "A♯", "E♯", "B♯"], "order of sharps \(sharpOrder)")
        check(flatOrder == ["B♭", "E♭", "A♭", "D♭", "G♭", "C♭", "F♭"], "order of flats \(flatOrder)")
        // Every key the app's KeySignature names is spelled like the independent scale.
        for fifths in -7...7 {
            for minor in [false, true] {
                let key = TheoryKey(fifths: fifths, isMinor: minor)
                check(key.scaleNames == scale(tonic(key), minor: minor).map(name), "\(key.name) scale \(key.scaleNames)")
                check(signature(tonic(key), minor: minor) == fifths, "\(key.name) has \(fifths) in its signature")
            }
        }
        print("ok   reference: order of sharps and flats, all 30 keys spelled and counted")
    }

    // MARK: - Questions

    static func allKinds() -> [TheoryQuestionKind] {
        var kinds: [TheoryQuestionKind] = []
        for minor in [false, true] {
            for key in TheoryKey.usual(isMinor: minor) {
                kinds += [.circleNeighbor(key: key, step: 1), .circleNeighbor(key: key, step: -1),
                          .circleRelative(key: key), .accidentalCount(key: key), .keyForSignature(key: key),
                          .relativeKey(key: key), .scaleNotes(key: key)]
                if key.fifths != 0 { kinds.append(.accidentalsInKey(key: key)) }
                if let parallel = key.parallel {
                    kinds += [.parallelKey(key: key), .relationship(first: key, second: parallel), .relationship(first: parallel, second: key)]
                    if !minor { kinds.append(.majorToMinor(key: key)) }
                }
                kinds += (2...7).map { .scaleDegree(key: key, degree: $0) }
                var partners = [key.relative, TheoryKey(fifths: key.fifths + 1, isMinor: minor), TheoryKey(fifths: key.fifths - 1, isMinor: minor)]
                if abs(key.fifths) >= 5 {
                    partners.append(TheoryKey(fifths: key.fifths > 0 ? key.fifths - 12 : key.fifths + 12, isMinor: minor))
                }
                for partner in partners {
                    kinds += [.relationship(first: key, second: partner), .relationship(first: partner, second: key)]
                }
            }
        }
        for n in 1...7 { kinds += [.nthAccidental(n: n, sharps: true), .nthAccidental(n: n, sharps: false)] }
        kinds += [.stepPattern(isMinor: false), .stepPattern(isMinor: true)]
        return kinds
    }

    static func checkQuestions() {
        let kinds = allKinds()
        // Random kinds stay within what allKinds covers.
        for topic in TheoryTopic.allCases {
            for _ in 0..<500 {
                let kind = TheoryQuestion.randomKind(in: topic)
                check(kind.topic == topic, "random kind \(kind) is in \(topic)")
                check(kinds.contains(kind), "random kind \(kind) is one the check covers")
            }
        }
        for kind in kinds {
            for _ in 0..<30 { checkQuestion(TheoryQuestion.make(kind)) }
            if failures > 30 { return }
        }
        print("ok   questions: \(kinds.count) kinds × 30, answers right, 4 distinct choices, no wrong choice also right")
    }

    static func checkQuestion(_ q: TheoryQuestion) {
        let answer = q.answer, choices = q.choices
        let label = "\(q.kind): \(q.prompt) → \(answer) \(choices)"
        check(choices.contains(answer), "answer is a choice: \(label)")
        check(Set(choices).count == choices.count && choices.count == 4, "4 distinct choices: \(label)")

        /// Every choice parsed as a key, each a real key, none sounding the same as another.
        func keyChoices() -> [(tonic: Spelled, minor: Bool)] {
            let keys = choices.compactMap(parseKey)
            check(keys.count == choices.count, "choices are keys: \(label)")
            for key in keys { check(signature(key.tonic, minor: key.minor) != nil, "\(name(key.tonic)) is a real key: \(label)") }
            let sounds = Set(keys.map { "\(pitchClass($0.tonic))\($0.minor)" })
            check(sounds.count == keys.count, "no two key choices sound the same: \(label)")
            return keys
        }
        /// The only choice of `keys` that's right is the answer.
        func onlyAnswer(_ keys: [(tonic: Spelled, minor: Bool)], _ isRight: ((tonic: Spelled, minor: Bool)) -> Bool) {
            for (choice, key) in zip(choices, keys) {
                check(isRight(key) == (choice == answer), "\(choice) \(choice == answer ? "is the answer but wrong" : "is wrong but also right"): \(label)")
            }
        }

        switch q.kind {
        case .circleNeighbor(let key, let step):
            let given = scale(tonic(key), minor: key.isMinor)
            let expected = step > 0 ? given[4] : given[3]   // a fifth up or down
            let givenSignature = signature(tonic(key), minor: key.isMinor) ?? 99
            onlyAnswer(keyChoices()) { $0.minor == key.isMinor && pitchClass($0.tonic) == pitchClass(expected) }
            if let a = parseKey(answer) {
                check(signature(a.tonic, minor: a.minor) == givenSignature + step, "one more sharp clockwise, flat counterclockwise: \(label)")
            }
            check(q.wheel?.shown.position == key.wheelPosition && q.wheel?.asked.position == (key.wheelPosition + step + 12) % 12
                  && q.wheel?.asked.isMinor == key.isMinor && q.wheel?.asked.label == parseKey(answer).map { name($0.tonic) + ($0.minor ? "m" : "") },
                  "wheel slices: \(label) \(String(describing: q.wheel))")

        case .circleRelative(let key), .relativeKey(let key):
            let s = scale(tonic(key), minor: key.isMinor)
            let expected = key.isMinor ? s[2] : s[5]   // relative major on the 3rd, relative minor on the 6th
            onlyAnswer(keyChoices()) { $0.minor != key.isMinor && pitchClass($0.tonic) == pitchClass(expected) }
            if let a = parseKey(answer) {
                check(a.tonic == expected && signature(a.tonic, minor: a.minor) == signature(tonic(key), minor: key.isMinor),
                      "relative spelled with the same signature: \(label)")
            }
            if case .circleRelative = q.kind {
                check(q.wheel?.asked.position == key.wheelPosition && q.wheel?.asked.isMinor == !key.isMinor, "wheel slices: \(label)")
            }

        case .accidentalCount(let key):
            check(answer == countName(signature(tonic(key), minor: key.isMinor) ?? 99), "count: \(label)")

        case .keyForSignature(let key):
            let wanted = signature(tonic(key), minor: key.isMinor)
            onlyAnswer(keyChoices()) { $0.minor == key.isMinor && signature($0.tonic, minor: $0.minor) == wanted }

        case .nthAccidental(let n, let sharps):
            check(answer == (sharps ? sharpOrder : flatOrder)[n - 1], "nth: \(label)")

        case .accidentalsInKey(let key):
            let order = key.fifths > 0 ? sharpOrder : flatOrder
            let expected = scale(tonic(key), minor: key.isMinor).filter { $0.accidental != 0 }.map(name)
                .sorted { order.firstIndex(of: $0) ?? 0 < order.firstIndex(of: $1) ?? 0 }
            check(answer == expected.joined(separator: ", "), "accidentals in key: \(label)")

        case .parallelKey(let key):
            onlyAnswer(keyChoices()) { $0.minor != key.isMinor && $0.tonic == tonic(key) }

        case .relationship(let first, let second):
            let a = tonic(first), b = tonic(second)
            let sa = signature(a, minor: first.isMinor), sb = signature(b, minor: second.isMinor)
            var expected: KeyRelationship?
            if first.isMinor != second.isMinor && sa == sb { expected = .relative }
            else if first.isMinor != second.isMinor && a == b { expected = .parallel }
            else if first.isMinor == second.isMinor && pitchClass(a) == pitchClass(b) && a != b { expected = .enharmonic }
            else if first.isMinor == second.isMinor, let sa, let sb, abs(sa - sb) == 1 { expected = .neighbors }
            check(expected != nil && answer == expected?.choice, "relationship: \(label)")
            check(Set(choices) == Set(KeyRelationship.allCases.map(\.choice)), "relationship choices: \(label)")

        case .scaleNotes(let key):
            check(answer == scale(tonic(key), minor: key.isMinor).map(name).joined(separator: " "), "scale notes: \(label)")
            check(q.prompt.contains(key.isMinor ? "natural minor scale" : "major scale"), "says which scale: \(label)")
            // Wrong choices: the parallel scale, or this one with a single note a half step off
            // that isn't just another natural note spelled oddly (F♭, C♭, E♯, B♯).
            let answerNotes = answer.split(separator: " ").map(String.init)
            let parallel = key.parallel.map { scale(tonic($0), minor: $0.isMinor).map(name).joined(separator: " ") }
            for choice in choices where choice != answer && choice != parallel {
                let notes = choice.split(separator: " ").map(String.init)
                let changed = zip(notes, answerNotes).filter { $0 != $1 }.map(\.0)
                check(notes.count == 7 && changed.count == 1 && !["F♭", "C♭", "E♯", "B♯"].contains(changed[0]),
                      "\(choice) is the scale with one note a half step off: \(label)")
            }

        case .scaleDegree(let key, let degree):
            check(answer == name(scale(tonic(key), minor: key.isMinor)[degree - 1]), "degree: \(label)")

        case .majorToMinor(let key):
            let major = scale(tonic(key), minor: false), minor = scale(tonic(key), minor: true)
            let lowered = (0..<7).filter { major[$0] != minor[$0] }
            check(lowered == [2, 5, 6] && lowered.allSatisfy { minor[$0].accidental == major[$0].accidental - 1 }, "3, 6, 7 lowered: \(label)")
            check(answer == lowered.map { name(major[$0]) }.joined(separator: ", "), "major to minor: \(label)")

        case .stepPattern(let isMinor):
            let steps = isMinor ? [0, 2, 3, 5, 7, 8, 10, 12] : [0, 2, 4, 5, 7, 9, 11, 12]
            let pattern = (1..<8).map { steps[$0] - steps[$0 - 1] == 2 ? "W" : "H" }.joined(separator: " ")
            check(answer == pattern, "step pattern: \(label)")
        }
    }
}
