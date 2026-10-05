//
//  pentatonic-check.swift
//
//  Offline check for the Pentatonic Trainer: every draw produces a question (all 5 positions
//  appear when they fit), every dot is within frets 1...maxFret, every dot is a note of the
//  scale, and the root dots are the root.
//
//  Run from the repo root:
//    swiftc -O -parse-as-library -o /tmp/pentatonic-check "Guitar Man/NeckPracticeModelsNote.swift" "Guitar Man/NeckPracticeModelsFretboard.swift" "Guitar Man/NeckPracticeModelsPentatonic.swift" "Guitar Man/NeckPracticeModelsPentatonicSession.swift" scripts/pentatonic-check.swift && /tmp/pentatonic-check
//

import Foundation

@main
struct PentatonicCheck {

    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        print(condition ? "ok  " : "FAIL", message)
        if !condition { failures += 1 }
    }

    /// Problems with one question, or [] if it's a correct pentatonic box.
    static func problems(_ q: PentatonicQuestion, maxFret: Int) -> [String] {
        var found: [String] = []
        let minorRoot = q.rootNote
        let scale = Set([0, 3, 5, 7, 10].map { minorRoot.advanced(by: $0) })

        if q.shapePositions.count != 12 { found.append("\(q.shapePositions.count) dots") }
        for pos in q.shapePositions {
            if pos.fret < 1 || pos.fret > maxFret { found.append("fret \(pos.fret) outside 1...\(maxFret)") }
            if !scale.contains(pos.note) { found.append("\(pos.note) not in \(minorRoot) minor pentatonic") }
        }
        if q.rootPositions.isEmpty || q.rootPositions.contains(where: { $0.note != minorRoot }) {
            found.append("root markers aren't all \(minorRoot)")
        }
        let effectiveRoots = q.effectiveRootPositions
        if effectiveRoots.isEmpty || effectiveRoots.contains(where: { $0.note != q.effectiveRootNote }) {
            found.append("\(q.quality) root dots aren't all \(q.effectiveRootNote)")
        }
        return found
    }

    static func main() {
        // Trainer: draws never come back empty, at the lowest, default and highest max fret.
        for maxFret in [7, 9, 12, 22] {
            let session = PentatonicSession()
            session.maxFret = maxFret
            var empty = 0
            var bad: [String] = []
            var shapes = Set<Int>()
            for _ in 0..<2000 {
                session.advance()
                guard let q = session.currentQuestion else { empty += 1; continue }
                shapes.insert(q.shape.id)
                bad += problems(q, maxFret: maxFret).map { "Position \(q.shape.id) in \(q.rootNote): \($0)" }
            }
            let fitting = allPentatonicShapes.filter { shape in
                Note.allCases.contains {
                    let a = shape.anchorFret(forMinorRoot: $0)
                    return a + shape.minOffset >= 1 && a + shape.maxOffset <= maxFret
                }
            }.map(\.id)
            check(empty == 0, "max fret \(maxFret): \(empty) of 2000 draws had no question")
            check(shapes == Set(fitting), "max fret \(maxFret): drew positions \(shapes.sorted()), fitting \(fitting)")
            check(bad.isEmpty, "max fret \(maxFret): every dot in range and in the scale\(bad.isEmpty ? "" : " — \(bad.prefix(3))")")
        }
        check(PentatonicSession().maxFret >= 12, "default max fret fits all 5 positions")

        print(failures == 0 ? "0 failures" : "\(failures) failures")
        exit(failures == 0 ? 0 : 1)
    }
}
