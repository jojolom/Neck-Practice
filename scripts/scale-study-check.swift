//
//  scale-study-check.swift
//
//  Offline check for Scale Study (ScaleStudySession): every round chains starting scale →
//  relative → parallel → relative on strings X, Y, Y, X, with one major and one minor scale per
//  string; every root sits between frets 2 and 12 (no open-string positions); rounds still
//  cover every starting key; and no rhythm/tempo, random or fixed (including an out-of-range
//  Daily Practice override), goes over 3 notes a second.
//
//  Run from the repo root:
//    swiftc -O -parse-as-library -o /tmp/scale-study-check "Guitar Man/NeckPracticeModelsNote.swift" "Guitar Man/NeckPracticeModelsFretboard.swift" "Guitar Man/NeckPracticeModelsPentatonic.swift" "Guitar Man/NeckPracticeModelsScaleStudySession.swift" scripts/scale-study-check.swift && /tmp/scale-study-check
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
            let x = r[0].string, y = r[1].string
            check(r.map(\.string) == [x, y, y, x] && x != y, "strings X Y Y X: \(r.map(\.string))")
            for string in [5, 6] {
                let on = r.filter { $0.string == string }
                check(on.count == 2 && on.filter(\.isMajor).count == 1, "one major and one minor on string \(string)")
            }
            check(r[1].isMajor != r[0].isMajor && r[1].root == (r[0].isMajor ? r[0].root.relativeMinor : r[0].root.relativeMajor),
                  "scale 2 is the relative of scale 1")
            check(r[2].root == r[1].root && r[2].isMajor != r[1].isMajor, "scale 3 is the parallel of scale 2")
            check(r[3].isMajor != r[2].isMajor && r[3].root == (r[2].isMajor ? r[2].root.relativeMinor : r[2].root.relativeMajor),
                  "scale 4 is the relative of scale 3")
            for scale in r {
                check((2...12).contains(scale.rootFret), "\(scale.fullLabel) on string \(scale.string) at fret \(scale.rootFret)")
                let actual = scale.string == 6 ? fretOnLowE(for: scale.root) : fretOnAString(for: scale.root)
                check(scale.rootFret % 12 == actual, "\(scale.fullLabel): fret \(scale.rootFret) is the root on its string")
            }
            if failures > 20 { return }
        }
        check(startingKeys.count == 24, "every major and minor key can start a round (\(startingKeys.count) of 24)")
        print("ok   rounds: theory chain, X-Y-Y-X strings, roots on frets 2–12, all 24 starting keys")
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
