//
//  PentatonicView.swift
//  Guitar Man
//
//  Two-step exercise:
//  Step 1 — Identify which box position this is (1–5)
//  Step 2 — Name the root note (major or minor pentatonic)
//

import SwiftUI

// MARK: - Answer step state

private enum PentatonicAnswerStep: Equatable {
    case position                            // waiting for 1–5 tap
    case root(positionWasCorrect: Bool)      // position answered; now pick root note
}

// MARK: - PentatonicView

struct PentatonicView: View {

    @State private var session      = PentatonicSession()
    @State private var step: PentatonicAnswerStep = .position
    @State private var answerResult: Bool? = nil
    @State private var isLocked     = false
    @State private var showSettings = false
    @State private var showRootDots = false

    // Snapshot of the question currently shown on screen.
    // Updated synchronously — never via onChange — so the fretboard
    // never disappears between advance() and the next draw.
    @State private var displayedQuestion: PentatonicQuestion? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Stats bar ─────────────────────────────────────────────
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

                // ── Prompt ────────────────────────────────────────────────
                promptArea

                // ── Fretboard ─────────────────────────────────────────────
                if let q = displayedQuestion {
                    FretboardView(
                        highlightedPositions: Set(q.shapePositions),
                        rootPositions: showRootDots ? q.rootPositions : [],
                        answerResult: answerResult,
                        maxFret: q.maxFret + 1,
                        showNoteLabels: false
                    )
                    .frame(height: 260)
                    .padding(.horizontal, 8)
                }

                Divider()

                // ── Answer area ───────────────────────────────────────────
                answerArea
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Spacer()
            }
            .navigationTitle("Pentatonic Trainer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Restart", role: .destructive) {
                        withAnimation { resetSession() }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                PentatonicSettingsView(session: session)
            }
            .onAppear {
                session.start()
                displayedQuestion = session.currentQuestion
            }
        }
    }

    // MARK: - Prompt

    @ViewBuilder
    private var promptArea: some View {
        Group {
            switch step {
            case .position:
                VStack(spacing: 4) {
                    Text("Which position is this?")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Tap a number 1–5")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

            case .root(let positionWasCorrect):
                VStack(spacing: 4) {
                    if let q = displayedQuestion {
                        Text("Position \(q.shape.id)")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(positionWasCorrect ? .green : .primary)
                        Text("\(q.quality.displayName) Pentatonic")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text("What is the root note?")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Orange dots are the root positions")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .frame(minHeight: 72)
    }

    // MARK: - Answer area

    @ViewBuilder
    private var answerArea: some View {
        switch step {
        case .position:
            HStack(spacing: 10) {
                ForEach(1...5, id: \.self) { pos in
                    Button {
                        handlePositionAnswer(pos)
                    } label: {
                        Text("\(pos)")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLocked)
                }
            }

        case .root:
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                spacing: 10
            ) {
                ForEach(Note.allCases) { note in
                    Button {
                        handleRootAnswer(note)
                    } label: {
                        Text(note.description)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLocked)
                }
            }
        }
    }

    // MARK: - Handlers

    private func handlePositionAnswer(_ position: Int) {
        guard !isLocked else { return }
        let correct = session.answerPosition(position)
        isLocked = true

        withAnimation(.easeInOut(duration: 0.2)) {
            answerResult = correct
        }

        let delay: Double = correct ? 0.6 : 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation {
                answerResult = nil
                showRootDots = true
                step = .root(positionWasCorrect: correct)
                isLocked = false
            }
        }
    }

    private func handleRootAnswer(_ note: Note) {
        guard !isLocked, case .root = step else { return }
        let correct = session.answerRoot(note)
        isLocked = true

        withAnimation(.easeInOut(duration: 0.15)) {
            answerResult = correct
        }

        let delay: Double = correct ? 0.6 : 2.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            // Reset feedback and step state first
            answerResult = nil
            showRootDots = false
            step         = .position
            isLocked     = false
            // Draw the next question and update the snapshot synchronously
            session.advance()
            displayedQuestion = session.currentQuestion
        }
    }

    private func resetSession() {
        answerResult      = nil
        showRootDots      = false
        step              = .position
        isLocked          = false
        session.reset()
        displayedQuestion = session.currentQuestion
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

#Preview {
    PentatonicView()
}
