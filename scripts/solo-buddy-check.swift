//
//  solo-buddy-check.swift
//
//  Offline check for Solo Buddy (SoloGroove, SoloPreset, BarClock): every preset, moved to
//  every key and played in every style, gives a playable bar each time — every note one of the
//  chord's (the boogie bass's 6th aside), on the guitar, inside its bar, not too many ringing
//  at once, the bass first; the 12-bar blues and two-bar chords come out bar by bar as they
//  should; every preset chord has a shape low on the neck; grooves save and load; and the bar
//  clock keeps bars back to back, on time, through a tempo change.
//
//  Run from the repo root:
//    swiftc -O -parse-as-library -o /tmp/solo-buddy-check "Guitar Man/NeckPracticeModelsNote.swift" "Guitar Man/NeckPracticeModelsFretboard.swift" "Guitar Man/NeckPracticeModelsNotation.swift" "Guitar Man/NeckPracticeModelsRomanNumeral.swift" "Guitar Man/NeckPracticeModelsChord.swift" "Guitar Man/NeckPracticeModelsChordVoicing.swift" "Guitar Man/NeckPracticeModelsPentatonic.swift" "Guitar Man/NeckPracticeModelsSoloBuddy.swift" scripts/solo-buddy-check.swift && /tmp/solo-buddy-check
//

import Foundation

@main
struct SoloBuddyCheck {

    static var failures = 0

    static func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition {
            if failures < 40 { print("FAIL", message()) }
            failures += 1
        }
    }

    static func main() {
        checkPresets()
        checkBars()
        checkEveryStyleEveryKey()
        checkSaving()
        checkClock()
        print(failures == 0 ? "All Solo Buddy checks passed." : "\(failures) failure(s).")
        exit(failures == 0 ? 0 : 1)
    }

    static func checkPresets() {
        let ids = SoloPreset.all.map(\.id)
        check(Set(ids).count == ids.count, "preset ids are unique")
        check(Set(SoloPreset.all.map(\.name)).count == ids.count, "preset names are unique")
        for preset in SoloPreset.all {
            let g = preset.groove
            check(g.presetID == preset.id, "\(preset.name): knows its preset")
            check(SoloGroove.tempoRange.contains(g.bpm), "\(preset.name): tempo \(g.bpm)")
            check(g.form == .twelveBar || SoloGroove.chordRange.contains(g.chords.count), "\(preset.name): 1–4 chords")
            check([1, 2].contains(g.barsPerChord), "\(preset.name): bars per chord")
            for symbol in Set(g.bars.map { $0 }) {
                let shape = SoloGroove.shape(for: g.chord(symbol))
                check(shape.count >= 3, "\(preset.name) \(g.chord(symbol).name): a shape")
            }
        }
        var lines: [String] = []
        for preset in SoloPreset.all {
            let g = preset.groove
            var names: [String] = []
            for symbol in g.bars {
                let name = g.chord(symbol).name
                if names.last != name { names.append(name) }
            }
            lines.append("\(preset.name) (\(g.keyName), \(names.joined(separator: " ")))")
        }
        print("ok   presets: \(SoloPreset.all.count) — " + lines.joined(separator: "; "))
    }

    static func checkBars() {
        var g = SoloGroove()
        g.keyRoot = .a
        g.isMinor = false
        g.form = .twelveBar
        let names = g.bars.map { g.chord($0).name }
        check(names == ["A7", "D7", "A7", "A7", "D7", "D7", "A7", "A7", "E7", "D7", "A7", "E7"], "12-bar in A: \(names)")
        g.isMinor = true
        check(g.bars.map { g.chord($0).name } == ["Am7", "Dm7", "Am7", "Am7", "Dm7", "Dm7", "Am7", "Am7", "E7", "Dm7", "Am7", "E7"],
              "minor 12-bar in A: \(g.bars.map { g.chord($0).name })")
        var loop = SoloGroove()
        loop.form = .loop
        loop.chords = [ChordSymbol(degree: 1), ChordSymbol(degree: 4)]
        loop.barsPerChord = 2
        check(loop.bars == [ChordSymbol(degree: 1), ChordSymbol(degree: 1), ChordSymbol(degree: 4), ChordSymbol(degree: 4)], "two bars each")
        check(loop.symbol(forBar: 5) == ChordSymbol(degree: 1) && loop.symbol(forBar: 6) == ChordSymbol(degree: 4), "bars loop")
        loop.chords = Array(repeating: ChordSymbol(degree: 2), count: 6)
        loop.barsPerChord = 1
        check(loop.bars.count == 4, "at most four chords")
        check(SoloGroove().scaleName == "A minor pentatonic", "scale name \(SoloGroove().scaleName)")
        var flat = SoloGroove()
        flat.keyRoot = .aSharp
        flat.isMinor = false
        flat.scale = .major
        check(flat.scaleName == "B♭ major pentatonic", "spelled in the key: \(flat.scaleName)")
        print("ok   bars: 12-bar, minor 12-bar, two bars a chord, looping")
    }

    static func checkEveryStyleEveryKey() {
        var bars = 0, notes = 0, maxRinging = 0
        for preset in SoloPreset.all {
            for root in Note.allCases {
                for style in BackingStyle.allCases {
                    var g = preset.groove
                    g.keyRoot = root
                    g.style = style
                    for bar in 0..<g.bars.count {
                        let chord = g.chord(g.symbol(forBar: bar))
                        let hits = g.hits(forBar: bar)
                        let label = "\(preset.name) in \(g.keyName), \(style.displayName), bar \(bar + 1) (\(chord.name))"
                        bars += 1
                        notes += hits.count
                        check(!hits.isEmpty, "\(label): plays something")
                        let beats = Double(style.beatsPerBar)
                        let lowRoot = SoloGroove.lowRoot(of: chord)
                        for hit in hits {
                            check((0..<beats).contains(hit.beat), "\(label): beat \(hit.beat)")
                            check(hit.beats > 0 && hit.beat + hit.beats <= beats + 0.001, "\(label): \(hit.beats) beats from \(hit.beat)")
                            check((40...88).contains(hit.midi), "\(label): midi \(hit.midi)")
                            check(hit.gain > 0 && hit.gain <= 1, "\(label): gain \(hit.gain)")
                            check((0..<0.2).contains(hit.roll), "\(label): roll \(hit.roll)")
                            let isBoogieSixth = style == .shuffle && hit.midi == lowRoot + 9
                            check(chord.pitchClasses.contains(hit.midi % 12) || isBoogieSixth,
                                  "\(label): \(hit.midi) isn't in \(chord.name) \(chord.pitchClasses.sorted())")
                        }
                        // Not too many notes ringing at once (AudioPlayer keeps 24).
                        let starts = Set(hits.map(\.beat))
                        for t in starts {
                            let ringing = hits.filter { $0.beat <= t && t < $0.beat + $0.beats }.count
                            maxRinging = max(maxRinging, ringing)
                            check(ringing <= 18, "\(label): \(ringing) ringing at beat \(t)")
                        }
                        // The bass (lowest note) is on beat 1 in the styles built on it.
                        if [.fingerpicked, .reggae, .bossa, .waltz, .funk].contains(style) {
                            let first = hits.filter { $0.beat == 0 }.map(\.midi).min()
                            check(first == hits.map(\.midi).min(), "\(label): bass on beat 1")
                        }
                    }
                }
            }
        }
        print("ok   every preset in every key and style: \(bars) bars, \(notes) notes, at most \(maxRinging) ringing")
    }

    static func checkSaving() {
        for preset in SoloPreset.all {
            let data = try! JSONEncoder().encode(preset.groove)
            check(try! JSONDecoder().decode(SoloGroove.self, from: data) == preset.groove, "\(preset.name): saves and loads")
        }
        // A groove saved before `savedID` existed still loads.
        var old = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(SoloPreset.all[0].groove)) as! [String: Any]
        old.removeValue(forKey: "savedID")
        let oldGroove = try? JSONDecoder().decode(SoloGroove.self, from: JSONSerialization.data(withJSONObject: old))
        check(oldGroove?.sameMusic(as: SoloPreset.all[0].groove) == true, "a groove saved by 1.5's first builds loads")

        // Saved grooves: kept by name, played as themselves, renamed without clashing.
        let defaults = UserDefaults(suiteName: "solo-buddy-check")!
        defaults.removePersistentDomain(forName: "solo-buddy-check")
        let first = SavedGroove(name: "Mine", groove: SoloPreset.all[3].groove)
        SavedGrooves.store([first], defaults)
        let loaded = SavedGrooves.load(defaults)
        check(loaded == [first], "saved grooves load back")
        check(first.playable.savedID == first.id && first.playable.presetID == nil, "a saved groove plays as itself")
        check(first.playable.sameMusic(as: SoloPreset.all[3].groove), "a saved groove keeps its music")
        check(SavedGrooves.unusedName("Mine", in: loaded) == "Mine 2", "a new name doesn't clash")
        // Your Groove from a TestFlight build is kept as a saved groove, once.
        defaults.set(try! JSONEncoder().encode(SoloPreset.all[5].groove), forKey: SavedGrooves.oldYourGrooveKey)
        let migrated = SavedGrooves.load(defaults)
        check(migrated.count == 2 && migrated.contains { $0.name == "My Groove" && $0.groove.sameMusic(as: SoloPreset.all[5].groove) },
              "Your Groove becomes a saved groove")
        check(defaults.data(forKey: SavedGrooves.oldYourGrooveKey) == nil && SavedGrooves.load(defaults).count == 2,
              "and only once")
        defaults.removePersistentDomain(forName: "solo-buddy-check")
        print("ok   saving")
    }

    static func checkClock() {
        let rate = 48_000.0
        var clock = BarClock(firstBarFrame: 4_800)
        var scheduled: [BarClock.Bar] = []
        var bpm = 120.0
        var now: Int64 = 0
        while now < Int64(rate * 30) {
            if now >= Int64(rate * 10) && bpm == 120 { bpm = 77 }
            let framesPerBar = Int64((4 * 60 / bpm * rate).rounded())
            scheduled += clock.bars(dueBy: now + Int64(rate * 0.6), framesPerBar: framesPerBar)
            now += Int64(rate * 0.1)
        }
        check(scheduled.first?.frame == 4_800 && scheduled.first?.index == 0, "first bar where asked")
        check(zip(scheduled, scheduled.dropFirst()).allSatisfy { $1.index == $0.index + 1 && $1.frame == $0.frame + $0.frames },
              "bars back to back, numbered in order")
        check(scheduled.contains { $0.frames == Int64((4 * 60 / 77.0 * rate).rounded()) }, "tempo change takes effect")
        let middle = scheduled[5]
        check(clock.position(at: middle.frame + middle.frames / 4, in: scheduled)?.index == 5
              && abs((clock.position(at: middle.frame + middle.frames / 4, in: scheduled)?.fraction ?? 0) - 0.25) < 1e-6,
              "position in a bar")
        check(clock.position(at: 0, in: scheduled) == nil, "before the first bar: none")
        print("ok   bar clock: \(scheduled.count) bars in 30 s through a tempo change")
    }
}
