//
//  ChordVoicing.swift
//  Guitar Man
//
//  Where to play a chord: playable shapes in standard tuning for any set of notes, found by
//  searching every four-fret window of the neck rather than kept in a table, so 7ths, sus
//  chords, borrowed chords and inversions all get shapes. A shape must have the chord's bass
//  note lowest, every required note, at most four fingers (a barre counts as one), and no more
//  than one muted string in the middle; the familiar open shapes score best (E is 022100, C is
//  x32010), then shapes low on the neck that sound more strings, with the standard movable
//  E- and A-shape barre chords preferred where they fit. No UI here, so
//  scripts/voicing-check.swift can check it.
//

import Foundation

struct ChordVoicing: Hashable {
    /// Fret per string, index 0 = high e … 5 = low E (as FretboardPosition); −1 = not played.
    let frets: [Int]
    /// The fret a finger lies across, if the shape needs one.
    let barre: Int?

    /// "x32010", low E first, as chord charts write them (frets over 9 in parentheses).
    var chart: String {
        frets.reversed().map { $0 < 0 ? "x" : $0 > 9 ? "(\($0))" : "\($0)" }.joined()
    }

    /// Strings played, low to high (5 = low E).
    var played: [(string: Int, fret: Int)] {
        (0..<6).reversed().compactMap { frets[$0] >= 0 ? ($0, frets[$0]) : nil }
    }

    var lowestFret: Int { frets.filter { $0 > 0 }.min() ?? 0 }
    var highestFret: Int { frets.max() ?? 0 }

    var positions: [FretboardPosition] {
        played.map { FretboardPosition(stringIndex: $0.string, fret: $0.fret) }
    }

    // MARK: Search

    private static let openMidi = [64, 59, 55, 50, 45, 40]
    private static let maxFret = 15

    /// Up to `limit` shapes, best first, each in a different part of the neck. `pitchClasses` are
    /// all the chord's notes (C = 0 … B = 11); `required` must all sound (the rest may be left
    /// out); `bass` sounds lowest.
    static func find(pitchClasses: Set<Int>, required: Set<Int>, bass: Int, limit: Int = 3) -> [ChordVoicing] {
        let key = CacheKey(pitchClasses: pitchClasses, required: required, bass: bass)
        let ranked = cache.value(for: key) { search(pitchClasses: pitchClasses, required: required, bass: bass) }
        var picked: [ChordVoicing] = []
        for voicing in ranked where picked.count < limit {
            // Different enough to be worth showing: in another part of the neck.
            if picked.allSatisfy({ abs($0.lowestFret - voicing.lowestFret) >= 3 }) {
                picked.append(voicing)
            }
        }
        return picked
    }

    /// Every playable shape, best first.
    private static func search(pitchClasses: Set<Int>, required: Set<Int>, bass: Int) -> [ChordVoicing] {
        var scored: [ChordVoicing: Double] = [:]
        for low in 1...(maxFret - 3) {
            let window = low...(low + 3)
            // Each string's choices, low E first: not played, open (low on the neck), or a chord note in the window.
            let options: [[Int]] = (0..<6).reversed().map { string in
                var frets = [-1]
                if low <= 3 && pitchClasses.contains(openMidi[string] % 12) { frets.append(0) }
                frets += window.filter { pitchClasses.contains((openMidi[string] + $0) % 12) }
                return frets
            }
            var current: [Int] = []
            func walk(_ index: Int) {
                if index == 6 {
                    let frets = Array(current.reversed())  // back to index 0 = high e
                    if let (voicing, score) = evaluate(frets, pitchClasses: pitchClasses, required: required, bass: bass),
                       score < scored[voicing] ?? .infinity {
                        scored[voicing] = score
                    }
                    return
                }
                for fret in options[index] {
                    current.append(fret)
                    walk(index + 1)
                    current.removeLast()
                }
            }
            walk(0)
        }
        return scored.sorted { $0.value != $1.value ? $0.value < $1.value : $0.key.chart < $1.key.chart }.map(\.key)
    }

    /// The shape and its score (lower is better), or nil if it isn't playable or isn't the chord.
    private static func evaluate(_ frets: [Int], pitchClasses: Set<Int>, required: Set<Int>,
                                 bass: Int) -> (ChordVoicing, Double)? {
        let playedStrings = (0..<6).filter { frets[$0] >= 0 }
        guard playedStrings.count >= 3, let lowString = playedStrings.max(), let highString = playedStrings.min() else {
            return nil
        }
        // The bass note lowest; every required note somewhere.
        guard (openMidi[lowString] + frets[lowString]) % 12 == bass else { return nil }
        let sounding = Set(playedStrings.map { (openMidi[$0] + frets[$0]) % 12 })
        guard required.isSubset(of: sounding) else { return nil }

        // At most one muted string between the lowest and highest played.
        let innerMutes = (highString...lowString).filter { frets[$0] < 0 }.count
        guard innerMutes <= 1 else { return nil }

        // Fingers: one per fretted note, or a barre across the lowest fret and one for each other note.
        let fretted = playedStrings.filter { frets[$0] > 0 }
        let lowest = fretted.map { frets[$0] }.min() ?? 0
        let highest = fretted.map { frets[$0] }.max() ?? 0
        guard highest - lowest <= 3 else { return nil }
        var barre: Int? = nil
        if fretted.count > 4 {
            // The barre lies from the lowest string fretted at `lowest` up to the high e, so
            // nothing under it can ring open or sit below it.
            guard let barreLow = fretted.filter({ frets[$0] == lowest }).max() else { return nil }
            let covered = (0...barreLow).filter { frets[$0] >= 0 }
            guard covered.allSatisfy({ frets[$0] >= lowest }) else { return nil }
            let fingers = 1 + fretted.filter { frets[$0] > lowest }.count
            guard fingers <= 4 else { return nil }
            barre = lowest
        }

        let opens = playedStrings.filter { frets[$0] == 0 }.count
        let missingOptional = pitchClasses.subtracting(sounding).count
        var score = Double(max(lowest, 1)) * 1.5
        score += Double(6 - playedStrings.count) * 2
        score += Double(innerMutes) * 4
        score += barre == nil ? 0 : 2
        score -= Double(opens) * 0.5
        // Stretches get hard fast, and charts rarely leave the high e out.
        score += Double((highest - lowest) * (highest - lowest)) * 0.5
        score += frets[0] < 0 ? 2 : 0
        score += Double(missingOptional) * 1.5
        if isStandardShape(frets) { score -= 3 }
        return (ChordVoicing(frets: frets, barre: barre), score)
    }

    // MARK: Standard shapes

    /// The shapes chord charts teach, low E first (nil = not played). The search only finds real
    /// chords, so these just break ties toward the familiar form (B♭ as x13331, not x10331).
    /// Movable ones also count moved up the neck, their open strings becoming a barre.
    private static let standardShapes: [(frets: [Int?], movable: Bool)] = [
        // Major, minor.
        ([0, 2, 2, 1, 0, 0], true), ([nil, 0, 2, 2, 2, 0], true), ([nil, 3, 2, 0, 1, 0], false),
        ([3, 2, 0, 0, 0, 3], false), ([3, 2, 0, 0, 3, 3], false), ([nil, nil, 0, 2, 3, 2], false),
        ([0, 2, 2, 0, 0, 0], true), ([nil, 0, 2, 2, 1, 0], true), ([nil, nil, 0, 2, 3, 1], false),
        // Sevenths.
        ([0, 2, 0, 1, 0, 0], true), ([nil, 0, 2, 0, 2, 0], true), ([nil, 3, 2, 3, 1, 0], false),
        ([3, 2, 0, 0, 0, 1], false), ([nil, nil, 0, 2, 1, 2], false), ([nil, 2, 1, 2, 0, 2], false),
        ([0, 2, 0, 0, 0, 0], true), ([nil, 0, 2, 0, 1, 0], true), ([nil, nil, 0, 2, 1, 1], false),
        ([0, 2, 1, 1, 0, 0], true), ([nil, 0, 2, 1, 2, 0], true), ([nil, 3, 2, 0, 0, 0], false),
        ([nil, nil, 0, 2, 2, 2], false), ([nil, nil, 3, 2, 1, 0], false),
        ([nil, 0, 1, 0, 1, nil], true), ([nil, nil, 0, 1, 0, 1], true),
        // Sus.
        ([0, 2, 2, 2, 0, 0], true), ([nil, 0, 2, 2, 3, 0], true), ([nil, 0, 2, 2, 0, 0], true),
        ([nil, nil, 0, 2, 3, 3], false), ([nil, nil, 0, 2, 3, 0], false),
    ]

    /// Whether `frets` (index 0 = high e) is one of the standard shapes, in place or moved.
    private static func isStandardShape(_ frets: [Int]) -> Bool {
        let lowFirst = Array(frets.reversed())
        return standardShapes.contains { shape in
            guard zip(shape.frets, lowFirst).allSatisfy({ ($0 == nil) == ($1 < 0) }) else { return false }
            let offsets = Set(zip(shape.frets, lowFirst).compactMap { template, fret in template.map { fret - $0 } })
            guard offsets.count == 1, let offset = offsets.first else { return false }
            return offset == 0 || (shape.movable && offset > 0)
        }
    }

    // MARK: Cache

    private struct CacheKey: Hashable {
        let pitchClasses: Set<Int>
        let required: Set<Int>
        let bass: Int
    }

    /// Searches are quick but views ask often (every redraw of a preview), so keep the answers.
    private final class Cache: @unchecked Sendable {
        private var storage: [CacheKey: [ChordVoicing]] = [:]
        private let lock = NSLock()

        func value(for key: CacheKey, compute: () -> [ChordVoicing]) -> [ChordVoicing] {
            lock.lock()
            if let hit = storage[key] { lock.unlock(); return hit }
            lock.unlock()
            let computed = compute()
            lock.lock()
            storage[key] = computed
            lock.unlock()
            return computed
        }
    }

    private static let cache = Cache()
}
