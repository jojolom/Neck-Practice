//
//  blues-buddy-check.swift
//
//  Offline check for Blues Buddy (BluesGroove, BluesDice, BluesPreset, SavedBluesGrooves):
//  every form spells the chords it should; then thousands of bars, in every form, feel and
//  key, with every mix of the three switches and many seeds, are each playable: every note on
//  the guitar and inside its bar, the bass on the chord (the boogie's 6th and a walk's passing
//  notes aside), the chords on the chord, fills in the pentatonic and ending on a chord note,
//  no chord inside a fill, not too many notes ringing. A switch that's off plays nothing (and
//  doesn't change the others), the same seed gives the same bar, different seeds give different
//  takes, fills come at the ends of lines, the turnaround lands on the 5th. What shows: each
//  scale's name and notes, both follow rules bar by bar, and the fretboard in every key and
//  position (the right notes, two a string, in one part of the neck whatever shows, the ♭5
//  and the two 3rds marked). Grooves save and load; and Solo Buddy's old 12-bar grooves move
//  over, once. Trade Licks: turns of one, two and four bars, a lick in every bar of Buddy's
//  turn and none in yours, every lick note a dot that's showing (top four strings, one at a
//  time, ending on a chord note with room left before your turn), a quiet backing under it,
//  and cues that match the notes.
//
//  Run from the repo root:
//    swiftc -O -parse-as-library -o /tmp/blues-buddy-check "Guitar Man/NeckPracticeModelsNote.swift" "Guitar Man/NeckPracticeModelsFretboard.swift" "Guitar Man/NeckPracticeModelsNotation.swift" "Guitar Man/NeckPracticeModelsRomanNumeral.swift" "Guitar Man/NeckPracticeModelsChord.swift" "Guitar Man/NeckPracticeModelsChordVoicing.swift" "Guitar Man/NeckPracticeModelsPentatonic.swift" "Guitar Man/NeckPracticeModelsSoloBuddy.swift" "Guitar Man/NeckPracticeModelsBluesBuddy.swift" scripts/blues-buddy-check.swift && /tmp/blues-buddy-check
//

import Foundation

@main
struct BluesBuddyCheck {

    static var failures = 0

    static func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition {
            if failures < 40 { print("FAIL", message()) }
            failures += 1
        }
    }

    static func main() {
        checkForms()
        checkScales()
        checkFretboard()
        checkEveryBar()
        checkSwitches()
        checkDice()
        checkFills()
        checkTradeLicks()
        checkPresetsAndSaving()
        checkMovingFromSoloBuddy()
        print(failures == 0 ? "All Blues Buddy checks passed." : "\(failures) failure(s).")
        exit(failures == 0 ? 0 : 1)
    }

    // MARK: Forms

    static func checkForms() {
        func names(_ form: BluesForm, _ key: Note = .a) -> [String] {
            BluesGroove(keyRoot: key, form: form).chords.map(\.name)
        }
        check(names(.twelveBar) == ["A7", "A7", "A7", "A7", "D7", "D7", "A7", "A7", "E7", "D7", "A7", "E7"], "12-bar in A: \(names(.twelveBar))")
        check(names(.quickChange) == ["A7", "D7", "A7", "A7", "D7", "D7", "A7", "A7", "E7", "D7", "A7", "E7"], "quick change in A: \(names(.quickChange))")
        check(names(.minorTwelveBar) == ["Am7", "Dm7", "Am7", "Am7", "Dm7", "Dm7", "Am7", "Am7", "E7", "Dm7", "Am7", "E7"], "minor 12-bar in A: \(names(.minorTwelveBar))")
        check(names(.eightBar) == ["A7", "E7", "D7", "D7", "A7", "E7", "A7", "E7"], "8-bar in A: \(names(.eightBar))")
        check(names(.vamp, .e) == ["E7"], "vamp in E: \(names(.vamp, .e))")
        check(names(.twelveBar, .aSharp).prefix(5).elementsEqual(["B♭7", "B♭7", "B♭7", "B♭7", "E♭7"]), "spelled in the key: \(names(.twelveBar, .aSharp))")

        let g = BluesGroove(keyRoot: .a, form: .twelveBar)
        check(g.symbol(forBar: 12) == g.symbol(forBar: 0) && g.symbol(forBar: 23) == g.symbol(forBar: 11), "the form comes round")
        check(g.keyName == "A" && BluesGroove(form: .minorTwelveBar).keyName == "A Minor", "key names")
        check(g.fillTonic == 57 && BluesGroove(keyRoot: .e).fillTonic == 64 && BluesGroove(keyRoot: .f).fillTonic == 53, "fill register")
        func pool(_ root: Note, _ scale: BluesScale) -> [Int] {
            g.fillPool(BluesGroove.ScaleChoice(root: root, rootName: "", scale: scale))
        }
        check(pool(.a, .minor) == [52, 55, 57, 60, 62, 64, 67, 69, 72], "A minor pentatonic pool \(pool(.a, .minor))")
        check(pool(.a, .major) == [52, 54, 57, 59, 61, 64, 66, 69, 71], "A major pentatonic pool \(pool(.a, .major))")
        check(pool(.a, .blues) == [52, 55, 57, 60, 62, 63, 64, 67, 69, 72], "A blues scale pool \(pool(.a, .blues))")
        check(pool(.d, .major) == [52, 54, 57, 59, 62, 64, 66, 69, 71], "D major pentatonic pool, in the same part of the neck \(pool(.d, .major))")
        for feel in BluesFeel.allCases {
            let slots = feel.slots
            check(slots == slots.sorted() && slots.first == 0 && (slots.last ?? 4) < 4 && slots.count % 4 == 0, "\(feel): slots \(slots)")
        }
        print("ok   forms: 12-bar, quick change, minor, 8-bar, vamp; pools and slots")
    }

    // MARK: What shows

    static func checkScales() {
        let g = BluesGroove(keyRoot: .a, form: .twelveBar)
        check(g.shownScale(forBar: 0).name == "A minor pentatonic", "scale name \(g.shownScale(forBar: 0).name)")
        let names = BluesScale.allCases.map { BluesGroove(keyRoot: .aSharp, scale: $0).shownScale(forBar: 4).name }
        check(names == ["B♭ minor pentatonic", "B♭ major pentatonic", "B♭ blues scale", "B♭ minor + major pentatonic"], "names \(names)")
        check(BluesScale.both.steps == BluesScale.minor.steps.union(BluesScale.major.steps), "Both is the two pentatonics")
        check(BluesScale.blues.steps == BluesScale.minor.steps.union([6]), "the blues scale is the minor pentatonic and the ♭5")
        // A minor blues keeps to minor and blues.
        check(BluesGroove(form: .minorTwelveBar, scale: .major).scale == .minor && BluesGroove(form: .minorTwelveBar, scale: .both).scale == .minor
              && BluesGroove(form: .minorTwelveBar, scale: .blues).scale == .blues, "a minor blues shows minor or blues")
        let sparse = try? JSONDecoder().decode(BluesGroove.self, from: Data(#"{"form":"minorTwelveBar","scale":"both"}"#.utf8))
        check(sparse?.scale == .minor, "and loads that way")
        // A groove saved before the four scales (the scale was a PentatonicQuality) still loads.
        let old = try? JSONDecoder().decode(BluesGroove.self, from: Data(#"{"form":"eightBar","scale":{"major":{}}}"#.utf8))
        check(old == BluesGroove(form: .eightBar), "an old scale loads as minor: \(String(describing: old))")

        // Not following: the scale picked, every bar.
        for scale in BluesScale.allCases {
            let fixed = BluesGroove(keyRoot: .a, form: .twelveBar, scale: scale)
            check((0..<12).allSatisfy { fixed.shownScale(forBar: $0) == BluesGroove.ScaleChoice(root: .a, rootName: "A", scale: scale) }, "\(scale) every bar")
        }
        // Following, on the key's root: major over I, minor over IV and V.
        let tonic = BluesGroove(keyRoot: .a, form: .twelveBar, scale: .blues, followsChords: true, followRule: .tonic)
        let shown = (0..<12).map { tonic.shownScale(forBar: $0) }
        check(shown.allSatisfy { $0.root == .a && $0.rootName == "A" }, "the tonic rule stays on the root")
        check(shown.map(\.scale) == [.major, .major, .major, .major, .minor, .minor, .major, .major, .minor, .minor, .major, .minor], "major on I, minor on IV and V: \(shown.map(\.scale))")
        check(tonic.shownScale(forBar: 16) == tonic.shownScale(forBar: 4), "and round again")
        // Following each chord's own.
        let own = BluesGroove(keyRoot: .a, form: .eightBar, followsChords: true, followRule: .chord)
        check((0..<8).map { own.shownScale(forBar: $0).name } == ["A", "E", "D", "D", "A", "E", "A", "E"].map { "\($0) major pentatonic" }, "each chord's own: \((0..<8).map { own.shownScale(forBar: $0).name })")
        // A minor blues follows each chord's own whichever rule is set: i and iv minor, V major.
        for rule in BluesFollowRule.allCases {
            let minor = BluesGroove(keyRoot: .a, form: .minorTwelveBar, followsChords: true, followRule: rule)
            check(minor.activeFollowRule == .chord, "a minor blues follows each chord's own")
            check((0..<12).map { minor.shownScale(forBar: $0).name } == ["A minor", "D minor", "A minor", "A minor", "D minor", "D minor", "A minor", "A minor", "E major", "D minor", "A minor", "E major"].map { "\($0) pentatonic" },
                  "minor blues, \(rule): \((0..<12).map { minor.shownScale(forBar: $0).name })")
        }
        check(BluesGroove(keyRoot: .a).flatFifthName == "E♭" && BluesGroove(keyRoot: .e).flatFifthName == "B♭" && BluesGroove(keyRoot: .b).flatFifthName == "F"
              && BluesGroove(keyRoot: .a, form: .minorTwelveBar).flatFifthName == "E♭", "the ♭5 spelled")
        // Where it would take a double flat (A𝄫 in D♭), the plain name.
        check(BluesGroove(keyRoot: .cSharp).flatFifthName == "G" && BluesGroove(keyRoot: .gSharp).flatFifthName == "D", "the ♭5 in D♭ and A♭")
        for form in [BluesForm.twelveBar, .minorTwelveBar] {
            for root in Note.allCases {
                let name = BluesGroove(keyRoot: root, form: form).flatFifthName
                check((1...2).contains(name.count) && !name.contains("#"), "the ♭5 in \(BluesGroove(keyRoot: root, form: form).keyName): \(name)")
            }
        }
        print("ok   scales: names, a minor blues, both follow rules")
    }

    static func checkFretboard() {
        var boards = 0
        var differ = 0
        for root in Note.allCases {
            for form in [BluesForm.twelveBar, .minorTwelveBar] {
                for position in 1...5 {
                    let plain = BluesGroove(keyRoot: root, form: form)
                    let area = plain.area(position: position)
                    let label = "\(plain.keyName) position \(position)"
                    check(area.minFret >= 1 && area.maxFret <= 22, "\(label): area frets \(area.minFret)–\(area.maxFret)")
                    // The area is the minor box Solo Buddy shows at that position.
                    check(Set(area.shapePositions) == Set(PentatonicQuestion(shape: allPentatonicShapes[position - 1], quality: .minor, key: root).shapePositions), "\(label): the area")

                    for showing in showings {
                        var g = plain
                        g.scale = form.isMinor && !BluesScale.forMinorBlues.contains(showing.scale) ? .minor : showing.scale
                        g.followsChords = showing.rule != nil
                        g.followRule = showing.rule ?? .tonic
                        for bar in 0..<g.barCount {
                            boards += 1
                            let board = g.fretboard(position: position, bar: bar)
                            let choice = g.shownScale(forBar: bar)
                            let here = "\(label), \(showing), bar \(bar + 1) (\(choice.name))"
                            let steps = { (p: FretboardPosition) in ((p.note.rawValue - choice.root.rawValue) % 12 + 12) % 12 }
                            check(board.root == choice.root && board.spellsAsMinor == (choice.scale != .major), "\(here): root and spelling")
                            // The right notes, all of them, and nothing else.
                            check(board.marks.keys.allSatisfy { choice.scale.steps.contains(steps($0)) }, "\(here): a dot off the scale")
                            check(Set(board.marks.keys.map(steps)) == choice.scale.steps, "\(here): steps \(Set(board.marks.keys.map(steps)).sorted())")
                            // Roots are the roots.
                            check(board.roots == Set(board.marks.keys.filter { steps($0) == 0 }) && !board.roots.isEmpty, "\(here): roots")
                            // On the neck, in the position's part of it, wherever the scale's root is.
                            let frets = board.marks.keys.map(\.fret)
                            check(board.frets == (frets.min() ?? 0)...(frets.max() ?? 0), "\(here): frets \(board.frets)")
                            check(board.frets.lowerBound >= 1 && board.frets.upperBound <= 24, "\(here): on the neck \(board.frets)")
                            check(board.focus == max(area.minFret - 1, 1)...(area.maxFret + 1), "\(here): focus \(board.focus)")
                            check(board.frets.lowerBound >= board.focus.lowerBound - 1 && board.frets.upperBound <= board.focus.upperBound + 1,
                                  "\(here): frets \(board.frets) stray from \(board.focus)")
                            check(board.frets.count <= 6, "\(here): a stretch of \(board.frets.count) frets")
                            // Every string is used.
                            let perString = (0..<6).map { string in board.marks.keys.filter { $0.stringIndex == string }.count }

                            switch choice.scale {
                            case .minor, .major:
                                check(perString == [2, 2, 2, 2, 2, 2], "\(here): two notes a string \(perString)")
                                check(board.labels.isEmpty, "\(here): no labels")
                                check(board.marks.values.allSatisfy { $0 == .root || $0 == .tone }, "\(here): plain dots")
                                if choice.root == root && choice.scale == .minor {
                                    check(Set(board.marks.keys) == Set(area.shapePositions), "\(here): the minor pentatonic is the area's box")
                                }
                            case .blues:
                                let blue = board.marks.filter { $0.value == .blueNote }.keys
                                check(!blue.isEmpty && blue.allSatisfy { steps($0) == 6 }, "\(here): \(blue.count) blue notes")
                                check(Set(board.marks.keys).subtracting(blue) == Set(area.shapePositions), "\(here): the minor box under the blue notes")
                                check(blue.allSatisfy { (area.minFret...area.maxFret).contains($0.fret) }, "\(here): blue notes among the box's frets")
                                check(Set(board.labels.keys) == Set(blue) && board.labels.values.allSatisfy { $0 == g.flatFifthName }, "\(here): blue notes named")
                            case .both:
                                check(perString.allSatisfy { (3...4).contains($0) }, "\(here): three or four notes a string \(perString)")
                                check(Set(area.shapePositions).isSubset(of: Set(board.marks.keys)), "\(here): the minor box is there")
                                for (dot, mark) in board.marks {
                                    let step = steps(dot)
                                    let expected: BluesFretboard.Mark = step == 0 ? .root : [3, 5, 10].contains(step) ? .minorOnly : [2, 4, 9].contains(step) ? .majorOnly : .tone
                                    check(mark == expected, "\(here): step \(step) marked \(mark)")
                                    check(board.labels[dot] == ["1", "", "2", "♭3", "3", "4", "", "5", "", "6", "♭7", ""][step], "\(here): step \(step) labelled \(board.labels[dot] ?? "nothing")")
                                }
                                // The two 3rds, a fret apart on some string.
                                check(board.marks.keys.contains { dot in
                                    steps(dot) == 3 && board.marks[FretboardPosition(stringIndex: dot.stringIndex, fret: dot.fret + 1)] == .majorOnly
                                }, "\(here): ♭3 and 3 side by side")
                            }
                            if bar > 0, board != g.fretboard(position: position, bar: bar - 1) { differ += 1 }
                        }
                    }
                }
            }
        }
        // Switching Minor to Major keeps the hand where it is: A at the 5th fret is frets 5–8 and 4–7.
        let a = BluesGroove(keyRoot: .a)
        var major = a
        major.scale = .major
        check(a.fretboard(position: 1, bar: 0).frets == 5...8 && major.fretboard(position: 1, bar: 0).frets == 4...7,
              "A, position 1: minor \(a.fretboard(position: 1, bar: 0).frets), major \(major.fretboard(position: 1, bar: 0).frets)")
        check(differ > 500, "following the chords changes the fretboard (\(differ) changes)")
        print("ok   fretboard: \(boards) boards in every key, position and showing; \(differ) changes while following")
    }

    // MARK: Every bar

    /// What the fretboard shows: each scale, and following the chords by each rule.
    static let showings: [(scale: BluesScale, rule: BluesFollowRule?)] = [
        (.minor, nil), (.major, nil), (.blues, nil), (.both, nil), (.minor, .tonic), (.minor, .chord),
    ]

    /// Every mix of the three switches.
    static let switches: [(bass: Bool, stabs: Bool, fills: Bool)] = [
        (true, true, true), (true, true, false), (true, false, true), (false, true, true),
        (true, false, false), (false, true, false), (false, false, true), (false, false, false),
    ]

    static func checkEveryBar() {
        var bars = 0, notes = 0, maxRinging = 0
        let end = Double(BluesGroove.beatsPerBar)
        for form in BluesForm.allCases {
            for feel in BluesFeel.allCases {
                for root in Note.allCases {
                    for (s, mix) in switches.enumerated() {
                        for (v, showing) in showings.enumerated() {
                            let g = BluesGroove(keyRoot: root, form: form, feel: feel, bassPicking: mix.bass,
                                                chordStabs: mix.stabs, fills: mix.fills, scale: showing.scale,
                                                followsChords: showing.rule != nil, followRule: showing.rule ?? .tonic)
                            let seed = UInt64(bars) &* 7919 &+ UInt64(s) &+ UInt64(v) &* 31
                            for bar in 0..<(g.barCount * 3) {
                                let chord = g.chord(forBar: bar)
                                let played = g.bar(bar, seed: seed)
                                let label = "\(form) \(feel) in \(g.keyName), switches \(mix), showing \(showing), bar \(bar + 1) (\(chord.name))"
                                bars += 1
                                notes += played.hits.count
                                check(played.hits == g.hits(forBar: bar, seed: seed), "\(label): hits are the bar's layers")
                                check(BluesBacking(groove: g, seed: seed).hits(forBar: bar) == played.hits, "\(label): the backing plays the bar")

                                for hit in played.hits {
                                    check((0..<end).contains(hit.beat), "\(label): beat \(hit.beat)")
                                    check(hit.beats > 0.01 && hit.beat + hit.beats <= end + 0.001, "\(label): \(hit.beats) beats from \(hit.beat)")
                                    check((40...88).contains(hit.midi), "\(label): midi \(hit.midi)")
                                    check(hit.gain > 0 && hit.gain <= 1, "\(label): gain \(hit.gain)")
                                    check((0..<0.2).contains(hit.roll), "\(label): roll \(hit.roll)")
                                }

                                // Bass: low, and on the chord, the boogie's 6th and ♭7th and a minor walk's 4th aside.
                                let lowRoot = SoloGroove.lowRoot(of: chord)
                                let passing = Set([5, 9, 10].map { (lowRoot + $0) % 12 })
                                for hit in played.bass {
                                    check((lowRoot...(lowRoot + 12)).contains(hit.midi), "\(label): bass \(hit.midi) is by the root \(lowRoot)")
                                    check(chord.pitchClasses.contains(hit.midi % 12) || passing.contains(hit.midi % 12),
                                          "\(label): bass \(hit.midi) isn't in \(chord.name)")
                                }
                                if !played.bass.isEmpty {
                                    check(played.bass.contains { $0.beat == 0 && $0.midi == lowRoot }, "\(label): the root on beat 1")
                                }

                                // Chords: the chord's own notes, and none inside a fill.
                                for hit in played.stabs {
                                    check(chord.pitchClasses.contains(hit.midi % 12), "\(label): stab \(hit.midi) isn't in \(chord.name)")
                                    if let span = played.fillSpan {
                                        check(!span.contains(hit.beat), "\(label): a chord at \(hit.beat) inside the fill \(span)")
                                    }
                                }

                                checkFill(played, in: g, bar: bar, seed: seed, chord: chord, label: label)

                                // Not too many notes ringing at once (AudioPlayer keeps 24).
                                for t in Set(played.hits.map(\.beat)) {
                                    let ringing = played.hits.filter { $0.beat <= t && t < $0.beat + $0.beats }.count
                                    maxRinging = max(maxRinging, ringing)
                                    check(ringing <= 18, "\(label): \(ringing) ringing at beat \(t)")
                                }
                            }
                        }
                    }
                }
            }
        }
        print("ok   every form, feel, key and mix of switches: \(bars) bars, \(notes) notes, at most \(maxRinging) ringing")
    }

    static func checkFill(_ played: BluesGroove.Bar, in g: BluesGroove, bar: Int, seed: UInt64,
                          chord: CompositionChord, label: String) {
        check(played.fill.isEmpty == (played.fillSpan == nil), "\(label): a fill has a span")
        guard !played.fill.isEmpty, let span = played.fillSpan else { return }
        let tonic = g.fillTonic
        let fill = played.fill
        check(fill == fill.sorted { $0.beat < $1.beat }, "\(label): fill in order")
        // One note at a time.
        for (a, b) in zip(fill, fill.dropFirst()) {
            check(a.beat + a.beats <= b.beat + 0.001, "\(label): fill notes overlap at \(b.beat)")
        }
        for hit in fill {
            check(((tonic - 5)...(tonic + 16)).contains(hit.midi), "\(label): fill \(hit.midi) is off the box around \(tonic)")
        }

        if played.isTurnaround {
            check(g.index(ofBar: bar) == g.barCount - 2 && g.form != .vamp, "\(label): the turnaround is the bar before last")
            check(g.startsTurnaround(atBar: bar, seed: seed), "\(label): turnaround as rolled")
            let steps = Set(fill.map { $0.midi - tonic })
            check(steps == [0, 10, 9, 8, 12], "\(label): turnaround notes \(steps.sorted())")
            check(fill.first?.beat == 0 && fill.first?.midi == tonic, "\(label): turnaround starts on the tonic")
            // The next bar lands on the 5th, on the V chord's first beat.
            let next = g.bar(bar + 1, seed: seed)
            check(next.fill.count == 1 && next.fill[0].beat == 0 && next.fill[0].midi == tonic + 7,
                  "\(label): the turnaround lands on the 5th")
            check(g.chord(forBar: bar + 1).pitchClasses.contains((tonic + 7) % 12), "\(label): the 5th is in the V chord")
            return
        }
        if span.isEmpty {
            // The turnaround's landing note.
            check(g.startsTurnaround(atBar: bar - 1, seed: seed) && fill.count == 1, "\(label): only a turnaround lands with an empty span")
            return
        }

        // A fill: in the bar's scale (the curl's major 3rd aside), starting where its span does
        // and ending on a note of the chord. The scale, worked out here from the settings:
        let chordRoot = chord.root.note.rawValue
        let onTonicChord = g.form.degrees[g.index(ofBar: bar)] == 1
        let minorSteps: Set<Int> = [0, 3, 5, 7, 10], majorSteps: Set<Int> = [0, 2, 4, 7, 9]
        let scaleRoot: Int
        var allowed: [Set<Int>]   // any one of these, for the whole fill
        if g.followsChords && (g.isMinor || g.followRule == .chord) {
            scaleRoot = chordRoot
            allowed = [chord.pitchClasses.contains((chordRoot + 3) % 12) ? minorSteps : majorSteps]
        } else if g.followsChords {
            scaleRoot = g.keyRoot.rawValue
            allowed = [onTonicChord ? majorSteps : minorSteps]
        } else {
            scaleRoot = g.keyRoot.rawValue
            switch g.scale {
            case .blues: allowed = [minorSteps.union([6])]
            case .major: allowed = [onTonicChord && !g.isMinor ? majorSteps : minorSteps]
            case .both:  allowed = onTonicChord && !g.isMinor ? [minorSteps, majorSteps] : [minorSteps]
            case .minor: allowed = [minorSteps]
            }
        }
        let majorThird = (chordRoot + 4) % 12
        let plain = fill.enumerated().filter { i, hit in
            !(hit.midi % 12 == majorThird && i > 0 && fill[i - 1].midi == hit.midi - 1 && fill[i - 1].beats <= 0.2)
        }.map { (($0.element.midi - scaleRoot) % 12 + 12) % 12 }
        check(allowed.contains { steps in plain.allSatisfy(steps.contains) }, "\(label): fill steps \(plain) aren't in one of \(allowed.map { $0.sorted() })")
        let scale = g.fillScale(forBar: bar, seed: seed)
        check(scale.scale != .both && Set(plain).isSubset(of: scale.scale.steps) && scale.root.rawValue == scaleRoot, "\(label): the fill's scale is \(scale)")
        check(abs((fill.first?.beat ?? -1) - span.lowerBound) < 0.001, "\(label): the fill starts at \(span.lowerBound)")
        check(fill.count >= 2, "\(label): a fill of \(fill.count)")
        if let last = fill.last {
            check(chord.pitchClasses.contains(last.midi % 12), "\(label): the fill ends on \(last.midi), not in \(chord.name)")
            check(last.beats >= 0.3, "\(label): the last note rings")
        }
    }

    // MARK: Switches

    static func checkSwitches() {
        var thinned = 0
        for form in BluesForm.allCases {
            for feel in BluesFeel.allCases {
                let all = BluesGroove(keyRoot: .g, form: form, feel: feel)
                for seed in UInt64(1)...40 {
                    for bar in 0..<(all.barCount * 2) {
                        let full = all.bar(bar, seed: seed)
                        let label = "\(form) \(feel) seed \(seed) bar \(bar + 1)"
                        for mix in switches {
                            var g = all
                            g.bassPicking = mix.bass
                            g.chordStabs = mix.stabs
                            g.fills = mix.fills
                            let played = g.bar(bar, seed: seed)
                            let plays = g.plays
                            check(plays.bass == (mix.bass || !(mix.stabs || mix.fills)) && plays.stabs == mix.stabs && plays.fills == mix.fills,
                                  "\(label): what plays with \(mix)")
                            check(plays.bass || played.bass.isEmpty, "\(label) \(mix): bass is off")
                            check(!plays.bass || !played.bass.isEmpty, "\(label) \(mix): bass plays every bar")
                            check(plays.stabs || played.stabs.isEmpty, "\(label) \(mix): chords are off")
                            check(plays.fills || played.fill.isEmpty, "\(label) \(mix): fills are off")
                            // A switch doesn't change the others, except that a fill thins the
                            // bass and keeps the chords out, and chords alone keep the time.
                            if plays.fills && (plays.bass || plays.stabs) { check(played.fill == full.fill, "\(label) \(mix): the same fill") }
                            if plays.bass && plays.fills { check(played.bass == full.bass, "\(label) \(mix): the same bass") }
                            if plays.stabs && plays.bass && plays.fills { check(played.stabs == full.stabs, "\(label) \(mix): the same chords") }
                        }
                        // Without fills the bass plays its pattern right through.
                        var noFills = all
                        noFills.fills = false
                        let plain = noFills.bar(bar, seed: seed)
                        if let span = full.fillSpan, !span.isEmpty {
                            thinned += 1
                            let from = Double(Int(span.lowerBound))
                            check(full.bass.filter { $0.beat < from } == plain.bass.filter { $0.beat < from }, "\(label): the bass before the fill")
                            check(full.bass.filter { $0.beat >= from }.allSatisfy { $0.beat == $0.beat.rounded() && $0.midi == full.bass[0].midi },
                                  "\(label): just the root under the fill")
                        } else {
                            check(full.bass == plain.bass, "\(label): the same bass without a fill")
                        }
                        // Chords alone hold the time: 2 and 4 every bar.
                        var chordsOnly = all
                        chordsOnly.bassPicking = false
                        chordsOnly.fills = false
                        let stabs = chordsOnly.bar(bar, seed: seed).stabs
                        check(stabs.contains { $0.beat == 1 } && stabs.contains { $0.beat == 3 }, "\(label): chords alone play 2 and 4")
                    }
                }
            }
        }
        check(thinned > 100, "fills thin the bass (\(thinned) bars)")
        print("ok   switches: off is silent, on is unchanged, the bass thins under \(thinned) fills")
    }

    // MARK: Dice

    static func checkDice() {
        var a = BluesDice(seed: 42, bar: 7, layer: .fill), b = BluesDice(seed: 42, bar: 7, layer: .fill)
        check((0..<50).allSatisfy { _ in a.next() == b.next() }, "the same dice roll the same")
        var seen = Set<UInt64>()
        for layer in [BluesDice.Layer.bassLine, .bass, .stabs, .fill, .turnaround] {
            for bar in -2..<40 {
                var dice = BluesDice(seed: 42, bar: bar, layer: layer)
                seen.insert(dice.next())
            }
        }
        check(seen.count == 5 * 42, "each bar and layer has its own dice (\(seen.count))")
        var dice = BluesDice(seed: 9, bar: 0, layer: .bass)
        var sum = 0.0, heads = 0, picks = [0, 0, 0]
        for _ in 0..<20_000 {
            let unit = dice.unit()
            check((0..<1).contains(unit), "unit \(unit)")
            sum += unit
            if dice.chance(0.3) { heads += 1 }
            picks[dice.pick([(0, 0.5), (1, 0.3), (2, 0.2)])] += 1
        }
        check(abs(sum / 20_000 - 0.5) < 0.02, "units average \(sum / 20_000)")
        check(abs(Double(heads) / 20_000 - 0.3) < 0.02, "chance(0.3) came up \(heads)")
        check(abs(Double(picks[0]) / 20_000 - 0.5) < 0.02 && abs(Double(picks[2]) / 20_000 - 0.2) < 0.02, "weighted picks \(picks)")

        // A take is its seed: the same again, and no two alike.
        let g = BluesGroove(keyRoot: .a, form: .twelveBar)
        func chorus(_ seed: UInt64, _ number: Int = 0) -> [[BluesGroove.Hit]] {
            (0..<12).map { g.hits(forBar: number * 12 + $0, seed: seed) }
        }
        check(chorus(1234) == chorus(1234), "the same seed plays the same chorus")
        let takes = (UInt64(0)..<60).map { chorus($0 &* 0x9E37_79B9 &+ 17) }
        var alike = 0
        for i in takes.indices { for j in takes.indices where j > i && takes[i] == takes[j] { alike += 1 } }
        check(alike == 0, "\(alike) pairs of takes alike")
        let choruses = (0..<30).map { chorus(77, $0) }
        check(Set(choruses.map { "\($0)" }).count == 30, "every chorus of a take is different")
        print("ok   dice: repeatable, fair, and 60 takes and 30 choruses all different")
    }

    // MARK: Fills

    static func checkFills() {
        // Over many choruses: fills mostly at the ends of lines, turnarounds about half the time.
        for form in BluesForm.allCases {
            for feel in BluesFeel.allCases {
                let g = BluesGroove(keyRoot: .a, form: form, feel: feel)
                var byPlace = [0, 0, 0, 0], total = 0, turnarounds = 0, times = 0, curls = 0, strums = 0
                let barsToPlay = 4_800
                for bar in 0..<barsToPlay {
                    let played = g.bar(bar, seed: 2026)
                    total += 1
                    if played.isTurnaround { turnarounds += 1 }
                    if g.index(ofBar: bar) == g.barCount - 2 { times += 1 }
                    if let span = played.fillSpan, !span.isEmpty, !played.isTurnaround {
                        byPlace[(form == .vamp ? bar : g.index(ofBar: bar)) % 4] += 1
                    }
                    let majorThird = (g.chord(forBar: bar).root.note.rawValue + 4) % 12
                    if zip(played.fill, played.fill.dropFirst()).contains(where: { $1.midi == $0.midi + 1 && $1.midi % 12 == majorThird }) { curls += 1 }
                    if played.stabs.filter({ $0.beat == 0 }).count >= 4 { strums += 1 }
                }
                let label = "\(form) \(feel)"
                let share = Double(byPlace.reduce(0, +)) / Double(total)
                check((0.15...0.5).contains(share), "\(label): fills in \(Int(share * 100))% of bars")
                check(byPlace[3] > byPlace[0] * 2 && byPlace[3] > byPlace[1] && byPlace[3] > byPlace[2], "\(label): fills by place in the line \(byPlace)")
                if form == .vamp {
                    check(turnarounds == 0, "\(label): no turnaround on one chord")
                } else {
                    check(abs(Double(turnarounds) / Double(times) - 0.5) < 0.1, "\(label): \(turnarounds) turnarounds in \(times) times through")
                }
                check(form.isMinor ? true : curls > 20, "\(label): \(curls) curls")
                check(strums > barsToPlay / 20, "\(label): \(strums) full chords on beat 1")
            }
        }
        // Fills alone: nearly every bar.
        let only = BluesGroove(keyRoot: .c, form: .twelveBar, bassPicking: false, chordStabs: false, fills: true)
        let filled = (0..<1_200).filter { !only.bar($0, seed: 5).fill.isEmpty }.count
        check(filled > 1_000, "fills alone play most bars (\(filled) of 1200)")
        print("ok   fills: at the ends of lines, turnarounds half the time, curls and full chords turn up")
    }

    // MARK: Trade Licks

    static func checkTradeLicks() {
        // Turns: Buddy first, then you, so many bars each.
        for length in BluesGroove.tradeLengths {
            let g = BluesGroove(mode: .trade, tradeBars: length)
            let turns = (0..<(length * 6)).map { g.turn(atBar: $0) }
            let expected = (0..<(length * 6)).map { ($0 / length) % 2 == 0 ? BluesGroove.Turn.buddy : .you }
            check(turns == expected, "turns of \(length): \(turns)")
            check((0..<(length * 6)).allSatisfy { g.turnStart(ofBar: $0) == ($0 / length) * length }, "turn starts of \(length)")
        }
        check(BluesGroove().turn(atBar: 0) == nil && BluesGroove().bar(0, seed: 1).lick.isEmpty, "no turns jamming along")
        check(BluesGroove(mode: .trade, tradeBars: 3).tradeBars == 2, "a turn is 1, 2 or 4 bars")
        let odd = try? JSONDecoder().decode(BluesGroove.self, from: Data(#"{"mode":"trade","tradeBars":7}"#.utf8))
        check(odd?.mode == .trade && odd?.tradeBars == 2, "and loads that way")
        // Trading, fills are the licks: the bass and the chords are what can be switched.
        for mix in switches {
            let g = BluesGroove(bassPicking: mix.bass, chordStabs: mix.stabs, fills: mix.fills, mode: .trade)
            check(g.plays.bass == (mix.bass || !mix.stabs) && g.plays.stabs == mix.stabs && !g.plays.fills, "what plays trading with \(mix)")
        }

        var bars = 0, lickNotes = 0, curls = 0, majorLicks = 0, minorLicks = 0
        let end = Double(BluesGroove.beatsPerBar)
        for form in BluesForm.allCases {
            for feel in BluesFeel.allCases {
                for root in Note.allCases {
                    for showing in showings {
                        for length in BluesGroove.tradeLengths {
                            for position in 1...5 {
                                // Bass and chords, bass alone, chords alone, and neither (the bass steps in).
                                let mix = switches[[0, 2, 3, 6][(bars / 7) % 4]]
                                let g = BluesGroove(keyRoot: root, form: form, feel: feel, bassPicking: mix.bass, chordStabs: mix.stabs,
                                                    scale: showing.scale, followsChords: showing.rule != nil,
                                                    followRule: showing.rule ?? .tonic, mode: .trade, tradeBars: length)
                                let seed = UInt64(bars) &* 104_729 &+ 3
                                let backing = BluesBacking(groove: g, seed: seed, position: position)
                                for bar in 0..<(length * 4) {
                                    bars += 1
                                    let chord = g.chord(forBar: bar)
                                    let played = g.bar(bar, seed: seed, position: position)
                                    let label = "trading \(length)s, \(form) \(feel) in \(g.keyName), showing \(showing), position \(position), bar \(bar + 1) (\(chord.name))"
                                    check(played.fill.isEmpty && played.fillSpan == nil && !played.isTurnaround, "\(label): no fills trading")
                                    check(backing.hits(forBar: bar) == played.hits, "\(label): the backing plays the bar")
                                    for hit in played.hits {
                                        check((0..<end).contains(hit.beat) && hit.beats > 0.01 && hit.beat + hit.beats <= end + 0.001, "\(label): \(hit.beats) beats from \(hit.beat)")
                                        check((40...88).contains(hit.midi) && hit.gain > 0 && hit.gain <= 1, "\(label): midi \(hit.midi), gain \(hit.gain)")
                                    }
                                    let lowRoot = SoloGroove.lowRoot(of: chord)

                                    guard g.turn(atBar: bar) == .buddy else {
                                        // Your turn: no lick, nothing to light, and the comping it would play jamming along without fills.
                                        check(played.lick.isEmpty && backing.cues(forBar: bar).isEmpty, "\(label): no lick in your turn")
                                        var jam = g
                                        jam.mode = .jam
                                        jam.fills = false
                                        let comp = jam.bar(bar, seed: seed)
                                        if g.plays.bass == jam.plays.bass {
                                            check(played.bass == comp.bass && played.stabs == comp.stabs, "\(label): comping in your turn")
                                        }
                                        check(!played.hits.isEmpty, "\(label): something to play to")
                                        continue
                                    }

                                    // Buddy's turn: a lick, one note at a time.
                                    let lick = played.lick
                                    lickNotes += lick.count
                                    check(lick.count >= 2 && lick.count <= 2 * feel.slots.count, "\(label): a lick of \(lick.count)")
                                    check(Set(lick.map(\.hit.beat)).count == lick.count, "\(label): two lick notes at once")
                                    check(lick.map(\.hit) == lick.map(\.hit).sorted { $0.beat < $1.beat }, "\(label): lick in order")
                                    for (a, b) in zip(lick, lick.dropFirst()) {
                                        check(a.hit.beat + a.hit.beats <= b.hit.beat + 0.001, "\(label): lick notes overlap at \(b.hit.beat)")
                                    }
                                    // Every note is a dot that's showing, on the top four strings, and sounds like where it's played.
                                    let board = g.fretboard(position: position, bar: bar)
                                    let avoid = (chord.root.note.rawValue + 11) % 12
                                    for note in lick {
                                        check(board.marks[note.position] != nil, "\(label): lick note at \(note.position.id) isn't showing")
                                        check(note.position.stringIndex <= 3, "\(label): lick on string \(note.position.stringIndex + 1)")
                                        check(note.position.midiNote == note.hit.midi, "\(label): \(note.hit.midi) played at \(note.position.id)")
                                        check(note.hit.midi % 12 != avoid, "\(label): the chord's major 7th")
                                        check(note.hit.gain >= 0.5, "\(label): lick heard over the backing")
                                    }
                                    // In one scale for the bar, never the two pentatonics muddled.
                                    let scale = g.lickScale(forBar: bar, seed: seed)
                                    check(scale.scale != .both, "\(label): lick scale \(scale)")
                                    let third = (chord.root.note.rawValue + 4) % 12
                                    let plain = lick.enumerated().filter { i, note in
                                        !(note.hit.midi % 12 == third && i > 0 && lick[i - 1].hit.midi == note.hit.midi - 1 && lick[i - 1].hit.beats <= 0.2)
                                    }.map(\.element)
                                    if plain.count < lick.count { curls += 1 }
                                    check(plain.allSatisfy { scale.scale.steps.contains((($0.hit.midi - scale.root.rawValue) % 12 + 12) % 12) }, "\(label): lick off the \(scale.name)")
                                    if showing.scale == .both && showing.rule == nil && !g.isMinor {
                                        if scale.scale == .major { majorLicks += 1 } else { minorLicks += 1 }
                                        check(scale.scale == .minor || g.form.degrees[g.index(ofBar: bar)] == 1, "\(label): major only over I")
                                    }
                                    // It ends on a note of the chord; the turn's last bar by beat 4, ringing, with room before your turn.
                                    if let last = lick.last {
                                        check(chord.pitchClasses.contains(last.hit.midi % 12), "\(label): the lick ends on \(last.hit.midi), not in \(chord.name)")
                                        if bar - g.turnStart(ofBar: bar) == length - 1 {
                                            check(last.hit.beat == 2 || last.hit.beat == 3, "\(label): the turn's last note is on beat \(last.hit.beat + 1)")
                                            check(last.hit.beats >= 0.99, "\(label): and rings \(last.hit.beats)")
                                        }
                                    }
                                    // Quiet under it: the root on the beat, and no chords but on the beat.
                                    if g.plays.bass {
                                        check(played.bass.map(\.beat) == [0, 1, 2, 3] && played.bass.allSatisfy { $0.midi == lowRoot && $0.gain < 0.5 }, "\(label): the bass under a lick")
                                        check(played.stabs.allSatisfy { $0.beat == 0 }, "\(label): chords under a lick")
                                    } else {
                                        check(played.bass.isEmpty && played.stabs.allSatisfy { $0.beat == $0.beat.rounded() } && played.stabs.contains { $0.beat == 1 }, "\(label): chords keep the time under a lick")
                                    }
                                    for hit in played.stabs { check(chord.pitchClasses.contains(hit.midi % 12), "\(label): stab \(hit.midi)") }
                                    // The cues are the lick, note for note.
                                    let cues = backing.cues(forBar: bar)
                                    check(cues.count == lick.count && zip(cues, lick).allSatisfy { cue, note in
                                        cue.beat == note.hit.beat && cue.beats == note.hit.beats && BluesBacking.position(forCue: cue.id) == note.position
                                    }, "\(label): cues")
                                    for t in Set(played.hits.map(\.beat)) {
                                        check(played.hits.filter { $0.beat <= t && t < $0.beat + $0.beats }.count <= 18, "\(label): too many ringing at \(t)")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        check(curls > 50, "licks curl where the major 3rd shows (\(curls))")
        check(majorLicks > 200 && minorLicks > majorLicks, "showing Both, licks are one or the other: \(majorLicks) major, \(minorLicks) minor")

        // A turn's bars share a rhythm two by two; takes differ; a take repeats.
        let g = BluesGroove(keyRoot: .a, form: .twelveBar, feel: .straight, mode: .trade, tradeBars: 4)
        var shared = 0
        for seed in UInt64(1)...200 {
            let first = g.bar(0, seed: seed).lick.map(\.hit.beat), third = g.bar(2, seed: seed).lick.map(\.hit.beat)
            if first.dropLast() == third.dropLast() || first.prefix(3) == third.prefix(3) { shared += 1 }
            check(g.bar(1, seed: seed) == g.bar(1, seed: seed), "a take repeats")
        }
        check(shared > 150, "bars 1 and 3 of a four-bar lick share a rhythm (\(shared) of 200)")
        let takes = Set((UInt64(0)..<60).map { seed in "\((0..<4).map { g.bar($0, seed: seed &* 7 &+ 1).lick })" })
        check(takes.count == 60, "\(takes.count) different licks in 60 takes")
        // The position moves the lick with the box.
        let low = g.bar(0, seed: 9, position: 1).lick.map(\.position.fret), high = g.bar(0, seed: 9, position: 4).lick.map(\.position.fret)
        check((low.max() ?? 0) <= 9 && (high.min() ?? 0) >= 11, "licks at position 1 \(low) and 4 \(high)")
        print("ok   trade licks: \(bars) bars, \(lickNotes) lick notes, every one a dot showing; \(curls) curls")
    }

    // MARK: Presets and saving

    static func checkPresetsAndSaving() {
        let ids = BluesPreset.all.map(\.id)
        check(Set(ids).count == ids.count && Set(BluesPreset.all.map(\.name)).count == ids.count, "preset ids and names are unique")
        check(Set(BluesPreset.all.map(\.groove.form)) == Set(BluesForm.allCases), "a preset for every form")
        check(Set(BluesPreset.all.map(\.groove.feel)) == Set(BluesFeel.allCases), "a preset for every feel")
        for preset in BluesPreset.all {
            let g = preset.groove
            check(g.presetID == preset.id && BluesPreset.preset(preset.id)?.name == preset.name, "\(preset.name): knows its preset")
            check(BluesGroove.tempoRange.contains(g.bpm) && g.bpm % 5 == 0, "\(preset.name): tempo \(g.bpm)")
            check(g.bassPicking && g.chordStabs && g.fills, "\(preset.name): everything plays")
            for chord in Set(g.chords) {
                check(SoloGroove.shape(for: chord).count >= 3, "\(preset.name) \(chord.name): a shape")
            }
            let data = try! JSONEncoder().encode(g)
            check(try! JSONDecoder().decode(BluesGroove.self, from: data) == g, "\(preset.name): saves and loads")
        }
        for feel in BluesFeel.allCases {
            check(BluesGroove.tempoRange.contains(feel.defaultBPM) && BluesGroove(feel: feel).bpm == feel.defaultBPM, "\(feel): default tempo")
        }
        // A groove saved with fields missing (by an older version) loads with the defaults.
        let sparse = try? JSONDecoder().decode(BluesGroove.self, from: Data(#"{"form":"eightBar","feel":"slow"}"#.utf8))
        check(sparse == BluesGroove(form: .eightBar, feel: .slow), "a sparse groove loads: \(String(describing: sparse))")

        let defaults = UserDefaults(suiteName: "blues-buddy-check")!
        defaults.removePersistentDomain(forName: "blues-buddy-check")
        check(SavedBluesGrooves.loadCurrent(defaults) == BluesPreset.all[0].groove, "the first preset to start with")
        check(SavedBluesGrooves.load(defaults).isEmpty, "nothing saved to start with")
        var mine = BluesPreset.all[3].groove
        mine.fills = false
        let first = SavedBlues(name: "Mine", groove: mine)
        SavedBluesGrooves.store([first], defaults)
        check(SavedBluesGrooves.load(defaults) == [first], "saved grooves load back")
        check(first.playable.savedID == first.id && first.playable.presetID == nil && first.playable.sameMusic(as: mine), "a saved groove plays as itself")
        check(SavedBluesGrooves.unusedName("Mine", in: [first]) == "Mine 2", "a new name doesn't clash")
        SavedBluesGrooves.storeCurrent(first.playable, defaults)
        check(SavedBluesGrooves.loadCurrent(defaults) == first.playable, "the groove playing is remembered")
        defaults.removePersistentDomain(forName: "blues-buddy-check")
        print("ok   presets: \(BluesPreset.all.map(\.name).joined(separator: ", ")); saving")
    }

    // MARK: From Solo Buddy

    static func checkMovingFromSoloBuddy() {
        let defaults = UserDefaults(suiteName: "blues-buddy-check")!
        defaults.removePersistentDomain(forName: "blues-buddy-check")

        // Three grooves saved in Solo Buddy when it had the 12-bar blues: two blues and a loop.
        let twelve = SoloGroove(keyRoot: .e, isMinor: false, chords: [ChordSymbol(degree: 1)], form: .twelveBar,
                                style: .shuffle, bpm: 62, barsPerChord: 1, scale: .major, presetID: nil)
        let minor = SoloGroove(keyRoot: .d, isMinor: true, chords: [ChordSymbol(degree: 1)], form: .twelveBar,
                               style: .ballad, bpm: 180, barsPerChord: 1, scale: .minor, presetID: "minor-blues")
        let loop = SoloPreset.all[0].groove
        let savedTwelve = SavedGroove(name: "My Blues", groove: twelve, savedAt: Date(timeIntervalSince1970: 1_000))
        let savedMinor = SavedGroove(name: "Sad One", groove: minor, savedAt: Date(timeIntervalSince1970: 3_000))
        let savedLoop = SavedGroove(name: "Spanish", groove: loop, savedAt: Date(timeIntervalSince1970: 2_000))
        SavedGrooves.store([savedTwelve, savedMinor, savedLoop], defaults)
        // Blues Buddy already has one called "My Blues".
        let own = SavedBlues(name: "My Blues", groove: BluesPreset.all[1].groove, savedAt: Date(timeIntervalSince1970: 500))
        SavedBluesGrooves.store([own], defaults)
        // And Solo Buddy was left playing the saved 12-bar.
        SavedGrooves.storeCurrent(savedTwelve.playable, defaults)

        let blues = SavedBluesGrooves.load(defaults)
        check(blues.map(\.name) == ["Sad One", "My Blues 2", "My Blues"], "blues grooves move over, newest first, names kept apart: \(blues.map(\.name))")
        check(blues.map(\.id) == [savedMinor.id, savedTwelve.id, own.id], "they keep their ids")
        let moved = blues.first { $0.id == savedTwelve.id }?.groove
        check(moved == BluesGroove(keyRoot: .e, form: .quickChange, feel: .shuffle, bpm: 62, scale: .major), "the 12-bar as it was: \(String(describing: moved))")
        let movedMinor = blues.first { $0.id == savedMinor.id }?.groove
        check(movedMinor == BluesGroove(keyRoot: .d, form: .minorTwelveBar, feel: .slow, bpm: 160, scale: .minor), "the minor blues as it was: \(String(describing: movedMinor))")
        // Solo Buddy's old 12-bar had the quick change: the same chords, bar for bar.
        let oldTwelve = ["E7", "A7", "E7", "E7", "A7", "A7", "E7", "E7", "B7", "A7", "E7", "B7"]
        check(moved?.chords.map(\.name) == oldTwelve, "the same twelve bars: \(moved?.chords.map(\.name) ?? [])")
        check(SavedGrooves.load(defaults) == [savedLoop], "Solo Buddy keeps the rest")

        // The groove left playing comes too, still tied to its saved groove; Solo Buddy starts afresh.
        let current = SavedBluesGrooves.loadCurrent(defaults)
        check(current.savedID == savedTwelve.id && current.sameMusic(as: moved ?? BluesGroove()), "the groove playing moves over")
        check(SavedGrooves.loadCurrent(defaults) == SoloPreset.all[0].groove, "Solo Buddy goes back to its first preset")
        check(defaults.data(forKey: SavedGrooves.currentKey) == nil, "and forgets the 12-bar")

        // Only once, and never over what Blues Buddy is playing.
        check(SavedBluesGrooves.load(defaults).count == 3 && SavedGrooves.load(defaults).count == 1, "moved once")
        SavedBluesGrooves.storeCurrent(BluesPreset.all[4].groove, defaults)
        SavedGrooves.storeCurrent(twelve, defaults)
        check(SavedBluesGrooves.loadCurrent(defaults) == BluesPreset.all[4].groove, "Blues Buddy keeps what it's playing")
        check(SavedGrooves.loadCurrent(defaults) == SoloPreset.all[0].groove, "Solo Buddy drops a 12-bar either way")

        // A loop left playing stays put.
        SavedGrooves.storeCurrent(SoloPreset.all[2].groove, defaults)
        check(SavedGrooves.loadCurrent(defaults) == SoloPreset.all[2].groove, "a loop stays in Solo Buddy")
        check(SoloPreset.all.allSatisfy { $0.groove.form == .loop }, "no blues presets left in Solo Buddy")
        defaults.removePersistentDomain(forName: "blues-buddy-check")
        print("ok   Solo Buddy's 12-bar grooves move to Blues Buddy, once")
    }
}
