//
//  ScaleReferenceView.swift
//  Neck Practice
//
//  Reference tool — pick a root note and scale type to see
//  3-note-per-string positions across the fretboard.
//

import SwiftUI

// MARK: - ScaleType

private enum ScaleType: String, CaseIterable, Identifiable {
    case major = "Major"
    case minor = "Minor"

    var id: String { rawValue }

    var isMinor: Bool { self == .minor }

    /// Semitone intervals from the root.
    var intervals: [Int] {
        switch self {
        case .major: return [0, 2, 4, 5, 7, 9, 11]
        case .minor: return [0, 2, 3, 5, 7, 8, 10]
        }
    }

    /// Scale degree labels for display.
    var degreeLabels: [String] {
        switch self {
        case .major: return ["R", "2", "3", "4", "5", "6", "7"]
        case .minor: return ["R", "2", "♭3", "4", "5", "♭6", "♭7"]
        }
    }
}

// MARK: - ShapeAnchor

/// CAGED-style shape variants: the scale played from the root sitting on
/// either the 6th string (E-shape) or 5th string (A-shape).
private enum ShapeAnchor: String, CaseIterable, Identifiable {
    case sixthString = "6th String Root"
    case fifthString = "5th String Root"

    var id: String { rawValue }

    /// Which string the root sits on (0 = high e, 5 = low E).
    var rootStringIndex: Int {
        switch self {
        case .sixthString: return 5
        case .fifthString: return 4
        }
    }
}

// MARK: - ScaleShape

/// A scale-shape template defined as fret offsets per string, where each
/// offset is measured from the fret on which the root sits on the shape's
/// anchor string. Lets us transpose a single fingering to any key.
private struct ScaleShape {
    /// `offsetsByString[stringIndex]` lists the offsets (from the anchor's
    /// root fret) of every note the shape plays on that string. Empty
    /// means the string is unused.
    let offsetsByString: [[Int]]

    /// Resolves the shape into concrete fretboard positions for the given
    /// root note on the given anchor string. If transposing would push any
    /// fret below 1, the whole shape shifts up an octave so open-string
    /// edge cases stay playable.
    func positions(rootNote: Note, anchor: ShapeAnchor) -> [FretboardPosition] {
        var rootFret: Int = {
            switch anchor {
            case .sixthString: return fretOnLowE(for: rootNote)
            case .fifthString: return fretOnAString(for: rootNote)
            }
        }()
        let minOffset = offsetsByString.flatMap { $0 }.min() ?? 0
        if rootFret + minOffset < 1 { rootFret += 12 }

        var result: [FretboardPosition] = []
        for (stringIndex, offsets) in offsetsByString.enumerated() {
            for off in offsets {
                result.append(FretboardPosition(stringIndex: stringIndex, fret: rootFret + off))
            }
        }
        return result
    }
}

/// 2-octave CAGED E-shape major scale, anchored to the 6th-string root.
/// Verified against G major (root fret 3): S6 3,5 | S5 2,3,5 | S4 2,4,5 |
/// S3 2,4,5 | S2 3,5 | S1 2,3
private let sixthStringMajorShape = ScaleShape(offsetsByString: [
    [-1,  0],         // S1 (high e) — 7, R
    [ 0,  2],         // S2 (B)      — 5, 6
    [-1,  1,  2],     // S3 (G)      - 2, 3, 4
    [-1,  1,  2],     // S4 (D)      — 6, 7, R
    [-1,  0,  2],     // S5 (A)      — 3, 4, 5
    [ 0,  2],         // S6 (low E)  — R, 2
])

/// 2-octave CAGED A-shape major scale, anchored to the 5th-string root.
/// Verified against C major (root fret 3): S5 3,5 | S4 2,3,5 | S3 2,4,5 |
/// S2 3,5,6 | S1 3,5,7,8
private let fifthStringMajorShape = ScaleShape(offsetsByString: [
    [ 0,  2,  4,  5], // S1 (high e) — 5, 6, 7, R
    [ 0,  2,  3],     // S2 (B)      — 2, 3, 4
    [-1,  1,  2],     // S3 (G)      — 6, 7, R
    [-1,  0,  2],     // S4 (D)      — 3, 4, 5
    [ 0,  2],         // S5 (A)      — R, 2
    [],               // S6 (low E)  — unused
])

/// 2-octave natural minor scale anchored to the 6th-string root.
/// Verified against A minor (root fret 5): S6 5,7,8 | S5 5,7,8 | S4 5,7,9 |
/// S3 5,7 | S2 5,6,8 | S1 5
private let sixthStringMinorShape = ScaleShape(offsetsByString: [
    [ 0],             // S1 (high e) — R
    [ 0,  1,  3],     // S2 (B)      — 5, ♭6, ♭7
    [ 0,  2],         // S3 (G)      — ♭3, 4
    [ 0,  2,  4],     // S4 (D)      — ♭7, R, 2
    [ 0,  2,  3],     // S5 (A)      — 4, 5, ♭6
    [ 0,  2,  3],     // S6 (low E)  — R, 2, ♭3
])

/// 2-octave natural minor scale anchored to the 5th-string root.
/// Verified against D minor (root fret 5): S5 5,7,8 | S4 5,7,8 | S3 5,7 |
/// S2 5,6,8 | S1 5,6,8,10
private let fifthStringMinorShape = ScaleShape(offsetsByString: [
    [ 0,  1,  3,  5], // S1 (high e) — 5, ♭6, ♭7, R
    [ 0,  1,  3],     // S2 (B)      — 2, ♭3, 4
    [ 0,  2],         // S3 (G)      — ♭7, R
    [ 0,  2,  3],     // S4 (D)      — 4, 5, ♭6
    [ 0,  2,  3],     // S5 (A)      — R, 2, ♭3
    [],               // S6 (low E)  — unused
])

// MARK: - ScaleReferenceView

struct ScaleReferenceView: View {

    @State private var rootNote: Note = .c
    @State private var scaleType: ScaleType = .major
    @State private var shapeAnchor: ShapeAnchor = .sixthString
    @State private var playingPosition: FretboardPosition? = nil
    @State private var isPlaying = false
    @Environment(AudioSettings.self) private var audioSettings

    /// Conventional key roots for the current scale type, in circle-of-fifths order.
    private var availableRoots: [Note] {
        Note.circleOfFifthsKeys(asMinor: scaleType.isMinor)
    }

    // MARK: - Scale computation

    /// Ordered scale notes for the degree strip.
    private var orderedScaleNotes: [Note] {
        scaleType.intervals.map { rootNote.advanced(by: $0) }
    }

    /// The scale shape positions for the current root, scale type, and anchor.
    private var currentPosition: [FretboardPosition] {
        templateForCurrent.positions(rootNote: rootNote, anchor: shapeAnchor)
    }

    /// Hand-templated shape for the current scale type + anchor.
    private var templateForCurrent: ScaleShape {
        switch (scaleType, shapeAnchor) {
        case (.major, .sixthString): return sixthStringMajorShape
        case (.major, .fifthString): return fifthStringMajorShape
        case (.minor, .sixthString): return sixthStringMinorShape
        case (.minor, .fifthString): return fifthStringMinorShape
        }
    }

    /// Positions as a set for FretboardView highlighting.
    private var positionSet: Set<FretboardPosition> {
        Set(currentPosition)
    }

    /// Root positions within the current position.
    private var rootPositionSet: Set<FretboardPosition> {
        if let pos = playingPosition { return [pos] }
        return Set(currentPosition.filter { $0.note == rootNote })
    }

    /// Max fret for the current position.
    private var positionMaxFret: Int {
        max(currentPosition.map(\.fret).max() ?? 5, 5)
    }

    /// Fret range label.
    private var fretRangeText: String {
        let frets = currentPosition.map(\.fret)
        guard let lo = frets.min(), let hi = frets.max() else { return "" }
        return "Frets \(lo)–\(hi)"
    }

    /// The note currently being played.
    private var playingNote: Note? { playingPosition?.note }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // ── Root note picker ─────────────────────────────
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availableRoots) { note in
                                Button {
                                    rootNote = note
                                } label: {
                                    Text(note.keyName(asMinor: scaleType.isMinor))
                                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        .foregroundStyle(rootNote == note ? .white : .primary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(rootNote == note ? Color.orange : Color(.secondarySystemBackground))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.top, 12)

                    // ── Scale type picker ────────────────────────────
                    Picker("Scale Type", selection: $scaleType) {
                        ForEach(ScaleType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    // ── Title + fret range ───────────────────────────
                    HStack {
                        Text("\(rootNote.keyName(asMinor: scaleType.isMinor)) \(scaleType.rawValue)")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Spacer()
                        Text(fretRangeText)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    // ── Shape anchor picker ──────────────────────────
                    Picker("Shape", selection: $shapeAnchor) {
                        ForEach(ShapeAnchor.allCases) { anchor in
                            Text(anchor.rawValue).tag(anchor)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Divider()
                        .padding(.top, 10)

                    // ── Scale degree strip (informational) ──────────
                    HStack(spacing: 12) {
                        ForEach(Array(orderedScaleNotes.enumerated()), id: \.offset) { index, note in
                            let isActive = playingNote == note
                            let isRoot = index == 0
                            VStack(spacing: 2) {
                                Text(scaleType.degreeLabels[index])
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(isActive ? .orange : .secondary)
                                Text(note.spelled(inKey: rootNote, asDegree: index, keyIsMinor: scaleType.isMinor))
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundStyle(isActive ? .orange : isRoot ? .orange : .primary)
                            }
                            .opacity(isActive ? 1.0 : isRoot ? 1.0 : 0.7)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)

                    // ── Fretboard ────────────────────────────────────
                    FretboardView(
                        highlightedPositions: positionSet,
                        rootPositions: rootPositionSet,
                        maxFret: positionMaxFret,
                        showHighlightedLabels: true,
                        keyContext: FretboardView.KeyContext(
                            root: rootNote,
                            isMinor: scaleType.isMinor
                        )
                    )
                    .frame(height: 280)
                    .padding(.horizontal, 8)
                    .animation(.easeInOut(duration: 0.3), value: shapeAnchor)
                    .animation(.easeInOut(duration: 0.15), value: playingPosition)
                }
            }

            Divider()

            // ── Play button ──────────────────────────────────
            Button {
                playScale()
            } label: {
                Label(isPlaying ? "Playing..." : "Play Position", systemImage: isPlaying ? "speaker.wave.2.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(audioSettings.isEnabled && !isPlaying ? Color.accentColor : Color.gray.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!audioSettings.isEnabled || isPlaying)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("Scale Reference")
    }

    // MARK: - Playback

    private func playScale() {
        guard audioSettings.isEnabled, !isPlaying else { return }
        AudioPlayer.shared.stopAll()
        isPlaying = true

        // Sort by ascending MIDI note for a clean ascending run
        let path = currentPosition.sorted { $0.midiNote < $1.midiNote }
        guard !path.isEmpty else { isPlaying = false; return }

        let interval = 0.22

        for (i, position) in path.enumerated() {
            let delay = Double(i) * interval
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.1)) { playingPosition = position }
                let octave = position.midiNote / 12 - 1
                AudioPlayer.shared.playNote(position.note, octave: octave)
            }
        }

        let total = Double(path.count) * interval
        DispatchQueue.main.asyncAfter(deadline: .now() + total + 0.4) {
            withAnimation { playingPosition = nil }
            isPlaying = false
        }
    }
}

#Preview {
    NavigationStack {
        ScaleReferenceView()
            .environment(AudioSettings())
    }
}
