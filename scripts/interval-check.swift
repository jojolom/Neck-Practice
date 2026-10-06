//
//  interval-check.swift
//
//  Offline check for the notation model and the Interval Trainer: key signature names, interval
//  arithmetic (semitones, spelling, inversions, compounds), wrong-answer choices, thousands of
//  generated questions (right interval, single accidentals, on the staff and the first 12 frets,
//  fretboard placement), triads spelled as chords, and the modes (spelling, formulas, fingerings, quiz).
//
//  Run from the repo root:
//    swiftc -O -parse-as-library -o /tmp/interval-check "Guitar Man/NeckPracticeModelsNote.swift" "Guitar Man/NeckPracticeModelsFretboard.swift" "Guitar Man/NeckPracticeModelsNotation.swift" "Guitar Man/NeckPracticeModelsIntervalSession.swift" "Guitar Man/NeckPracticeModelsTriad.swift" "Guitar Man/NeckPracticeModelsMode.swift" scripts/interval-check.swift && /tmp/interval-check
//

import Foundation

@main
struct IntervalCheck {

    static var failures = 0

    static func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition {
            print("FAIL", message())
            failures += 1
        }
    }

    static func main() {
        checkKeySignatures()
        checkIntervals()
        checkDistractors()
        checkSessions()
        checkTriads()
        checkModes()
        print(failures == 0 ? "All interval checks passed." : "\(failures) failure(s).")
        exit(failures == 0 ? 0 : 1)
    }

    static func tonicName(_ t: (letter: Int, accidental: Int)) -> String {
        SpelledPitch.letterNames[t.letter] + SpelledPitch.accidentalSymbol(t.accidental)
    }

    static func checkKeySignatures() {
        let majors = (-7...7).map { tonicName(KeySignature(fifths: $0).majorTonic) }
        check(majors == ["C♭", "G♭", "D♭", "A♭", "E♭", "B♭", "F", "C", "G", "D", "A", "E", "B", "F♯", "C♯"],
              "major key names: \(majors)")
        let minors = (-7...7).map { tonicName(KeySignature(fifths: $0).minorTonic) }
        check(minors == ["A♭", "E♭", "B♭", "F", "C", "G", "D", "A", "E", "B", "F♯", "C♯", "G♯", "D♯", "A♯"],
              "minor key names: \(minors)")
        // The signature for each key root matches how the rest of the app names that key.
        for note in Note.allCases {
            for minor in [false, true] {
                let key = KeySignature(root: note, isMinor: minor)
                let name = tonicName(minor ? key.minorTonic : key.majorTonic)
                    .replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b")
                check(name == note.keyName(asMinor: minor), "key of \(note) \(minor ? "minor" : "major"): \(name)")
            }
        }
        print("ok   key signatures")
    }

    static func checkIntervals() {
        let expected: [String: Int] = ["m2": 1, "M2": 2, "m3": 3, "M3": 4, "P4": 5, "A4": 6, "d5": 6, "P5": 7,
                                       "m6": 8, "M6": 9, "m7": 10, "M7": 11, "P8": 12, "m9": 13, "M9": 14,
                                       "m10": 15, "M10": 16, "P11": 17, "A11": 18, "d12": 18, "P12": 19,
                                       "m13": 20, "M13": 21, "A2": 3, "A5": 8, "A6": 10, "d7": 9]
        for interval in Interval.simplePool + Interval.compoundPool + Interval.commonAlternates {
            check(interval.isValid, "\(interval.shortName) valid")
            check(expected[interval.shortName] == interval.semitones,
                  "\(interval.shortName) is \(interval.semitones) semitones")
            // Spell it from every scale note of every key, both ways.
            for fifths in -7...7 {
                let key = KeySignature(fifths: fifths)
                for letter in 0..<7 {
                    for octave in 2...4 {
                        let lower = key.pitch(letter: letter, octave: octave)
                        guard let upper = lower.transposed(by: interval) else { continue }
                        check(upper.midi - lower.midi == interval.semitones, "\(lower.name) + \(interval.shortName)")
                        check(Interval.between(lower, upper) == interval,
                              "\(lower.name)\(octave) to \(upper.name): \(Interval.between(lower, upper)?.shortName ?? "nil")")
                        check(Interval.between(upper, lower) == interval, "measured from the lower note")
                        check(upper.transposed(by: interval, up: false) == lower, "\(upper.name) down \(interval.shortName)")
                    }
                }
            }
        }
        for interval in Interval.simplePool {
            guard let inversion = interval.inversion else { check(false, "\(interval.shortName) inverts"); continue }
            check(inversion.number + interval.number == 9, "\(interval.shortName) inversion numbers add to 9")
            check(inversion.semitones + interval.semitones == 12, "\(interval.shortName) inversion fills an octave")
        }
        check(Interval(.major, 6).inversion == Interval(.minor, 3), "M6 inverts to m3")
        check(Interval(.major, 3).compound == Interval(.major, 10), "M3 + octave = M10")
        check(Interval(.minor, 10).simple == Interval(.minor, 3), "m10 - octave = m3")
        check(Interval(.perfect, 8).name == "Perfect Octave" && Interval(.minor, 6).name == "Minor 6th",
              "interval names")
        check(Interval.ordinal(11) == "11th" && Interval.ordinal(2) == "2nd" && Interval.ordinal(13) == "13th",
              "ordinals")
        print("ok   intervals")
    }

    static func checkDistractors() {
        for interval in Interval.simplePool + Interval.compoundPool {
            for _ in 0..<200 {
                let wrong = interval.distractors(5)
                check(wrong.count == 5, "\(interval.shortName): \(wrong.count) wrong answers")
                check(Set(wrong).count == wrong.count && !wrong.contains(interval), "\(interval.shortName): duplicates")
                check(wrong.allSatisfy { $0.isValid && $0.isCommon }, "\(interval.shortName): odd names")
                if !interval.isCompound {
                    check(wrong.allSatisfy { !$0.isCompound }, "\(interval.shortName): compound wrong answer")
                }
            }
        }
        // The first wrong answer is the same number with another quality (m6 or A6 for a M6).
        check(Interval(.major, 6).distractors(1).first?.number == 6, "M6's first wrong answer is another 6th")
        print("ok   wrong answers")
    }

    static func checkSessions() {
        for maxAccidentals in [0, 2, 4, 6] {
            for compound in [false, true] {
                let session = IntervalSession()
                session.maxAccidentals = maxAccidentals
                session.includeCompound = compound
                session.choiceCount = 4
                session.start()
                var seen = Set<String>()
                for _ in 0..<3000 {
                    guard let q = session.currentQuestion, let anchor = session.anchorPosition else {
                        check(false, "no question (\(maxAccidentals), \(compound))")
                        break
                    }
                    seen.insert(q.interval.shortName)
                    check(Interval.between(q.lower, q.upper) == q.interval, "question interval")
                    check(abs(q.lower.accidental) <= 1 && abs(q.upper.accidental) <= 1, "single accidentals")
                    check(q.lower.staffPosition >= -4 && q.upper.staffPosition <= 11, "on the staff")
                    check(abs(q.keySignature.fifths) <= maxAccidentals, "key within setting")
                    check(q.lower.accidental == q.keySignature.accidental(forLetter: q.lower.letter), "lower note in key")
                    check(q.choices.count == 4 && Set(q.choices).count == 4 && q.choices.contains(q.interval), "choices")
                    check(anchor.midiNote == q.first.midi, "anchor plays the first note")
                    check(!session.targetPositions.isEmpty
                          && session.targetPositions.allSatisfy { $0.midiNote == q.second.midi && $0.fret <= 12 },
                          "targets play the second note")
                    if let bonus = session.bonus {
                        check(bonus.choices.contains(bonus.answer) && Set(bonus.choices).count == bonus.choices.count,
                              "bonus choices")
                        switch bonus.kind {
                        case .inversion: check(bonus.answer == q.interval.inversion, "bonus inversion")
                        case .compound:  check(bonus.answer == q.interval.compound, "bonus compound")
                        case .simple:    check(bonus.answer == q.interval.simple, "bonus simple")
                        }
                    }
                    session.advance()
                }
                let pool = compound ? Interval.simplePool + Interval.compoundPool : Interval.simplePool
                check(seen == Set(pool.map(\.shortName)),
                      "every interval comes up (\(maxAccidentals), \(compound)): missing \(Set(pool.map(\.shortName)).subtracting(seen))")
            }
        }
        print("ok   interval sessions")
    }

    static func checkTriads() {
        for shape in allTriadShapes {
            for baseFret in 1...9 {
                let q = TriadQuestion(shape: shape, baseFret: baseFret)
                let pitches = q.spelledPitches
                check(pitches.count == 3, "\(shape.id) at \(baseFret): \(pitches.count) notes")
                check(pitches.allSatisfy { abs($0.accidental) <= 1 }, "\(shape.id) at \(baseFret): double accidental")
                check(pitches.map(\.midi) == q.triadPositions.map(\.midiNote).sorted(), "\(shape.id): pitches")
                // Root, 3rd, and 5th letters: the triad stacks in thirds once put in root position.
                guard let root = pitches.first(where: { $0.note == q.rootNote }) else {
                    check(false, "\(shape.id): no root"); continue
                }
                let third = pitches.first { ($0.letter - root.letter + 7) % 7 == 2 }
                let fifth = pitches.first { ($0.letter - root.letter + 7) % 7 == 4 }
                check(third != nil && fifth != nil, "\(shape.id) at \(baseFret): spelled \(pitches.map(\.name))")
                if let third, let fifth {
                    let thirdSemis = (third.note.rawValue - root.note.rawValue + 12) % 12
                    check(thirdSemis == (shape.quality == .major ? 4 : 3), "\(shape.id): quality")
                    check((fifth.note.rawValue - root.note.rawValue + 12) % 12 == 7, "\(shape.id): fifth")
                }
            }
        }
        // A first-inversion G major reads B–D–G.
        if let shape = allTriadShapes.first(where: { $0.id == "maj-first-123" }) {
            let q = (1...9).map { TriadQuestion(shape: shape, baseFret: $0) }.first { $0.rootNote == .g }
            check(q?.spelledPitches.map(\.name) == ["B", "D", "G"], "first-inversion G major is B D G")
        }
        print("ok   triads")
    }

    static func checkModes() {
        let formulas = Mode.allCases.map { $0.degreeLabels.joined(separator: " ") }
        check(formulas == ["1 2 3 4 5 6 7", "1 2 ♭3 4 5 6 ♭7", "1 ♭2 ♭3 4 5 ♭6 ♭7", "1 2 3 ♯4 5 6 7",
                           "1 2 3 4 5 6 ♭7", "1 2 ♭3 4 5 ♭6 ♭7", "1 ♭2 ♭3 4 ♭5 ♭6 ♭7"], "mode formulas: \(formulas)")
        check(Mode.dorian.comparison == "Natural minor with a ♮6", "Dorian: \(Mode.dorian.comparison)")
        check(Mode.lydian.comparison == "Major with a ♯4", "Lydian: \(Mode.lydian.comparison)")
        check(Mode.locrian.comparison == "Natural minor with a ♭2 and ♭5", "Locrian: \(Mode.locrian.comparison)")
        check(ModeScale(mode: .dorian, root: .d).pitches().map(\.name) == ["D", "E", "F", "G", "A", "B", "C", "D"],
              "D Dorian is the notes of C major")
        check(ModeScale(mode: .lydian, root: .cSharp).name == "D♭ Lydian", "D♭ Lydian, not C♯ Lydian")
        for mode in Mode.allCases {
            for root in Note.allCases {
                let scale = ModeScale(mode: mode, root: root)
                check(abs(scale.parentKey.fifths) <= 6, "\(scale.name): \(scale.parentKey.fifths) accidentals")
                let pitches = scale.pitches()
                check(pitches.allSatisfy { abs($0.accidental) <= 1 }, "\(scale.name): double accidental")
                check(pitches.first?.note == root && pitches.last?.midi == (pitches.first?.midi ?? 0) + 12,
                      "\(scale.name): root to octave")
                check(zip(pitches, mode.semitones).allSatisfy { $0.midi - pitches[0].midi == $1 }, "\(scale.name): notes")
                let fingering = scale.threeNotesPerString
                check(fingering.count == 18, "\(scale.name): 18 notes")
                check(fingering.allSatisfy { $0.position.fret >= 0 && $0.position.fret <= 22 }, "\(scale.name): frets")
                check(fingering.allSatisfy { $0.position.note == root.advanced(by: mode.semitones[$0.degree]) },
                      "\(scale.name): fingering notes")
                for kind in ModeQuestionKind.allCases {
                    let q = ModeQuizSession.makeQuestion(kind: kind, scale: scale, choiceCount: 4)
                    check(q.choices.count == 4 && Set(q.choices).count == 4 && q.choices.contains(q.answer),
                          "\(scale.name) \(kind): choices \(q.choices)")
                }
            }
        }
        print("ok   modes")
    }
}
