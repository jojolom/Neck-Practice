//
//  SightReadingView.swift
//  Neck Practice
//
//  Shows a note on a treble clef staff. The user taps the matching
//  fretboard position and presses Submit.
//

import SwiftUI

struct SightReadingView: View {

    @State private var session: SightReadingSession
    @State private var showingSettings = false

    init(override: SightReadingStepConfig? = nil) {
        let session = SightReadingSession()
        session.apply(override: override)
        _session = State(initialValue: session)
    }
    @State private var selectedPosition: FretboardPosition? = nil
    @State private var answerResult: Bool? = nil
    @State private var correctPositions: Set<FretboardPosition> = []
    @State private var isLocked = false
    @State private var isNewQuestionLocked = false

    @Environment(AudioSettings.self) private var audioSettings

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Stats bar ────────────────────────────────────
                HStack(spacing: 24) {
                    statPill(label: "Score",
                             value: "\(session.score)/\(session.totalAnswered)")
                    statPill(label: "Streak", value: "🔥 \(session.streak)")
                    statPill(label: "Accuracy",
                             value: session.totalAnswered > 0
                                ? String(format: "%.0f%%", session.accuracy * 100)
                                : "—")
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Divider().padding(.top, 12)

                // ── Staff notation ───────────────────────────────
                if let pitch = session.currentPitch {
                    ZStack(alignment: .topTrailing) {
                        StaffNotationView(pitch: pitch)
                            .frame(height: 140)
                            .padding(.horizontal, 20)

                        Button {
                            playCurrentNote()
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                                .frame(width: 36, height: 36)
                                .background(Color(.secondarySystemBackground))
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 24)
                        .padding(.top, 4)
                    }
                    .padding(.top, 8)
                } else {
                    Color.clear.frame(height: 140)
                }

                // ── Fretboard ────────────────────────────────────
                FretboardView(
                    highlightedPosition: selectedPosition,
                    correctPositions: correctPositions,
                    answerResult: answerResult,
                    onTap: { pos in handleTap(pos) },
                    maxFret: session.maxFret,
                    showNoteLabels: false,
                    showHighlightedLabels: true
                )
                .frame(height: 260)
                .padding(.horizontal, 8)

                Divider()

                // ── Submit button ────────────────────────────────
                Button {
                    submitAnswer()
                } label: {
                    Text("Submit")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(selectedPosition != nil && !isLocked
                                    ? Color.accentColor : Color.gray.opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(selectedPosition == nil || isLocked)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Spacer()
            }
            .navigationTitle("Sight Reading")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Restart", role: .destructive) {
                        resetState()
                        withAnimation { session.reset() }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SightReadingSettingsView(session: session)
            }
            .onAppear {
                session.start()
                playCurrentNote()
            }
            .onChange(of: session.currentPitch) {
                selectedPosition = nil
                answerResult = nil
                correctPositions = []
                playCurrentNote()
            }
        }
    }

    // MARK: - Interaction

    private func handleTap(_ position: FretboardPosition) {
        guard !isLocked, !isNewQuestionLocked else { return }
        selectedPosition = position
        answerResult = nil
        correctPositions = []
    }

    private func submitAnswer() {
        guard let selected = selectedPosition, !isLocked else { return }
        let correct = session.answer(position: selected)
        isLocked = true

        if correct {
            withAnimation(.easeInOut(duration: 0.2)) {
                answerResult = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                resetState()
                session.advance()
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                answerResult = false
                correctPositions = session.validPositions
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                resetState()
                session.advance()
            }
        }
    }

    private func playCurrentNote() {
        guard audioSettings.isEnabled else { return }
        isNewQuestionLocked = true
        if let pitch = session.currentPitch {
            AudioPlayer.shared.stopAll()
            // Play at the exact MIDI pitch
            let pos = session.validPositions.first
            if let pos {
                AudioPlayer.shared.playNote(at: pos)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isNewQuestionLocked = false
        }
    }

    private func resetState() {
        isLocked = false
        isNewQuestionLocked = false
        selectedPosition = nil
        answerResult = nil
        correctPositions = []
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func statPill(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Staff Notation View

/// Draws a treble clef staff with a single note head.
/// Uses guitar notation convention: written pitch = concert pitch + 1 octave.
private struct StaffNotationView: View {

    let pitch: StaffPitch

    private let lineSpacing: CGFloat = 12
    private let lineCount = 5
    private let noteHeadWidth: CGFloat = 16
    private let noteHeadHeight: CGFloat = 12

    /// Y of the bottom staff line within the drawing area.
    private var bottomLineY: CGFloat { 80 }

    /// Y coordinate for a given staff position (0 = bottom line).
    private func yForPosition(_ pos: Int) -> CGFloat {
        bottomLineY - CGFloat(pos) * (lineSpacing / 2)
    }

    var body: some View {
        Canvas { context, size in
            let staffLeft: CGFloat = 60
            let staffRight = size.width - 20

            // ── Draw 5 staff lines ───────────────────────────
            for i in 0..<lineCount {
                let y = bottomLineY - CGFloat(i) * lineSpacing
                let path = Path { p in
                    p.move(to: CGPoint(x: staffLeft, y: y))
                    p.addLine(to: CGPoint(x: staffRight, y: y))
                }
                context.stroke(path, with: .color(Color(.systemGray3)), lineWidth: 1)
            }

            // ── Treble clef ──────────────────────────────────
            let clefY = bottomLineY - 2 * lineSpacing  // center on middle line
            context.draw(
                Text("𝄞")
                    .font(.system(size: 52))
                    .foregroundColor(Color(.label)),
                at: CGPoint(x: staffLeft + 20, y: clefY - 2),
                anchor: .center
            )

            // ── Note position ────────────────────────────────
            let staffPos = pitch.staffPosition
            let noteY = yForPosition(staffPos)
            let noteX = size.width / 2 + 20

            // ── Ledger lines ─────────────────────────────────
            let ledgerHalf: CGFloat = noteHeadWidth + 4
            if staffPos < 0 {
                // Below the staff
                var pos = -2  // first ledger line below = position -2
                while pos >= staffPos - 1 {
                    let ly = yForPosition(pos)
                    let lpath = Path { p in
                        p.move(to: CGPoint(x: noteX - ledgerHalf, y: ly))
                        p.addLine(to: CGPoint(x: noteX + ledgerHalf, y: ly))
                    }
                    context.stroke(lpath, with: .color(Color(.systemGray3)), lineWidth: 1)
                    pos -= 2
                }
            }
            if staffPos > 8 {
                // Above the staff (top line = position 8)
                var pos = 10
                while pos <= staffPos + 1 {
                    let ly = yForPosition(pos)
                    let lpath = Path { p in
                        p.move(to: CGPoint(x: noteX - ledgerHalf, y: ly))
                        p.addLine(to: CGPoint(x: noteX + ledgerHalf, y: ly))
                    }
                    context.stroke(lpath, with: .color(Color(.systemGray3)), lineWidth: 1)
                    pos += 2
                }
            }

            // ── Sharp symbol ─────────────────────────────────
            if pitch.note.needsSharp {
                context.draw(
                    Text("♯")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Color(.label)),
                    at: CGPoint(x: noteX - noteHeadWidth - 8, y: noteY),
                    anchor: .center
                )
            }

            // ── Note head (filled oval) ──────────────────────
            let noteRect = CGRect(
                x: noteX - noteHeadWidth / 2,
                y: noteY - noteHeadHeight / 2,
                width: noteHeadWidth,
                height: noteHeadHeight
            )
            // Slight rotation for a more natural oval look
            var noteTransform = CGAffineTransform.identity
            noteTransform = noteTransform.translatedBy(x: noteX, y: noteY)
            noteTransform = noteTransform.rotated(by: -.pi / 8)
            noteTransform = noteTransform.translatedBy(x: -noteX, y: -noteY)

            let notePath = Path(ellipseIn: noteRect).applying(noteTransform)
            context.fill(notePath, with: .color(Color(.label)))
        }
    }
}

#Preview {
    SightReadingView()
        .environment(AudioSettings())
}
