//
//  TriadView.swift
//  Guitar Man
//
//  Two-step exercise:
//  Step 1 — Identify the quality (Major / Minor)
//  Step 2 — Name the root note
//

import SwiftUI

// MARK: - Answer step state

private enum AnswerStep: Equatable {
    case quality                        // waiting for Major/Minor tap
    case root(qualityWasCorrect: Bool)  // quality answered; now pick root note
}

// MARK: - TriadView

struct TriadView: View {

    @State private var session       = TriadSession()
    @State private var step: AnswerStep = .quality
    @State private var answerResult: Bool? = nil   // drives dot colour
    @State private var isLocked      = false
    @State private var showSettings  = false
    @State private var showRootHint  = false       // reveals root ring after quality answer

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Stats bar ────────────────────────────────────────────
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

                // ── Prompt ───────────────────────────────────────────────
                promptArea

                // ── Fretboard ────────────────────────────────────────────
                if let q = session.currentQuestion {
                    FretboardView(
                        highlightedPositions: Set(q.triadPositions),
                        rootPosition: showRootHint ? q.rootPosition : nil,
                        answerResult: answerResult,
                        maxFret: max(q.maxFret + 1, session.maxFret),
                        showNoteLabels: false
                    )
                    .frame(height: 260)
                    .padding(.horizontal, 8)
                }

                Divider()

                // ── Answer area ──────────────────────────────────────────
                answerArea
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                Spacer()
            }
            .navigationTitle("Triad Trainer")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
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
                TriadSettingsView(session: session)
            }
            .onAppear {
                session.start()
            }
            .onChange(of: session.currentQuestion?.shape.id) {
                // New question — reset all step state
                step         = .quality
                answerResult = nil
                showRootHint = false
                isLocked     = false
            }
        }
    }

    // MARK: - Prompt

    @ViewBuilder
    private var promptArea: some View {
        Group {
            switch step {
            case .quality:
                VStack(spacing: 4) {
                    Text("What type of chord is this?")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if let q = session.currentQuestion {
                        Text(q.shape.stringGroup.displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            case .root(let qualityWasCorrect):
                VStack(spacing: 4) {
                    // Show what quality they're looking at
                    if let q = session.currentQuestion {
                        Text(q.shape.quality.displayName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(qualityWasCorrect ? .green : .primary)
                    }
                    Text("What is the root note?")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("The highlighted dot is the root")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .frame(minHeight: 64)
    }

    // MARK: - Answer area

    @ViewBuilder
    private var answerArea: some View {
        switch step {
        case .quality:
            // Two large buttons
            HStack(spacing: 16) {
                ForEach(TriadQuality.allCases, id: \.self) { quality in
                    Button {
                        handleQualityAnswer(quality)
                    } label: {
                        Text(quality.displayName)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLocked)
                }
            }

        case .root:
            // 12 note buttons (3×4 grid)
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

    private func handleQualityAnswer(_ quality: TriadQuality) {
        guard !isLocked else { return }
        let correct = session.answerQuality(quality)
        isLocked = true

        withAnimation(.easeInOut(duration: 0.2)) {
            answerResult = correct ? true : false
        }

        if correct {
            // Brief green flash then move to root step
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                withAnimation {
                    answerResult = nil
                    showRootHint = true
                    step = .root(qualityWasCorrect: true)
                    isLocked = false
                }
            }
        } else {
            // Show red for 1.5s, reveal correct quality in prompt, then move to root step
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation {
                    answerResult = nil
                    showRootHint = true
                    step = .root(qualityWasCorrect: false)
                    isLocked = false
                }
            }
        }
    }

    private func handleRootAnswer(_ note: Note) {
        guard !isLocked, case .root = step else { return }
        let correct = session.answerRoot(note)
        isLocked = true

        withAnimation(.easeInOut(duration: 0.15)) {
            answerResult = correct ? true : false
        }

        let delay: Double = correct ? 0.6 : 2.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation { answerResult = nil }
            isLocked = false
            session.advance()
        }
    }

    private func resetSession() {
        step = .quality
        answerResult = nil
        showRootHint = false
        isLocked = false
        session.reset()
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
    TriadView()
}
