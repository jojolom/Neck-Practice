//
//  settings-check.swift
//
//  Offline check that game settings stick and apply at once: every setting of every game survives
//  being saved and loaded (including filters set back to "Both"); plans saved before the newer
//  settings existed still load; after any change of settings a game can tell whether the question
//  on screen still fits, and the next one it draws always does; the number of choices changes in
//  place, on the same question; and Scale Study's rhythm and tempo follow its settings during a round.
//
//  Run from the repo root:
//    swiftc -O -parse-as-library -o /tmp/settings-check "Guitar Man/NeckPracticeModelsNote.swift" "Guitar Man/NeckPracticeModelsFretboard.swift" "Guitar Man/NeckPracticeModelsNotation.swift" "Guitar Man/NeckPracticeModelsRomanNumeral.swift" "Guitar Man/NeckPracticeModelsRomanNumeralSession.swift" "Guitar Man/NeckPracticeModelsTriad.swift" "Guitar Man/NeckPracticeModelsTriadSession.swift" "Guitar Man/NeckPracticeModelsPentatonic.swift" "Guitar Man/NeckPracticeModelsPentatonicSession.swift" "Guitar Man/NeckPracticeModelsQuizSession.swift" "Guitar Man/NeckPracticeModelsSightReadingSession.swift" "Guitar Man/NeckPracticeModelsIntervalSession.swift" "Guitar Man/NeckPracticeModelsMode.swift" "Guitar Man/NeckPracticeModelsScaleStudySession.swift" "Guitar Man/NeckPracticeModelsStepConfig.swift" scripts/settings-check.swift && /tmp/settings-check
//

import Foundation

@main
struct SettingsCheck {

    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        print(condition ? "ok  " : "FAIL", message)
        if !condition { failures += 1 }
    }

    static func main() {
        checkRoundTrips()
        checkOldPlans()
        checkQuestionsFit()
        checkChoicesInPlace()
        checkScaleStudyFollows()
        print(failures == 0 ? "All settings checks passed." : "\(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }

    /// Through JSON, as they're stored.
    static func saved<Settings: Codable>(_ settings: Settings) -> Settings {
        try! JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
    }

    /// Every setting set away from its default comes back, and so does a filter set back to "Both".
    static func checkRoundTrips() {
        let quiz = QuizSession()
        quiz.maxFret = 9; quiz.naturalsOnly = false; quiz.choiceCount = 11
        let quiz2 = QuizSession(); quiz2.apply(override: saved(quiz.settings))
        check(quiz2.settings == quiz.settings && quiz2.maxFret == 9 && !quiz2.naturalsOnly && quiz2.choiceCount == 11,
              "Note Guesser settings come back")

        let triad = TriadSession()
        triad.stringGroupFilter = StringGroup.allCases.last; triad.qualityFilter = .minor; triad.maxFret = 7
        let triad2 = TriadSession(); triad2.apply(override: saved(triad.settings))
        check(triad2.settings == triad.settings && triad2.qualityFilter == .minor && triad2.maxFret == 7,
              "Triad Trainer settings come back")
        triad.qualityFilter = nil
        let triad3 = TriadSession(); triad3.apply(override: saved(triad.settings))
        check(triad3.qualityFilter == nil, "Triad Trainer: Both comes back as Both")

        let pentatonic = PentatonicSession()
        pentatonic.qualityFilter = .major; pentatonic.maxFret = 15; pentatonic.rootChoiceCount = 9
        let pentatonic2 = PentatonicSession(); pentatonic2.apply(override: saved(pentatonic.settings))
        check(pentatonic2.settings == pentatonic.settings && pentatonic2.qualityFilter == .major
              && pentatonic2.rootChoiceCount == 9, "Pentatonic Trainer settings come back")

        let sight = SightReadingSession()
        sight.maxFret = 11; sight.naturalsOnly = false
        let sight2 = SightReadingSession(); sight2.apply(override: saved(sight.settings))
        check(sight2.settings == sight.settings && sight2.maxFret == 11 && !sight2.naturalsOnly,
              "Sight Reading settings come back")

        let roman = RomanNumeralSession()
        roman.keyFilter = .f; roman.scaleFilter = .minor; roman.easyMode = true; roman.choiceCount = 6
        let roman2 = RomanNumeralSession(); roman2.apply(override: saved(roman.settings))
        check(roman2.settings == roman.settings && roman2.keyFilter == .f && roman2.easyMode && roman2.choiceCount == 6,
              "Roman Numerals settings come back")

        let interval = IntervalSession()
        interval.maxAccidentals = 1; interval.includeCompound = true; interval.bonusQuestions = false
        interval.choiceCount = 6
        let interval2 = IntervalSession(); interval2.apply(override: saved(interval.settings))
        check(interval2.settings == interval.settings && interval2.maxAccidentals == 1 && interval2.includeCompound
              && !interval2.bonusQuestions && interval2.choiceCount == 6, "Interval Trainer settings come back")

        let mode = ModeQuizSession()
        mode.includeNameIt = false; mode.includeParentKey = true; mode.includeCompare = false; mode.choiceCount = 7
        let mode2 = ModeQuizSession(); mode2.apply(override: saved(mode.settings))
        check(mode2.settings == mode.settings && !mode2.includeNameIt && !mode2.includeCompare && mode2.choiceCount == 7,
              "Mode Quiz settings come back")

        let scale = ScaleStudySession()
        scale.rhythmMode = .fixed; scale.fixedRhythm = .eighth; scale.fixedBPM = scale.fixedRhythm.bpmRange.lowerBound
        scale.clickSubdivisions = true; scale.enabledRhythms = [.quarter, .eighth]
        let scale2 = ScaleStudySession(); scale2.apply(override: saved(scale.settings))
        check(scale2.settings == scale.settings && scale2.rhythmMode == .fixed && scale2.fixedRhythm == .eighth
              && scale2.clickSubdivisions && scale2.enabledRhythms == [.quarter, .eighth],
              "Scale Study settings come back")
    }

    /// Daily Practice plans saved by earlier versions have none of the newer fields.
    static func checkOldPlans() {
        func old<Settings: Decodable>(_ json: String, as type: Settings.Type) -> Settings? {
            try? JSONDecoder().decode(type, from: Data(json.utf8))
        }
        let interval = old(#"{"maxAccidentals":2}"#, as: IntervalStepConfig.self)
        let mode = old(#"{"choiceCount":5}"#, as: ModeStepConfig.self)
        let scale = old(#"{"fixedBPM":80}"#, as: ScaleStudyStepConfig.self)
        check(interval?.maxAccidentals == 2 && interval?.bonusQuestions == nil
              && mode?.choiceCount == 5 && mode?.includeNameIt == nil
              && scale?.fixedBPM == 80 && scale?.enabledRhythms == nil, "plans from before these settings still load")
        let session = ModeQuizSession()
        session.apply(override: mode)
        check(session.includeNameIt && session.includeParentKey && session.includeCompare,
              "...and leave the newer settings at their defaults")
    }

    /// Whatever the settings become, the game knows if the question fits, and the next one does.
    static func checkQuestionsFit() {
        var noticed = 0
        for _ in 0..<500 {
            let quiz = QuizSession()
            quiz.naturalsOnly = false; quiz.maxFret = 12; quiz.start()
            quiz.maxFret = Int.random(in: 1...12); quiz.naturalsOnly = Bool.random()
            if !quiz.currentFitsSettings { noticed += 1 }
            quiz.advance()
            if !quiz.currentFitsSettings { check(false, "Note Guesser: drew a note outside its settings"); return }
        }
        check(noticed > 0, "Note Guesser: a note outside the new settings is noticed, the next always fits (\(noticed)/500)")

        noticed = 0
        for _ in 0..<500 {
            let triad = TriadSession()
            triad.maxFret = 12; triad.start()
            triad.maxFret = Int.random(in: 5...12)
            triad.qualityFilter = [nil, .major, .minor].randomElement()!
            triad.stringGroupFilter = ([nil] + StringGroup.allCases.map(Optional.some)).randomElement()!
            if !triad.currentFitsSettings { noticed += 1 }
            triad.advance()
            if !triad.currentFitsSettings { check(false, "Triad Trainer: drew a shape outside its settings"); return }
        }
        check(noticed > 0, "Triad Trainer: \(noticed)/500 noticed, the next always fits")

        noticed = 0
        for _ in 0..<500 {
            let pentatonic = PentatonicSession()
            pentatonic.maxFret = 22; pentatonic.start()
            pentatonic.maxFret = Int.random(in: 7...22)
            pentatonic.qualityFilter = [nil, .major, .minor].randomElement()!
            if !pentatonic.currentFitsSettings { noticed += 1 }
            pentatonic.advance()
            if !pentatonic.currentFitsSettings { check(false, "Pentatonic Trainer: drew outside its settings"); return }
        }
        check(noticed > 0, "Pentatonic Trainer: \(noticed)/500 noticed, the next always fits")

        noticed = 0
        for _ in 0..<500 {
            let sight = SightReadingSession()
            sight.maxFret = 12; sight.naturalsOnly = false; sight.start()
            sight.maxFret = Int.random(in: 3...12); sight.naturalsOnly = Bool.random()
            if !sight.currentFitsSettings { noticed += 1 }
            sight.advance()
            if !sight.currentFitsSettings { check(false, "Sight Reading: drew outside its settings"); return }
            sight.refreshValidPositions()
            if sight.validPositions.isEmpty || sight.validPositions.contains(where: { $0.fret > sight.maxFret }) {
                check(false, "Sight Reading: right answers outside the fret range"); return
            }
        }
        check(noticed > 0, "Sight Reading: \(noticed)/500 noticed, the next always fits, right answers stay in range")

        noticed = 0
        for _ in 0..<500 {
            let roman = RomanNumeralSession()
            roman.start()
            roman.keyFilter = Note.allCases.randomElement()!
            roman.scaleFilter = DiatonicScale.allCases.randomElement()!
            if !roman.currentFitsSettings { noticed += 1 }
            roman.advance()
            if !roman.currentFitsSettings { check(false, "Roman Numerals: drew outside its settings"); return }
        }
        check(noticed > 0, "Roman Numerals: \(noticed)/500 noticed, the next always fits")

        noticed = 0
        for _ in 0..<200 {
            let interval = IntervalSession()
            interval.maxAccidentals = 6; interval.includeCompound = true; interval.start()
            interval.maxAccidentals = Int.random(in: 0...6); interval.includeCompound = Bool.random()
            if !interval.currentFitsSettings { noticed += 1 }
            interval.advance()
            if !interval.currentFitsSettings { check(false, "Interval Trainer: drew outside its settings"); return }
        }
        check(noticed > 0, "Interval Trainer: \(noticed)/200 noticed, the next always fits")

        noticed = 0
        for _ in 0..<200 {
            let mode = ModeQuizSession()
            mode.start()
            mode.includeNameIt = Bool.random(); mode.includeParentKey = Bool.random(); mode.includeCompare = Bool.random()
            if !mode.includeNameIt && !mode.includeParentKey && !mode.includeCompare { mode.includeCompare = true }
            if !mode.currentFitsSettings { noticed += 1 }
            mode.advance()
            if !mode.currentFitsSettings { check(false, "Mode Quiz: drew a kind that's turned off"); return }
        }
        check(noticed > 0, "Mode Quiz: \(noticed)/200 noticed, the next always fits")

        let bonus = IntervalSession()
        bonus.bonusQuestions = true
        var sawBonus = false
        for _ in 0..<100 where !sawBonus {
            bonus.advance()
            sawBonus = bonus.bonus != nil
        }
        bonus.bonusQuestions = false
        bonus.dropBonusIfOff()
        check(sawBonus && bonus.bonus == nil, "Interval Trainer: turning bonus questions off drops this round's")
    }

    static func checkChoicesInPlace() {
        let interval = IntervalSession()
        interval.start()
        let before = interval.currentQuestion!
        let number = interval.questionNumber
        for count in [6, 3, 5] {
            interval.choiceCount = count
            interval.refreshChoices()
            let now = interval.currentQuestion!
            check(now.choices.count == count && now.choices.contains(before.interval)
                  && now.interval == before.interval && now.lower == before.lower && now.upper == before.upper
                  && now.descending == before.descending && interval.questionNumber == number,
                  "Interval Trainer: \(count) choices, same question, right answer among them")
        }

        let mode = ModeQuizSession()
        mode.start()
        let question = mode.currentQuestion!
        let modeNumber = mode.questionNumber
        mode.choiceCount = question.choices.count == 3 ? 4 : 3
        mode.refreshChoices()
        let now = mode.currentQuestion!
        check(now.kind == question.kind && now.scale.mode == question.scale.mode && now.scale.root == question.scale.root
              && now.choices.contains(now.answer) && mode.questionNumber == modeNumber,
              "Mode Quiz: same scale and kind, right answer among the new choices")
    }

    static func checkScaleStudyFollows() {
        let session = ScaleStudySession()
        session.rhythmMode = .random
        session.startNewRound()
        let round = session.roundNumber

        session.rhythmMode = .fixed
        session.fixedRhythm = .eighth
        session.fixedBPM = session.fixedRhythm.bpmRange.lowerBound
        session.applySettingsNow()
        check(session.rhythm == .eighth && session.bpm == session.fixedBPM && session.roundNumber == round,
              "Scale Study: fixed rhythm and tempo apply mid-round")

        session.rhythmMode = .random
        session.applySettingsNow()
        check(session.rhythm == .eighth, "Scale Study: random keeps a rhythm that's still on")

        session.enabledRhythms = [.quarter]
        session.applySettingsNow()
        check(session.rhythm == .quarter && Rhythm.quarter.bpmRange.contains(session.bpm),
              "Scale Study: a rhythm you turn off is replaced at once, in its tempo range")
    }
}
