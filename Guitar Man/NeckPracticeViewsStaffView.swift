//
//  StaffView.swift
//  Guitar Man
//
//  A treble-clef staff in guitar notation (written an octave above concert pitch): clef,
//  key signature, optional time signature, and columns of notes — one note for a melody,
//  several stacked for a chord — with accidentals, ledger lines, stems, and a line of text
//  above and below each column. Used by the Triad, Interval, Modes, and Composition screens.
//

import SwiftUI

/// One spot on the staff: a single note or a stacked chord.
struct StaffColumn: Identifiable {
    var id: Int
    var pitches: [SpelledPitch]
    var value: NoteValue = .whole
    /// Text over the staff (a chord name).
    var above: String? = nil
    /// Text under the staff (note names, a Roman numeral).
    var below: String? = nil
    /// Note-head color; nil draws in the label color.
    var color: Color? = nil
}

struct StaffView: View {

    var keySignature: KeySignature = .cMajor
    var columns: [StaffColumn]
    var showsClef = true
    var showsKeySignature = true
    /// Beats per measure for a time signature (4 → 4/4, 3 → 3/4); nil draws none.
    var beatsPerMeasure: Int? = nil
    /// Draw a bar line at the right edge.
    var showsEndBarline = false
    /// Distance between two staff lines; everything else scales from it.
    var lineSpacing: CGFloat = 10

    /// Width of the clef, key signature, and time signature, for laying a staff out from pieces
    /// (a header followed by one StaffView per slot, as the Composition screen does).
    static func headerWidth(keySignature: KeySignature, showsClef: Bool = true,
                            beatsPerMeasure: Int? = nil, lineSpacing s: CGFloat) -> CGFloat {
        var width = s * 0.4
        if showsClef { width += s * 3.0 }
        if keySignature.fifths != 0 { width += CGFloat(abs(keySignature.fifths)) * s * 0.85 + s * 0.4 }
        if beatsPerMeasure != nil { width += s * 2.4 }
        return width + s * 0.4
    }

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Layout

    /// Y of a staff position (0 = bottom line, 8 = top line); the staff is centered vertically.
    private func y(_ position: Int, in size: CGSize) -> CGFloat {
        size.height / 2 - CGFloat(position - 4) * lineSpacing / 2
    }

    private var noteHeadWidth: CGFloat { lineSpacing * 1.3 }
    private var noteHeadHeight: CGFloat { lineSpacing * 0.95 }
    private var stemLength: CGFloat { lineSpacing * 3.5 }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let s = lineSpacing
        let ink = Color(.label)
        let lineColor = Color(.systemGray3)

        // ── Staff lines ──────────────────────────────────────
        for line in 0..<5 {
            let ly = y(line * 2, in: size)
            context.stroke(Path { p in
                p.move(to: CGPoint(x: 0, y: ly))
                p.addLine(to: CGPoint(x: size.width, y: ly))
            }, with: .color(lineColor), lineWidth: 1)
        }

        var x: CGFloat = s * 0.4

        // ── Clef ─────────────────────────────────────────────
        if showsClef {
            context.draw(Text("𝄞").font(.system(size: s * 4.4)).foregroundColor(ink),
                         at: CGPoint(x: x + s * 1.3, y: y(4, in: size) - s * 0.2), anchor: .center)
            x += s * 3.0
        }

        // ── Key signature ────────────────────────────────────
        if showsKeySignature && keySignature.fifths != 0 {
            let count = abs(keySignature.fifths)
            let isSharp = keySignature.fifths > 0
            let positions = isSharp ? KeySignature.sharpStaffPositions : KeySignature.flatStaffPositions
            for i in 0..<count {
                drawAccidental(isSharp ? 1 : -1, at: CGPoint(x: x + s * 0.5 + CGFloat(i) * s * 0.85,
                                                            y: y(positions[i], in: size)),
                               color: ink, in: &context)
            }
            x += CGFloat(count) * s * 0.85 + s * 0.4
        }

        // ── Time signature ───────────────────────────────────
        if let beats = beatsPerMeasure {
            let font = Font.system(size: s * 2.0, weight: .heavy, design: .serif)
            context.draw(Text("\(beats)").font(font).foregroundColor(ink),
                         at: CGPoint(x: x + s, y: y(6, in: size)), anchor: .center)
            context.draw(Text("4").font(font).foregroundColor(ink),
                         at: CGPoint(x: x + s, y: y(2, in: size)), anchor: .center)
            x += s * 2.4
        }

        // ── End bar line ─────────────────────────────────────
        let right = showsEndBarline ? size.width - 1 : size.width
        if showsEndBarline {
            context.stroke(Path { p in
                p.move(to: CGPoint(x: right, y: y(8, in: size)))
                p.addLine(to: CGPoint(x: right, y: y(0, in: size)))
            }, with: .color(ink), lineWidth: 1.2)
        }

        // ── Columns ──────────────────────────────────────────
        guard !columns.isEmpty else { return }
        let start = x + s * 0.8
        let slot = max(0, right - start - s * 0.4) / CGFloat(columns.count)
        for (i, column) in columns.enumerated() {
            let noteX = start + slot * (CGFloat(i) + 0.5)
            drawColumn(column, x: noteX, size: size, in: &context)
        }
    }

    private func drawColumn(_ column: StaffColumn, x: CGFloat, size: CGSize, in context: inout GraphicsContext) {
        let s = lineSpacing
        let ink = column.color ?? Color(.label)
        let positions = column.pitches.map(\.staffPosition)
        let lowest = positions.min() ?? 4
        let highest = positions.max() ?? 4
        let stemUp = Double(lowest + highest) / 2 < 4

        if !positions.isEmpty {
            // ── Ledger lines (only up to the outermost note) ──
            let ledgerHalf = noteHeadWidth * 0.85
            var ledgers: [Int] = []
            if lowest <= -2 { ledgers += Array(stride(from: -2, through: lowest, by: -2)) }
            if highest >= 10 { ledgers += Array(stride(from: 10, through: highest, by: 2)) }
            for ledger in ledgers {
                let ly = y(ledger, in: size)
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: x - ledgerHalf, y: ly))
                    p.addLine(to: CGPoint(x: x + ledgerHalf, y: ly))
                }, with: .color(Color(.systemGray3)), lineWidth: 1)
            }

            // ── Accidentals, staggered left so stacked ones don't collide ──
            var placed: [(position: Int, slot: Int)] = []
            for pitch in column.pitches.sorted(by: { $0.staffPosition > $1.staffPosition }) {
                guard let accidental = keySignature.printedAccidental(for: pitch) else { continue }
                let position = pitch.staffPosition
                var slot = 0
                while placed.contains(where: { $0.slot == slot && abs($0.position - position) < 6 }) {
                    slot += 1
                }
                placed.append((position, slot))
                drawAccidental(accidental,
                               at: CGPoint(x: x - noteHeadWidth * 0.5 - s * 0.75 - CGFloat(slot) * s * 0.9,
                                           y: y(position, in: size)),
                               color: ink, in: &context)
            }

            // ── Note heads (and dots) ──
            for position in positions {
                drawNoteHead(column.value, at: CGPoint(x: x, y: y(position, in: size)), color: ink, in: &context)
                if column.value.isDotted {
                    // A dot on a line moves up into the space above.
                    let dotPosition = position % 2 == 0 ? position + 1 : position
                    let dotRect = CGRect(x: x + noteHeadWidth * 0.5 + s * 0.3, y: y(dotPosition, in: size) - s * 0.17,
                                         width: s * 0.34, height: s * 0.34)
                    context.fill(Path(ellipseIn: dotRect), with: .color(ink))
                }
            }

            // ── Stem ──
            if column.value.hasStem {
                let stemX = stemUp ? x + noteHeadWidth * 0.5 - 0.6 : x - noteHeadWidth * 0.5 + 0.6
                let fromY = stemUp ? y(lowest, in: size) : y(highest, in: size)
                let toY = stemUp ? y(highest, in: size) - stemLength : y(lowest, in: size) + stemLength
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: stemX, y: fromY))
                    p.addLine(to: CGPoint(x: stemX, y: toY))
                }, with: .color(ink), lineWidth: 1.2)
            }
        }

        // ── Text above / below ──
        let font = Font.system(size: s * 1.3, weight: .semibold, design: .rounded)
        if let above = column.above {
            var top = min(y(8, in: size), y(highest, in: size))
            if column.value.hasStem && stemUp && !positions.isEmpty { top = min(top, y(highest, in: size) - stemLength) }
            context.draw(Text(above).font(font).foregroundColor(Color(.label)),
                         at: CGPoint(x: x, y: top - s * 1.3), anchor: .center)
        }
        if let below = column.below {
            var bottom = max(y(0, in: size), y(lowest, in: size))
            if column.value.hasStem && !stemUp && !positions.isEmpty { bottom = max(bottom, y(lowest, in: size) + stemLength) }
            context.draw(Text(below).font(font).foregroundColor(Color(.secondaryLabel)),
                         at: CGPoint(x: x, y: bottom + s * 1.5), anchor: .center)
        }
    }

    private func drawNoteHead(_ value: NoteValue, at center: CGPoint, color: Color, in context: inout GraphicsContext) {
        let width = value == .whole ? noteHeadWidth * 1.15 : noteHeadWidth
        let rect = CGRect(x: center.x - width / 2, y: center.y - noteHeadHeight / 2,
                          width: width, height: noteHeadHeight)
        let tilt = value == .whole ? 0 : -CGFloat.pi / 8
        let transform = CGAffineTransform(translationX: center.x, y: center.y)
            .rotated(by: tilt)
            .translatedBy(x: -center.x, y: -center.y)
        let head = Path(ellipseIn: rect).applying(transform)
        if value.isFilled {
            context.fill(head, with: .color(color))
        } else {
            context.stroke(head, with: .color(color), lineWidth: value == .whole ? lineSpacing * 0.28 : lineSpacing * 0.2)
        }
    }

    private func drawAccidental(_ accidental: Int, at point: CGPoint, color: Color, in context: inout GraphicsContext) {
        let symbol = accidental == 0 ? "♮" : SpelledPitch.accidentalSymbol(accidental)
        // A flat's bowl sits below the middle of the glyph, so lift it to land on its line or space.
        let lift = accidental < 0 ? lineSpacing * 0.35 : 0
        context.draw(Text(symbol).font(.system(size: lineSpacing * 1.9, weight: .medium)).foregroundColor(color),
                     at: CGPoint(x: point.x, y: point.y - lift), anchor: .center)
    }

    private var accessibilityDescription: String {
        var parts: [String] = []
        if showsKeySignature && keySignature.fifths != 0 {
            let count = abs(keySignature.fifths)
            parts.append("Key signature: \(count) \(keySignature.fifths > 0 ? "sharp" : "flat")\(count == 1 ? "" : "s")")
        }
        for column in columns where !column.pitches.isEmpty {
            parts.append(column.pitches.map(\.name).joined(separator: ", "))
        }
        return parts.joined(separator: ". ")
    }
}

#Preview {
    let key = KeySignature(fifths: -3)
    StaffView(keySignature: key, columns: [
        StaffColumn(id: 0, pitches: [key.pitch(letter: 2, octave: 3), key.pitch(letter: 4, octave: 3),
                                     key.pitch(letter: 6, octave: 3)], below: "E♭ G B♭"),
        StaffColumn(id: 1, pitches: [SpelledPitch(letter: 3, accidental: 1, octave: 3)], value: .half),
        StaffColumn(id: 2, pitches: [SpelledPitch(letter: 0, octave: 3)], value: .quarter, above: "C"),
    ], beatsPerMeasure: 4)
    .frame(height: 150)
    .padding()
}
