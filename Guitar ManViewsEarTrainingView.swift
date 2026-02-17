//
//  EarTrainingView.swift
//  Guitar Man
//
//  Shows a dot on the fretboard WITHOUT its note label.
//  The note plays automatically when the question appears.
//  Tap "Play Again" to replay it. Then guess from the note buttons.
//

import SwiftUI

struct EarTrainingView: View {

    @State private var session       = QuizSession()
    @State private var choices: [Note] = []
    @State private var answerResult: Bool? = nil
    @State private var isLocked      = false
    @State private var showSettings  = false

    @Environment(AudioSettings.self) private var audioSettings

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
                VStack(spacing: 8) {
                    Text("What note is this?")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Button {
                        if let note = session.currentPosition?.note {
                            AudioPlayer.shared.playNote(note)
                        }
                    } label: {
                        Label("Play Again", systemImage: "speaker.wave.2.fill")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(session.currentPosition == nil)
                }
                .padding(.top, 16)
                .padding(.bottom, 4)
                .frame(minHeight: 72)

                // ── Fretboard ─────────────────────────────────────────────
                // Dot shown but note label hidden until answered
                FretboardView(
                    highlightedPosition: session.currentPosition,
                    answerResult: answerResult,
                    maxFret: session.maxFret,
                    showNoteLabels: false
                )
                .frame(height: 260)
                .padding(.horizontal, 8)

                Divider()

                // ── Answer buttons ────────────────────────────────────────
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
            .navigationTitle("Ear Training")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Restart", role: .destructive) {
                        withAnimation { session.reset(); refreshChoices() }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                EarTrainingSettingsView(session: session)
            }
            .onAppear {
                session.start()
                refreshChoices()
                playCurrentNote()
            }
            .onChange(of: session.currentPosition) {
                answerResult = nil
                refreshChoices()
                playCurrentNote()
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

    private func playCurrentNote() {
        guard audioSettings.isEnabled, let note = session.currentPosition?.note else { return }
        AudioPlayer.shared.playNote(note)
    }

    private func handleAnswer(_ note: Note) {
        guard !isLocked else { return }
        let correct = session.answer(note)
        answerResult = correct
        isLocked = true

        // Play the guessed note so user hears if they were right
        if audioSettings.isEnabled { AudioPlayer.shared.playNote(note) }

        let delay: Double = correct ? 0.6 : 2.0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            answerResult = nil
            isLocked = false
            session.advance()
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
    EarTrainingView()
        .environment(AudioSettings())
}
