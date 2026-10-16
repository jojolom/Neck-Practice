//
//  FretboardView.swift
//  Neck Practice
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
    /// Positions that should always show green + label (the correct answer on a wrong guess).
    var correctPositions: Set<FretboardPosition> = []
    /// User-selected positions (shown in yellow before submit, green/red after).
    var selectedPositions: Set<FretboardPosition> = []
    var answerResult: Bool? = nil
    var onTap: ((FretboardPosition) -> Void)? = nil
    var maxFret: Int = 5
    var showNoteLabels: Bool = false
    /// When false, suppresses note name labels on highlighted dots (used in Pentatonic step 2).
    var showHighlightedLabels: Bool = true
    /// When true, fret numbers sit on the fret line; when false (default), centered between frets.
    var fretNumbersOnLine: Bool = false
    /// When true, skip auto-scroll-to-shape on highlight changes (useful for full-neck views).
    var disableAutoScroll: Bool = false
    /// Optional key/quality context used to spell note labels enharmonically
    /// correctly. When set, an A♭ in an F-minor context renders as "A♭" instead
    /// of "G♯". Non-diatonic notes fall back to the default sharp spelling.
    var keyContext: KeyContext? = nil

    /// Tuple-style struct describing a (key root, major/minor) context for
    /// rendering correctly-spelled note labels.
    struct KeyContext: Equatable {
        let root: Note
        let isMinor: Bool
    }

    /// Labels that replace the note name on specific dots (a note spelled for its key, or a
    /// scale degree like "♭3").
    var customLabels: [FretboardPosition: String] = [:]

    /// Returns the proper enharmonic spelling for `note` given the current
    /// key context, or the chromatic default if there's no context.
    private func label(for note: Note) -> String {
        guard let ctx = keyContext else { return note.description }
        return note.spelled(inKey: ctx.root, asMinor: ctx.isMinor)
    }

    /// The custom label for `position` if there is one, else its note name.
    private func label(for position: FretboardPosition) -> String {
        customLabels[position] ?? label(for: position.note)
    }

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

    /// The frets the highlighted shape spans (open strings sit in the fixed column, so they
    /// don't count unless the shape is nothing but open strings).
    private var shapeSpan: ClosedRange<Int> {
        let all = allHighlighted.map(\.fret)
        let fretted = all.filter { $0 > 0 }
        let frets = fretted.isEmpty ? all : fretted
        let lo = max(frets.min() ?? 1, 1)
        return lo...max(frets.max() ?? lo, lo)
    }

    /// The id of an invisible marker over the shape: the scroll view centres it.
    private static let shapeMarkerID = "fretboard.shape"

    var body: some View {
        let totalStrings = stringCount
        let totalFrets   = maxFret
        let neckHeight   = CGFloat(totalStrings - 1) * stringSpacing
        let scrollContentWidth = CGFloat(totalFrets) * fretSpacing + dotRadius + nutWidth
        let span = shapeSpan

        GeometryReader { _ in
            HStack(alignment: .top, spacing: 0) {

                // ── Fixed string labels (EADGBE) / open-string dots ──
                ZStack(alignment: .topLeading) {
                    ForEach(0..<totalStrings, id: \.self) { s in
                        let openPos = FretboardPosition(stringIndex: s, fret: 0)
                        let isOpenHighlighted = allHighlighted.contains(openPos)
                        let isOpenRoot = rootPositions.contains(openPos)
                        let isOpenCorrect = correctPositions.contains(openPos)
                        let isOpenSelected = selectedPositions.contains(openPos)
                        let openDotShown = isOpenHighlighted || isOpenRoot || isOpenCorrect || isOpenSelected

                        if openDotShown {
                            // Show the dot in the fixed column so it's always visible
                            let fill = dotColor(pos: openPos,
                                                isHighlighted: isOpenHighlighted,
                                                isMultiRoot: isOpenRoot,
                                                isCorrect: isOpenCorrect,
                                                isSelected: isOpenSelected)
                            ZStack {
                                Circle()
                                    .fill(fill)
                                    .frame(width: dotRadius * 2, height: dotRadius * 2)
                                    .shadow(color: fill.opacity(0.45), radius: 6)

                                if showHighlightedLabels {
                                    Text(label(for: openPos))
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .position(x: openColWidth / 2,
                                      y: CGFloat(s) * stringSpacing)
                            .onTapGesture { onTap?(openPos) }
                        } else {
                            Text(standardTuning[s].description)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary.opacity(0.7))
                                .position(x: openColWidth / 2,
                                          y: CGFloat(s) * stringSpacing)
                        }
                    }
                }
                .frame(width: openColWidth, height: neckHeight + 40)
                .padding(.vertical, 20)

                // ── Scrollable fretboard ──────────────────────────────
                ScrollViewReader { scroller in
                ScrollView(.horizontal, showsIndicators: false) {
                    ZStack(alignment: .topLeading) {

                        // ── The shape's frets, for scrolling to ─────────
                        // Laid out by width, not `position` (which would make the marker the
                        // whole neck, so the scroll always centred the middle of the neck).
                        HStack(spacing: 0) {
                            Color.clear
                                .frame(width: CGFloat(span.lowerBound - 1) * fretSpacing, height: 1)
                            Color.clear
                                .frame(width: CGFloat(span.count) * fretSpacing, height: 1)
                                .id(Self.shapeMarkerID)
                        }
                        .accessibilityHidden(true)

                        // ── String lines ─────────────────────────────
                        ForEach(0..<totalStrings, id: \.self) { s in
                            let y = CGFloat(s) * stringSpacing
                            Path { p in
                                p.move(to:    CGPoint(x: 0, y: y))
                                p.addLine(to: CGPoint(x: scrollContentWidth - dotRadius, y: y))
                            }
                            .stroke(Color.primary, lineWidth: stringThickness(for: s))
                        }

                        // ── Nut ──────────────────────────────────────
                        Path { p in
                            p.move(to:    CGPoint(x: 0, y: 0))
                            p.addLine(to: CGPoint(x: 0, y: neckHeight))
                        }
                        .stroke(Color.primary, lineWidth: nutWidth)

                        // ── Fret lines ───────────────────────────────
                        ForEach(1...totalFrets, id: \.self) { f in
                            let x = CGFloat(f) * fretSpacing
                            Path { p in
                                p.move(to:    CGPoint(x: x, y: 0))
                                p.addLine(to: CGPoint(x: x, y: neckHeight))
                            }
                            .stroke(Color.primary.opacity(0.7), lineWidth: 1.5)
                        }

                        // ── Fret inlay markers ───────────────────────
                        ForEach(1...totalFrets, id: \.self) { f in
                            if fretMarkers.contains(f) {
                                let x = CGFloat(f) * fretSpacing - fretSpacing / 2
                                Circle()
                                    .fill(Color.primary.opacity(0.5))
                                    .frame(width: 6, height: 6)
                                    .position(x: x, y: neckHeight / 2)
                            }
                        }

                        // ── Fret number labels ───────────────────────
                        ForEach(1...totalFrets, id: \.self) { f in
                            let onLineX = CGFloat(f) * fretSpacing
                            let centerX = CGFloat(f) * fretSpacing - fretSpacing / 2
                            let x = fretNumbersOnLine ? onLineX : centerX
                            Text("\(f)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(fretMarkers.contains(f) ? Color.blue : .primary.opacity(0.5))
                                .frame(width: fretSpacing, alignment: .center)
                                .position(x: x, y: neckHeight + 20)
                        }

                        // ── Fretted dots (including open strings) ────
                        ForEach(0...totalFrets, id: \.self) { f in
                            ForEach(0..<stringCount, id: \.self) { s in
                                dotView(fret: f, stringIndex: s)
                            }
                        }
                    }
                    .frame(width: scrollContentWidth, height: neckHeight + 40)
                    .padding(.vertical, 20)
                }
                .onAppear { scrollToShape(scroller, animated: false) }
                // Centre the shape whenever it moves or the neck changes length. The scroll waits
                // a turn of the run loop so it measures the new layout, not the one before (a
                // neck that changed length with the shape left the shape half out of view).
                .onChange(of: [span.lowerBound, span.upperBound, totalFrets]) {
                    scrollToShape(scroller, animated: true)
                }
                }
            }
        }
    }

    private func scrollToShape(_ scroller: ScrollViewProxy, animated: Bool) {
        guard !disableAutoScroll, !allHighlighted.isEmpty else { return }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.4)) {
                    scroller.scrollTo(Self.shapeMarkerID, anchor: .center)
                }
            } else {
                scroller.scrollTo(Self.shapeMarkerID, anchor: .center)
            }
        }
    }

    // MARK: - Helpers

    /// Renders a single dot (and optional label) for a given fret + string.
    /// Extracted into its own function so Swift's type checker doesn't time out
    /// on the large body closure.
    @ViewBuilder
    private func dotView(fret: Int, stringIndex: Int) -> some View {
        let pos          = FretboardPosition(stringIndex: stringIndex, fret: fret)
        let isHighlighted = allHighlighted.contains(pos)
        let isMultiRoot  = rootPositions.contains(pos)
        let isSingleRoot = rootPosition == pos
        let isCorrect    = correctPositions.contains(pos)
        let isSelected   = selectedPositions.contains(pos)
        let showDot      = isHighlighted || isCorrect || isSelected

        // For fret 0 (open strings), only render when highlighted — otherwise the
        // open-string letter label handles it.
        let renderDot = fret > 0 || showDot || isMultiRoot

        let x = fret == 0
            ? -openColWidth / 2                                          // off-screen left (covered by fixed labels)
            : CGFloat(fret) * fretSpacing - fretSpacing / 2
        let y = CGFloat(stringIndex) * stringSpacing

        if renderDot {
            let fill = dotColor(pos: pos,
                                isHighlighted: isHighlighted,
                                isMultiRoot: isMultiRoot,
                                isCorrect: isCorrect,
                                isSelected: isSelected)

            ZStack {
                if isSingleRoot {
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: dotRadius * 2 + 6, height: dotRadius * 2 + 6)
                }

                Circle()
                    .fill(fill)
                    .frame(width: dotRadius * 2, height: dotRadius * 2)
                    .shadow(color: showDot ? fill.opacity(0.45) : .clear,
                            radius: 6)

                if showNoteLabels && !isHighlighted && !isCorrect && !isSelected {
                    Text(label(for: pos))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                }

                if (isHighlighted || isCorrect) && showHighlightedLabels {
                    let showLabel: Bool = isCorrect || (highlightedPositions.isEmpty ? answerResult != nil : true)
                    if showLabel {
                        Text(label(for: pos))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .position(x: x, y: y)
            .onTapGesture { onTap?(pos) }
            .animation(.spring(duration: 0.25), value: showDot)
        }
    }

    private func dotColor(pos: FretboardPosition, isHighlighted: Bool,
                          isMultiRoot: Bool = false, isCorrect: Bool = false,
                          isSelected: Bool = false) -> Color {
        // Correct positions always green
        if isCorrect { return .green }
        // Selected dots: yellow before submit, green/red after submit
        if isSelected {
            guard answerResult != nil else { return .yellow }
            return correctPositions.contains(pos) ? .green : .red
        }
        guard isHighlighted else { return Color(.systemGray3) }
        // Single-dot mode: green on correct, red on wrong
        if highlightedPositions.isEmpty {
            if answerResult == true  { return .green }
            if answerResult == false { return .red   }
        }
        return isMultiRoot ? .orange : Color(.systemIndigo)
    }

    private func stringThickness(for stringIndex: Int) -> CGFloat {
        0.8 + CGFloat(stringIndex) * 0.35
    }
}

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
