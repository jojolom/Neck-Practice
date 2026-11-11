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
//  takes, fills come at the ends of lines, the turnaround lands on the 5th; grooves save and
//  load; and Solo Buddy's old 12-bar grooves move over, once.
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
        checkEveryBar()
        checkSwitches()
        checkDice()
        checkFills()
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
        check(g.scaleName == "A minor pentatonic", "scale name \(g.scaleName)")
        check(BluesGroove(form: .minorTwelveBar, scale: .major).scale == .minor, "a minor blues shows the minor pentatonic")
        check(g.fillTonic == 57 && BluesGroove(keyRoot: .e).fillTonic == 64 && BluesGroove(keyRoot: .f).fillTonic == 53, "fill register")
        check(g.fillPool(.minor) == [52, 55, 57, 60, 62, 64, 67, 69, 72], "A minor pentatonic pool \(g.fillPool(.minor))")
        check(g.fillPool(.major) == [52, 54, 57, 59, 61, 64, 66, 69, 71], "A major pentatonic pool \(g.fillPool(.major))")
        for feel in BluesFeel.allCases {
            let slots = feel.slots
            check(slots == slots.sorted() && slots.first == 0 && (slots.last ?? 4) < 4 && slots.count % 4 == 0, "\(feel): slots \(slots)")
        }
        print("ok   forms: 12-bar, quick change, minor, 8-bar, vamp; pools and slots")
    }

    // MARK: Every bar

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
                        for scale in [PentatonicQuality.minor, .major] {
                            let g = BluesGroove(keyRoot: root, form: form, feel: feel, bassPicking: mix.bass,
                                                chordStabs: mix.stabs, fills: mix.fills, scale: scale)
                            let seed = UInt64(bars) &* 7919 &+ UInt64(s)
                            for bar in 0..<(g.barCount * 3) {
                                let chord = g.chord(forBar: bar)
                                let played = g.bar(bar, seed: seed)
                                let label = "\(form) \(feel) in \(g.keyName), switches \(mix), bar \(bar + 1) (\(chord.name))"
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

        // A fill: in the bar's pentatonic (the curl's major 3rd aside), starting where its span
        // does and ending on a note of the chord.
        let scale = g.fillScale(forBar: bar)
        let pool = Set(g.fillPool(scale))
        let chordRoot = chord.root.note.rawValue
        let majorThird = (chordRoot + 4) % 12
        for (i, hit) in fill.enumerated() {
            let isCurl = hit.midi % 12 == majorThird && i > 0 && fill[i - 1].midi == hit.midi - 1 && fill[i - 1].beats <= 0.2
            check(pool.contains(hit.midi) || isCurl, "\(label): fill \(hit.midi) isn't in the \(scale) pentatonic")
        }
        check(abs((fill.first?.beat ?? -1) - span.lowerBound) < 0.001, "\(label): the fill starts at \(span.lowerBound)")
        check(fill.count >= 2, "\(label): a fill of \(fill.count)")
        if let last = fill.last {
            check(chord.pitchClasses.contains(last.midi % 12), "\(label): the fill ends on \(last.midi), not in \(chord.name)")
            check(last.beats >= 0.3, "\(label): the last note rings")
        }
        if g.isMinor || g.form.degrees[g.index(ofBar: bar)] != 1 {
            check(scale == .minor, "\(label): minor pentatonic off the I chord")
        } else {
            check(scale == g.scale, "\(label): the pentatonic showing on the I chord")
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
