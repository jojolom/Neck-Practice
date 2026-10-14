//
//  ChordDiagramView.swift
//  Guitar Man
//
//  A chord chart: the neck upright, low E on the left, with a dot where each finger goes, a
//  bar for a barre, ✕ over strings not played and ○ over open ones. Low on the neck it shows
//  the nut; higher up it starts at the shape's lowest fret, numbered ("5fr"). The chord's root
//  is drawn in orange, like roots elsewhere in the app. ChordShapesView finds the shapes for a
//  Compose chord (see ChordVoicing) and steps through them.
//

import SwiftUI

struct ChordDiagramView: View {

    let voicing: ChordVoicing
    /// Pitch class of the chord's root (C = 0): its dots are orange.
    var rootPitchClass: Int? = nil

    private static let openMidi = [64, 59, 55, 50, 45, 40]
    private let rows = 4

    /// The fret the diagram's first row is: 1 (with the nut) when the shape fits there.
    private var firstFret: Int {
        voicing.highestFret <= rows ? 1 : voicing.lowestFret
    }

    var body: some View {
        Canvas { context, size in
            draw(in: &context, size: size)
        }
        .aspectRatio(0.82, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("Chord shape \(voicing.chart)")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        let ink = Color(.label)
        let line = Color(.systemGray2)
        let labelWidth = size.width * 0.2
        let top = size.height * 0.16
        let bottom = size.height * 0.97
        let left = labelWidth, right = size.width - size.width * 0.06
        let stringGap = (right - left) / 5
        let fretGap = (bottom - top) / CGFloat(rows)
        let dot = min(stringGap, fretGap) * 0.66
        // Column for string index (5 = low E on the left).
        func x(_ string: Int) -> CGFloat { left + CGFloat(5 - string) * stringGap }

        // Frets and strings.
        for row in 0...rows {
            let y = top + CGFloat(row) * fretGap
            context.stroke(Path { p in
                p.move(to: CGPoint(x: left, y: y))
                p.addLine(to: CGPoint(x: right, y: y))
            }, with: .color(line), lineWidth: row == 0 && firstFret == 1 ? max(3, size.height * 0.03) : 1)
        }
        for string in 0..<6 {
            context.stroke(Path { p in
                p.move(to: CGPoint(x: x(string), y: top))
                p.addLine(to: CGPoint(x: x(string), y: bottom))
            }, with: .color(line), lineWidth: 1)
        }
        if firstFret > 1 {
            context.draw(Text("\(firstFret)fr").font(.system(size: size.height * 0.085, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(.secondaryLabel)),
                         at: CGPoint(x: labelWidth * 0.45, y: top + fretGap / 2), anchor: .center)
        }

        // Barre.
        if let barre = voicing.barre, let lowString = (0..<6).filter({ voicing.frets[$0] == barre }).max() {
            let y = top + (CGFloat(barre - firstFret) + 0.5) * fretGap
            let rect = CGRect(x: x(lowString) - dot / 2, y: y - dot * 0.42, width: x(0) - x(lowString) + dot, height: dot * 0.84)
            context.fill(Path(roundedRect: rect, cornerRadius: dot * 0.42), with: .color(ink))
        }

        // Open, muted, and fretted strings.
        let markerY = top - size.height * 0.075
        let markerFont = Font.system(size: size.height * 0.09, weight: .semibold, design: .rounded)
        for string in 0..<6 {
            let fret = voicing.frets[string]
            let isRoot = rootPitchClass.map { fret >= 0 && (Self.openMidi[string] + fret) % 12 == $0 } ?? false
            let color: Color = isRoot ? .orange : ink
            if fret < 0 {
                context.draw(Text("✕").font(markerFont).foregroundColor(Color(.secondaryLabel)),
                             at: CGPoint(x: x(string), y: markerY), anchor: .center)
            } else if fret == 0 {
                let r = dot * 0.36
                context.stroke(Path(ellipseIn: CGRect(x: x(string) - r, y: markerY - r, width: r * 2, height: r * 2)),
                               with: .color(color), lineWidth: 1.5)
            } else {
                let y = top + (CGFloat(fret - firstFret) + 0.5) * fretGap
                context.fill(Path(ellipseIn: CGRect(x: x(string) - dot / 2, y: y - dot / 2, width: dot, height: dot)),
                             with: .color(color))
            }
        }
    }
}

/// The shapes for a Compose chord, one at a time: tap (or the arrows, when interactive) for
/// another place on the neck.
struct ChordShapesView: View {

    let chord: CompositionChord
    /// Show the "1 of 3" switcher; off for previews, which can't take taps.
    var isInteractive = true
    var width: CGFloat = 96

    @State private var index = 0

    private var shapes: [ChordVoicing] {
        ChordVoicing.find(pitchClasses: chord.pitchClasses, required: chord.requiredPitchClasses,
                          bass: chord.bass.note.rawValue)
    }

    var body: some View {
        let shapes = self.shapes
        VStack(spacing: 4) {
            if shapes.isEmpty {
                Text("No shape found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let shape = shapes[min(index, shapes.count - 1)]
                ChordDiagramView(voicing: shape, rootPitchClass: chord.root.note.rawValue)
                    .frame(width: width)
                if isInteractive && shapes.count > 1 {
                    HStack(spacing: 10) {
                        Button {
                            index = (index + shapes.count - 1) % shapes.count
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .accessibilityLabel("Previous shape")
                        Text("\(min(index, shapes.count - 1) + 1) of \(shapes.count)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        Button {
                            index = (index + 1) % shapes.count
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .accessibilityLabel("Next shape")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .buttonStyle(.borderless)
                }
            }
        }
        .onChange(of: chord) { index = 0 }
    }
}

#Preview {
    HStack {
        ChordDiagramView(voicing: ChordVoicing(frets: [0, 1, 0, 2, 3, -1], barre: nil), rootPitchClass: 0)
            .frame(width: 100)
        ChordDiagramView(voicing: ChordVoicing(frets: [1, 3, 3, 3, 1, -1], barre: 1), rootPitchClass: 10)
            .frame(width: 100)
        ChordDiagramView(voicing: ChordVoicing(frets: [5, 6, 7, 7, 5, -1], barre: 5), rootPitchClass: 2)
            .frame(width: 100)
    }
    .padding()
}
