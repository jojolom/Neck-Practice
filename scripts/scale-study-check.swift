//
//  scale-study-check.swift
//
//  Offline check for Scale Study (ScaleStudySession): every round chains starting scale →
//  relative → parallel → relative on strings X, X, Y, Y, with one major and one minor scale per
//  string; each scale is spelled from the one before (a relative has the same notes, checked by
//  spelling both scales letter by letter; a parallel has the same tonic name), and every key is a
//  real one, at most 7 sharps or flats; every root sits between frets 2 and 12 (no open-string
//  positions); rounds still cover every starting key that fits (20 of 24: D♭ major, D minor,
//  G minor and A♭ major would put F or B♭ at fret 1; F♯ major, B major, E♭ minor and B♭ minor
//  start as G♭, C♭, D♯ and A♯ so the chain stays within 7); and no rhythm/tempo, random or fixed
//  (including an out-of-range Daily Practice override), goes over 3 notes a second.
//
//  Run from the repo root:
//    swiftc -O -parse-as-library -o /tmp/scale-study-check "Guitar Man/NeckPracticeModelsNote.swift" "Guitar Man/NeckPracticeModelsFretboard.swift" "Guitar Man/NeckPracticeModelsNotation.swift" "Guitar Man/NeckPracticeModelsPentatonic.swift" "Guitar Man/NeckPracticeModelsScaleStudySession.swift" scripts/scale-study-check.swift && /tmp/scale-study-check
//

import Foundation

@main
struct ScaleStudyCheck {

    static var failures = 0

    static func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition {
            print("FAIL", message())
            failures += 1
        }
    }

    static func main() {
        checkRounds()
        checkTempos()
        print(failures == 0 ? "All scale study checks passed." : "\(failures) failure(s).")
        exit(failures == 0 ? 0 : 1)
    }

    static func checkRounds() {
        let session = ScaleStudySession()
        var startingKeys = Set<String>()
        for _ in 0..<3000 {
            session.startNewRound()
            let r = session.round
            guard r.count == 4 else { check(false, "round has \(r.count) scales"); return }
            startingKeys.insert(r[0].fullLabel)
            let x = r[0].string, y = r[2].string
            check(r.map(\.string) == [x, x, y, y] && x != y, "strings X X Y Y: \(r.map(\.string))")
            for string in [5, 6] {
                let on = r.filter { $0.string == string }
                check(on.count == 2 && on.filter(\.isMajor).count == 1, "one major and one minor on string \(string)")
            }
            check(r[1].isMajor != r[0].isMajor && r[1].keySignature == r[0].keySignature
                  && Set(spelledScale(r[1])) == Set(spelledScale(r[0])), "scale 2 is the relative of scale 1: \(labels(r))")
            check(r[2].isMajor != r[1].isMajor && r[2].tonic == r[1].tonic, "scale 3 is the parallel of scale 2: \(labels(r))")
            check(r[3].isMajor != r[2].isMajor && r[3].keySignature == r[2].keySignature
                  && Set(spelledScale(r[3])) == Set(spelledScale(r[2])), "scale 4 is the relative of scale 3: \(labels(r))")
            for scale in r {
                let accidentals = spelledScale(scale).map(\.accidental)
                check(accidentals.allSatisfy { abs($0) <= 1 } && !(accidentals.contains(1) && accidentals.contains(-1)),
                      "\(scale.fullLabel) is a real key: \(accidentals)")
                check(scale.root.rawValue == (SpelledPitch.naturalSemitones[scale.tonic.letter] + scale.tonic.accidental + 12) % 12,
                      "\(scale.fullLabel): root pitch matches its name")
            }
            for scale in r {
                check((2...12).contains(scale.rootFret), "\(scale.fullLabel) on string \(scale.string) at fret \(scale.rootFret)")
                let actual = scale.string == 6 ? fretOnLowE(for: scale.root) : fretOnAString(for: scale.root)
                check(scale.rootFret % 12 == actual, "\(scale.fullLabel): fret \(scale.rootFret) is the root on its string")
            }
            if failures > 20 { return }
        }
        let unfit: Set = ["D♭ Major", "D Minor", "G Minor", "A♭ Major"]
        check(startingKeys.count == 20 && startingKeys.isDisjoint(with: unfit),
              "every key that fits can start a round (\(startingKeys.count) of 20: \(startingKeys.intersection(unfit)))")
        // The one from the bug report: F♯ major's relative minor is D♯ minor (same six sharps).
        let fSharp = ScaleStudySession.chain(startRoot: .a, startMajor: true, startString: 6)!
        check(labels(fSharp) == ["A Major", "F♯ Minor", "F♯ Major", "D♯ Minor"], "A major chain: \(labels(fSharp))")
        print("ok   rounds: theory chain spelled key to key, X-X-Y-Y strings, roots on frets 2–12, all 20 starting keys that fit")
    }

    static func labels(_ round: [ScaleEntry]) -> [String] { round.map(\.fullLabel) }

    /// The scale's seven notes, worked out from its tonic and the major or
    /// natural-minor step pattern, without the key signature.
    static func spelledScale(_ scale: ScaleEntry) -> [SpelledPitch] {
        let steps = scale.isMajor ? [0, 2, 4, 5, 7, 9, 11] : [0, 2, 3, 5, 7, 8, 10]
        let tonicPitch = SpelledPitch.naturalSemitones[scale.tonic.letter] + scale.tonic.accidental
        return (0..<7).map { i in
            let letter = (scale.tonic.letter + i) % 7
            var accidental = (tonicPitch + steps[i] - SpelledPitch.naturalSemitones[letter] + 24) % 12
            if accidental > 6 { accidental -= 12 }
            return SpelledPitch(letter: letter, accidental: accidental, octave: 4)
        }
    }

    static func checkTempos() {
        func notesPerSecond(_ rhythm: Rhythm, _ bpm: Int) -> Double { Double(bpm) / 60 * Double(rhythm.notesPerBeat) }
        for rhythm in Rhythm.allCases {
            check(notesPerSecond(rhythm, rhythm.bpmRange.upperBound) <= 3, "\(rhythm.label) tops out at 3 notes/sec")
            for _ in 0..<200 {
                let bpm = rhythm.randomBPM()
                check(rhythm.bpmRange.contains(bpm) && bpm % 5 == 0, "\(rhythm.label) random BPM \(bpm)")
            }
        }
        // Fixed mode, including overrides outside the range (a plan saved before the ranges changed).
        let session = ScaleStudySession()
        session.rhythmMode = .fixed
        for rhythm in Rhythm.allCases {
            for asked in [0, 40, 100, 200] {
                session.fixedRhythm = rhythm
                session.fixedBPM = asked
                check(rhythm.bpmRange.contains(session.fixedBPM), "\(rhythm.label) fixed \(asked) → \(session.fixedBPM)")
                session.startNewRound()
                check(notesPerSecond(session.rhythm, session.bpm) <= 3, "\(rhythm.label) at \(session.bpm) BPM is over 3 notes/sec")
            }
        }
        // A Daily Practice override sets the rhythm, then the BPM (as apply(override:) does).
        session.fixedRhythm = .sixteenth
        session.fixedBPM = 100
        check(session.fixedBPM == Rhythm.sixteenth.bpmRange.upperBound, "override 16ths at 100 BPM is clamped (\(session.fixedBPM))")
        print("ok   tempos: every rhythm at or under 3 notes/sec, fixed and overridden tempos clamped")
    }
}
