//
//  QuizView.swift
//  Guitar Man
//

import SwiftUI

struct QuizView: View {

    @State private var session = QuizSession()
    @State private var showingSettings = false
    @State private var answerFlash: Color = .clear

    /// nil = waiting for answer, true = correct, false = wrong
    @State private var answerResult: Bool? = nil

    /// Locked choices for the current question — only regenerated when the question changes.
    @State private var choices: [Note] = []

    /// Prevents tapping another answer while feedback is showing.
    @State private var isLocked = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Stats bar ───────────────────────────────────────────────
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

                // ── Prompt ──────────────────────────────────────────────────
                Group {
                    if let pos = session.currentPosition {
                        VStack(spacing: 4) {
                            Text("What note is this?")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text(pos.stringLabel)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 20)
                    }
                }

                // ── Fretboard ───────────────────────────────────────────────
                FretboardView(
                    highlightedPosition: session.currentPosition,
                    answerResult: answerResult,
                    maxFret: session.maxFret,
                    showNoteLabels: false
                )
                .frame(height: 260)
                .padding(.horizontal, 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(answerFlash, lineWidth: 4)
                        .padding(.horizontal, 8)
                        .allowsHitTesting(false)
                )
                .animation(.easeOut(duration: 0.3), value: answerFlash)

                Divider()

                // ── Answer buttons ──────────────────────────────────────────
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                    spacing: 10
                ) {
                    ForEach(choices) { note in
                        Button {
                            handleAnswer(note)
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
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Spacer()
            }
            .navigationTitle("Quiz")
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
                        withAnimation { session.reset() }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                QuizSettingsView(session: session)
            }
            .onAppear {
                session.start()
                refreshChoices()
            }
            // Regenerate choices only when the question changes
            .onChange(of: session.currentPosition) {
                answerResult = nil
                refreshChoices()
            }
        }
    }

    // MARK: - Helpers

    private func refreshChoices() {
        guard let correct = session.currentPosition?.note else {
            choices = Array(Note.allCases.filter(\.isNatural).prefix(8))
            return
        }
        let pool = session.naturalsOnly
            ? Note.allCases.filter(\.isNatural)
            : Note.allCases
        let distractors = pool.filter { $0 != correct }.shuffled().prefix(7)
        var all = [correct] + distractors
        all.shuffle()
        choices = all
    }

    private func handleAnswer(_ note: Note) {
        guard !isLocked else { return }
        let correct = session.answer(note)
        answerResult = correct

        withAnimation(.easeInOut(duration: 0.15)) {
            answerFlash = correct ? .green : .red
        }

        if correct {
            // Briefly show green, then clear — session already advanced
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation { answerFlash = .clear }
            }
        } else {
            // Lock buttons, show red for 2 seconds, then advance
            isLocked = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation { answerFlash = .clear }
                isLocked = false
                session.advance()
            }
        }
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
    QuizView()
}
