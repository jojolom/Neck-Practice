//
//  FretboardView.swift
//  Guitar Man
//

import SwiftUI

/// A visual representation of the guitar neck.
///
/// **Single-position mode** (Note Guesser): pass `highlightedPosition`.
/// **Multi-position mode** (Triad / Pentatonic): pass `highlightedPositions` and optionally
/// `rootPosition` / `rootPositions`.
///
/// The scroll view auto-centers the active shape whenever `highlightedPositions` changes.
/// Shapes near the nut scroll fully left; shapes near the highest fret scroll fully right.
struct FretboardView: View {

    // ── Inputs ────────────────────────────────────────────────────────────
    var highlightedPosition: FretboardPosition? = nil        // single-dot mode
    var highlightedPositions: Set<FretboardPosition> = []    // multi-dot mode
    var rootPosition: FretboardPosition? = nil               // root ring (Triad)
    var rootPositions: Set<FretboardPosition> = []           // orange roots (Pentatonic)
    var answerResult: Bool? = nil
    var onTap: ((FretboardPosition) -> Void)? = nil
    var maxFret: Int = 5
    var showNoteLabels: Bool = false

    // ── Layout constants ──────────────────────────────────────────────────
    private let stringSpacing: CGFloat = 36
    private let fretSpacing: CGFloat   = 54
    private let dotRadius: CGFloat     = 14
    private let nutWidth: CGFloat      = 5
    private let openColWidth: CGFloat  = 44

    private let fretMarkers: Set<Int> = [3, 5, 7, 9, 12]

    // ── Derived ───────────────────────────────────────────────────────────

    private var allHighlighted: Set<FretboardPosition> {
        var set = highlightedPositions
        if let p = highlightedPosition { set.insert(p) }
        return set
    }

    /// Pixel x-coordinate of the centre of the highlighted shape in the scroll content.
    private var shapeCentreX: CGFloat {
        let frets = allHighlighted.map(\.fret)
        let lo = frets.min() ?? 1
        let hi = frets.max() ?? 1
        let left  = openColWidth + CGFloat(lo - 1) * fretSpacing
        let right = openColWidth + CGFloat(hi) * fretSpacing
        return (left + right) / 2
    }

    // ── Scroll state (iOS 17+) ────────────────────────────────────────────
    @State private var scrollPosition = ScrollPosition(idType: Int.self)

    var body: some View {
        let totalStrings = stringCount
        let totalFrets   = maxFret
        let neckHeight   = CGFloat(totalStrings - 1) * stringSpacing
        let totalWidth   = openColWidth + CGFloat(totalFrets) * fretSpacing + dotRadius

        // GeometryReader gives us the viewport width so we can compute the exact offset.
        GeometryReader { geo in
            let viewportWidth = geo.size.width

            ScrollView(.horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {

                    // ── String lines ──────────────────────────────────────
                    ForEach(0..<totalStrings, id: \.self) { s in
                        let y = CGFloat(s) * stringSpacing
                        Path { p in
                            p.move(to:    CGPoint(x: openColWidth, y: y))
                            p.addLine(to: CGPoint(x: totalWidth - dotRadius, y: y))
                        }
                        .stroke(Color(.systemGray2), lineWidth: stringThickness(for: s))
                    }

                    // ── Nut ───────────────────────────────────────────────
                    Path { p in
                        p.move(to:    CGPoint(x: openColWidth, y: 0))
                        p.addLine(to: CGPoint(x: openColWidth, y: neckHeight))
                    }
                    .stroke(Color(.systemGray2), lineWidth: nutWidth)

                    // ── Fret lines ────────────────────────────────────────
                    ForEach(1...totalFrets, id: \.self) { f in
                        let x = openColWidth + CGFloat(f) * fretSpacing
                        Path { p in
                            p.move(to:    CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: neckHeight))
                        }
                        .stroke(Color(.systemGray), lineWidth: 1.5)
                    }

                    // ── Fret inlay markers ────────────────────────────────
                    ForEach(1...totalFrets, id: \.self) { f in
                        if fretMarkers.contains(f) {
                            let x = openColWidth + CGFloat(f) * fretSpacing - fretSpacing / 2
                            Circle()
                                .fill(Color(.systemGray2))
                                .frame(width: 6, height: 6)
                                .position(x: x, y: neckHeight / 2)
                        }
                    }

                    // ── Fret number labels ────────────────────────────────
                    ForEach(1...totalFrets, id: \.self) { f in
                        let x = openColWidth + CGFloat(f) * fretSpacing - fretSpacing / 2
                        Text("\(f)")
                            .font(.caption)
                            .foregroundStyle(Color(.systemGray))
                            .frame(width: fretSpacing, alignment: .center)
                            .position(x: x, y: neckHeight + 20)
                    }

                    // ── Open-string labels ────────────────────────────────
                    ForEach(0..<totalStrings, id: \.self) { s in
                        Text(standardTuning[s].description)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color(.systemGray))
                            .frame(width: openColWidth - 8, alignment: .center)
                            .position(x: (openColWidth - 8) / 2,
                                      y: CGFloat(s) * stringSpacing)
                    }

                    // ── Fretted dots ──────────────────────────────────────
                    ForEach(1...totalFrets, id: \.self) { f in
                        ForEach(0..<totalStrings, id: \.self) { s in
                            let pos           = FretboardPosition(stringIndex: s, fret: f)
                            let isHighlighted = allHighlighted.contains(pos)
                            let isMultiRoot   = rootPositions.contains(pos)
                            let isSingleRoot  = rootPosition == pos
                            let x = openColWidth + CGFloat(f) * fretSpacing - fretSpacing / 2
                            let y = CGFloat(s) * stringSpacing

                            ZStack {
                                // White ring for the singular Triad root
                                if isSingleRoot {
                                    Circle()
                                        .stroke(Color.white, lineWidth: 3)
                                        .frame(width: dotRadius * 2 + 6,
                                               height: dotRadius * 2 + 6)
                                }

                                Circle()
                                    .fill(dotFill(isHighlighted: isHighlighted,
                                                  isMultiRoot: isMultiRoot))
                                    .frame(width: dotRadius * 2, height: dotRadius * 2)
                                    .shadow(color: isHighlighted
                                                ? dotFill(isHighlighted: true,
                                                          isMultiRoot: isMultiRoot).opacity(0.45)
                                                : .clear,
                                            radius: 6)

                                // Non-highlighted label (Explore / showNoteLabels)
                                if showNoteLabels && !isHighlighted {
                                    Text(pos.note.description)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color(.systemGray))
                                }

                                // Highlighted label — always visible on multi-dot modes,
                                // revealed after answer in single-dot (Note Guesser) mode
                                if isHighlighted {
                                    let showLabel = highlightedPositions.isEmpty
                                        ? answerResult != nil          // single-dot: after answer
                                        : true                         // multi-dot: always
                                    if showLabel {
                                        Text(pos.note.description)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                            }
                            .position(x: x, y: y)
                            .onTapGesture { onTap?(pos) }
                            .animation(.spring(duration: 0.25), value: isHighlighted)
                        }
                    }
                }
                .frame(width: totalWidth, height: neckHeight + 40)
                .padding(.vertical, 20)
            }
            .scrollPosition($scrollPosition)
            .onAppear {
                scrollPosition.scrollTo(x: centeredOffset(shapeCentreX,
                                                           viewportWidth: viewportWidth,
                                                           contentWidth: totalWidth))
            }
            .onChange(of: shapeCentreX) { _, newCentre in
                withAnimation(.easeInOut(duration: 0.4)) {
                    scrollPosition.scrollTo(x: centeredOffset(newCentre,
                                                               viewportWidth: viewportWidth,
                                                               contentWidth: totalWidth))
                }
            }
        }
    }

    // MARK: - Helpers

    /// The scroll x offset that places `centre` in the middle of the viewport,
    /// clamped so we never scroll past the content edges.
    private func centeredOffset(_ centre: CGFloat,
                                 viewportWidth: CGFloat,
                                 contentWidth: CGFloat) -> CGFloat {
        let ideal = centre - viewportWidth / 2
        return max(0, min(ideal, contentWidth - viewportWidth))
    }

    private func dotFill(isHighlighted: Bool, isMultiRoot: Bool = false) -> Color {
        guard isHighlighted else { return Color(.systemGray5) }
        switch answerResult {
        case .none:       return isMultiRoot ? .orange : Color(.systemIndigo)
        case .some(true): return .green
        case .some(false): return .red
        }
    }

    private func stringThickness(for stringIndex: Int) -> CGFloat {
        0.8 + CGFloat(stringIndex) * 0.35
    }
}

// stringCount is defined in Guitar ManModelsFretboard.swift
private var stringCount: Int { standardTuning.count }

#Preview {
    FretboardView(
        highlightedPosition: FretboardPosition(stringIndex: 2, fret: 3),
        answerResult: nil,
        maxFret: 5,
        showNoteLabels: true
    )
    .frame(height: 260)
    .padding()
}
