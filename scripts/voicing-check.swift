//
//  voicing-check.swift
//
//  Offline check for ChordVoicing (the chord shapes Compose shows): the familiar open shapes
//  come first (C is x32010, G 320003, D xx0232, Am x02210, G7 320001, …); every chord Compose
//  can write — every palette choice and inversion in every key — gets at least one shape, and
//  every shape is playable (bass note lowest, every required note, nothing outside the chord,
//  at most four fingers counting a barre as one, within four frets, at most one muted string
//  in the middle); and the shapes offered for one chord sit in different parts of the neck.
//
//  Run from the repo root:
//    swiftc -O -parse-as-library -o /tmp/voicing-check "Guitar Man/NeckPracticeModelsNote.swift" "Guitar Man/NeckPracticeModelsFretboard.swift" "Guitar Man/NeckPracticeModelsNotation.swift" "Guitar Man/NeckPracticeModelsRomanNumeral.swift" "Guitar Man/NeckPracticeModelsChord.swift" "Guitar Man/NeckPracticeModelsComposition.swift" "Guitar Man/NeckPracticeModelsChordVoicing.swift" scripts/voicing-check.swift && /tmp/voicing-check
//

import Foundation

@main
struct VoicingCheck {

    static var failures = 0

    static func check(_ condition: Bool, _ message: @autoclosure () -> String) {
        if !condition {
            print("FAIL", message())
            failures += 1
        }
    }

    static let openMidi = [64, 59, 55, 50, 45, 40]

    static func main() {
        checkFamiliarShapes()
        checkEveryChord()
        print(failures == 0 ? "All voicing checks passed." : "\(failures) failure(s).")
        exit(failures == 0 ? 0 : 1)
    }

    static func shapes(_ chord: CompositionChord) -> [ChordVoicing] {
        ChordVoicing.find(pitchClasses: chord.pitchClasses, required: chord.requiredPitchClasses,
                          bass: chord.bass.note.rawValue)
    }

    static func checkFamiliarShapes() {
        var c = Composition()
        func best(_ symbol: ChordSymbol) -> String { shapes(c.chord(symbol)).first?.chart ?? "none" }
        let expected: [(ChordSymbol, String)] = [
            (ChordSymbol(degree: 1), "x32010"),                   // C
            (ChordSymbol(degree: 5), "320003"),                   // G
            (ChordSymbol(degree: 6), "x02210"),                   // Am
            (ChordSymbol(degree: 3), "022000"),                   // Em
            (ChordSymbol(degree: 2), "xx0231"),                   // Dm
            (ChordSymbol(degree: 4), "133211"),                   // F
            (ChordSymbol(degree: 5, kind: .seventh), "320001"),   // G7
            (ChordSymbol(degree: 6, kind: .seventh), "x02010"),   // Am7
            (ChordSymbol(degree: 1, kind: .seventh), "x32000"),   // Cmaj7
            (ChordSymbol(degree: 5, kind: .major, secondary: 5), "xx0232"),  // D (V/V)
            (ChordSymbol(degree: 5, kind: .major, secondary: 6), "022100"),  // E (V/vi)
            (ChordSymbol(degree: 5, kind: .major, secondary: 2), "x02220"),  // A (V/ii)
        ]
        for (symbol, chart) in expected {
            let got = best(symbol)
            check(got == chart, "\(c.chord(symbol).name): best shape \(got), wanted \(chart) (others: \(shapes(c.chord(symbol)).map(\.chart)))")
        }
        let cOverE = shapes(c.chord(ChordSymbol(degree: 1, inversion: 1))).first
        check(cOverE.map { openMidi[$0.played[0].string] + $0.played[0].fret } .map { $0 % 12 } == 4, "C/E has E in the bass: \(cOverE?.chart ?? "none")")
        c.keyRoot = .a
        c.isMinor = true
        check(best(ChordSymbol(degree: 5, kind: .dominant7)) == "020100", "E7 in A minor: \(best(ChordSymbol(degree: 5, kind: .dominant7)))")
        c.keyRoot = .c
        c.isMinor = false
        let samples: [ChordSymbol] = [ChordSymbol(degree: 7, shift: -1, kind: .major), ChordSymbol(degree: 6, shift: -1, kind: .major),
                                      ChordSymbol(degree: 4, kind: .minor), ChordSymbol(degree: 5, kind: .sus4),
                                      ChordSymbol(degree: 2, kind: .sus2), ChordSymbol(degree: 4, kind: .seventh),
                                      ChordSymbol(degree: 7, kind: .seventh), ChordSymbol(degree: 1, inversion: 2),
                                      ChordSymbol(degree: 5, kind: .dominant7, secondary: 5)]
        print("ok   familiar shapes; also " + samples.map { "\(c.chord($0).name) \(shapes(c.chord($0)).map(\.chart))" }.joined(separator: ", "))
    }

    static func checkEveryChord() {
        var chords = 0, shapesSeen = 0
        for minor in [false, true] {
            for root in Note.allCases {
                var k = Composition()
                k.keyRoot = root
                k.isMinor = minor
                var symbols = (1...7).flatMap { CompositionChord.variants(degree: $0, keySignature: k.keySignature, isMinor: minor) }
                symbols += CompositionChord.borrowed(isMinor: minor).flatMap { [$0.chord, $0.seventh] }
                for base in symbols {
                    for inversion in 0...k.chord(base).maxInversion {
                        var symbol = base
                        symbol.inversion = inversion
                        let chord = k.chord(symbol)
                        let found = shapes(chord)
                        chords += 1
                        shapesSeen += found.count
                        check(!found.isEmpty, "\(k.keyName) \(chord.name): no shape")
                        for shape in found { checkPlayable(shape, chord: chord, label: "\(k.keyName) \(chord.name)") }
                        for (a, b) in zip(found, found.dropFirst()) {
                            check(abs(a.lowestFret - b.lowestFret) >= 3, "\(chord.name): \(a.chart) and \(b.chart) too close")
                        }
                    }
                }
            }
        }
        print("ok   every chord: \(chords) chords, \(shapesSeen) shapes")
    }

    static func checkPlayable(_ shape: ChordVoicing, chord: CompositionChord, label: String) {
        let played = shape.played
        check(played.count >= 3, "\(label) \(shape.chart): at least 3 strings")
        let sounding = played.map { (openMidi[$0.string] + $0.fret) % 12 }
        check(sounding.first == chord.bass.note.rawValue, "\(label) \(shape.chart): bass")
        check(Set(sounding).isSubset(of: chord.pitchClasses), "\(label) \(shape.chart): only chord notes")
        check(chord.requiredPitchClasses.isSubset(of: Set(sounding)), "\(label) \(shape.chart): every required note")
        let fretted = shape.frets.filter { $0 > 0 }
        check((fretted.max() ?? 0) - (fretted.min() ?? 0) <= 3, "\(label) \(shape.chart): span")
        let fingers = shape.barre.map { barre in 1 + fretted.filter { $0 > barre }.count } ?? fretted.count
        check(fingers <= 4, "\(label) \(shape.chart): \(fingers) fingers")
        if let barre = shape.barre {
            let lowestBarred = (0..<6).filter { shape.frets[$0] == barre }.max()!
            check((0...lowestBarred).allSatisfy { shape.frets[$0] < 0 || shape.frets[$0] >= barre }, "\(label) \(shape.chart): barre")
        }
        let strings = played.map(\.string)
        let inner = (strings.min()!...strings.max()!).filter { shape.frets[$0] < 0 }.count
        check(inner <= 1, "\(label) \(shape.chart): muted strings in the middle")
    }
}
