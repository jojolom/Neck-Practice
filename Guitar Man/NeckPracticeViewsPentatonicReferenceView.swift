//
//  PentatonicReferenceView.swift
//  Neck Practice
//
//  Reference tool — pick a root note and quality to see the 5
//  pentatonic box shapes on the fretboard.
//

import SwiftUI

struct PentatonicReferenceView: View {

    @State private var rootNote: Note = .a
    @State private var quality: PentatonicQuality = .minor
    @State private var shapeIndex: Int = 0
    @State private var playingPosition: FretboardPosition? = nil
    @State private var isPlaying = false
    @Environment(AudioSettings.self) private var audioSettings

    /// Conventional key roots for the current quality, in circle-of-fifths order.
    private var availableRoots: [Note] {
        Note.circleOfFifthsKeys(asMinor: quality.isMinor)
    }

    // MARK: - Computed data

    /// Build a PentatonicQuestion for the current root + quality + shape.
    private var currentQuestion: PentatonicQuestion {
        let shape = allPentatonicShapes[shapeIndex]
        let anchorFret: Int = {
            if let rootOffset = shape.rootOffsetOnLowE {
                let baseFret = fretOnLowE(for: rootNote)
                let anchor = baseFret - rootOffset
                return anchor <= 0 ? anchor + 12 : anchor
            } else if let rootOffset = shape.rootOffsetOnAString {
                let baseFret = fretOnAString(for: rootNote)
                let anchor = baseFret - rootOffset
                return anchor <= 0 ? anchor + 12 : anchor
            }
            return fretOnLowE(for: rootNote)
        }()
        return PentatonicQuestion(shape: shape, quality: quality, rootNote: rootNote, anchorFret: anchorFret)
    }

    private var highlightedPositions: Set<FretboardPosition> {
        Set(currentQuestion.shapePositions)
    }

    private var rootPositionSet: Set<FretboardPosition> {
        if let pos = playingPosition { return [pos] }
        return currentQuestion.effectiveRootPositions
    }

    private var maxFret: Int {
        max(currentQuestion.maxFret, 5)
    }

    private var fretRangeText: String {
        let lo = currentQuestion.minFret
        let hi = currentQuestion.maxFret
        return "Frets \(lo)–\(hi)"
    }

    /// The note currently being played.
    private var playingNote: Note? { playingPosition?.note }

    /// Degree labels, notes, and full-scale degree indices for the degree strip.
    private var degreeInfo: [(label: String, note: Note, degreeIndex: Int)] {
        let effectiveRoot = currentQuestion.effectiveRootNote
        switch quality {
        case .minor:
            // Minor pentatonic: R ♭3 4 5 ♭7 → full-scale degrees 0, 2, 3, 4, 6
            let intervals = [0, 3, 5, 7, 10]
            let labels = ["R", "♭3", "4", "5", "♭7"]
            let degreeIndices = [0, 2, 3, 4, 6]
            return (0..<5).map { i in
                (labels[i], effectiveRoot.advanced(by: intervals[i]), degreeIndices[i])
            }
        case .major:
            // Major pentatonic: R 2 3 5 6 → full-scale degrees 0, 1, 2, 4, 5
            let intervals = [0, 2, 4, 7, 9]
            let labels = ["R", "2", "3", "5", "6"]
            let degreeIndices = [0, 1, 2, 4, 5]
            return (0..<5).map { i in
                (labels[i], effectiveRoot.advanced(by: intervals[i]), degreeIndices[i])
            }
        }
    }

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
                                    Text(note.keyName(asMinor: quality.isMinor))
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

                    // ── Quality picker ───────────────────────────────
                    Picker("Quality", selection: $quality) {
                        Text("Minor").tag(PentatonicQuality.minor)
                        Text("Major").tag(PentatonicQuality.major)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    // ── Title + fret range ───────────────────────────
                    HStack {
                        Text("\(currentQuestion.effectiveRootNote.keyName(asMinor: quality.isMinor)) \(quality.displayName) Pentatonic")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                        Spacer()
                        Text(fretRangeText)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    // ── Shape navigation ─────────────────────────────
                    HStack(spacing: 16) {
                        Button {
                            withAnimation { shapeIndex = max(0, shapeIndex - 1) }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(shapeIndex > 0 ? Color.accentColor : .gray.opacity(0.4))
                        }
                        .disabled(shapeIndex == 0)

                        Text("Position \(shapeIndex + 1) of 5")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        Button {
                            withAnimation { shapeIndex = min(4, shapeIndex + 1) }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(shapeIndex < 4 ? Color.accentColor : .gray.opacity(0.4))
                        }
                        .disabled(shapeIndex >= 4)
                    }
                    .padding(.top, 6)

                    Divider()
                        .padding(.top, 10)

                    // ── Degree strip (informational) ─────────────────
                    HStack(spacing: 16) {
                        ForEach(Array(degreeInfo.enumerated()), id: \.offset) { index, info in
                            let isActive = playingNote == info.note
                            let isRoot = index == 0
                            VStack(spacing: 2) {
                                Text(info.label)
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(isActive ? .orange : .secondary)
                                Text(info.note.spelled(inKey: currentQuestion.effectiveRootNote, asDegree: info.degreeIndex, keyIsMinor: quality.isMinor))
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
                        highlightedPositions: highlightedPositions,
                        rootPositions: rootPositionSet,
                        maxFret: maxFret,
                        showHighlightedLabels: true,
                        keyContext: FretboardView.KeyContext(
                            root: currentQuestion.effectiveRootNote,
                            isMinor: quality.isMinor
                        )
                    )
                    .frame(height: 280)
                    .padding(.horizontal, 8)
                    .animation(.easeInOut(duration: 0.3), value: shapeIndex)
                    .animation(.easeInOut(duration: 0.15), value: playingPosition)
                }
            }

            Divider()

            // ── Play button ──────────────────────────────────
            Button {
                playShape()
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
        .navigationTitle("Pentatonic Shapes")
    }

    // MARK: - Playback

    private func playShape() {
        guard audioSettings.isEnabled, !isPlaying else { return }
        AudioPlayer.shared.stopAll()
        isPlaying = true

        let path = currentQuestion.shapePositions.sorted { $0.midiNote < $1.midiNote }
        guard !path.isEmpty else { isPlaying = false; return }

        let interval = 0.25

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
        PentatonicReferenceView()
            .environment(AudioSettings())
    }
}
