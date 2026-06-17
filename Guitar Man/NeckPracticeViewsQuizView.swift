//
//  QuizView.swift
//  Neck Practice
//

import SwiftUI

struct QuizView: View {

    @State private var session: QuizSession

    init(override: QuizStepConfig? = nil) {
        let session = QuizSession()
        session.apply(override: override)
        _session = State(initialValue: session)
    }
    @State private var showingSettings = false
    @State private var answerFlash: Color = .clear
    @State private var answerResult: Bool? = nil
    @State private var choices: [Note] = []
    @State private var isLocked = false
    /// Set to the correct note after answering so the button highlights green.
    @State private var correctNote: Note? = nil
    /// Set to the tapped note on a wrong guess so that button highlights red.
    @State private var wrongNote: Note? = nil
    /// True during the new-question lock period so the note can be heard first.
    @State private var isNewQuestionLocked = false

    @Environment(AudioSettings.self) private var audioSettings

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
                HStack(spacing: 8) {
                    ForEach(choices) { note in
                        let isCorrect = correctNote == note
                        let isWrong   = wrongNote == note
                        Button {
                            handleAnswer(note)
                        } label: {
                            Text(note.description)
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                                .foregroundStyle((isCorrect || isWrong) ? .white : .primary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(isCorrect ? Color.green : isWrong ? Color.red : Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(isLocked || isNewQuestionLocked)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Spacer()
            }
            .navigationTitle("Note Guesser")
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
                        isNewQuestionLocked = false
                        isLocked = false
                        correctNote = nil
                        wrongNote   = nil
                        answerResult = nil
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
                lockForNewQuestion()
            }
            .onChange(of: session.currentPosition) {
                answerResult = nil
                correctNote  = nil
                wrongNote    = nil
                refreshChoices()
                lockForNewQuestion()
            }
        }
    }

    // MARK: - Helpers

    private func refreshChoices() {
        guard let correct = session.currentPosition?.note else {
            choices = Array(Note.allCases.filter(\.isNatural).prefix(session.choiceCount))
            return
        }
        let pool = session.naturalsOnly
            ? Note.allCases.filter(\.isNatural)
            : Note.allCases
        let count = min(session.choiceCount, pool.count)
        let distractors = pool.filter { $0 != correct }.shuffled().prefix(count - 1)
        choices = ([correct] + distractors).sorted { $0.rawValue < $1.rawValue }
    }

    private func handleAnswer(_ note: Note) {
        guard !isLocked, !isNewQuestionLocked else { return }
        let correct = session.answer(note)
        let pos = session.currentPosition
        isLocked = true

        if correct {
            // Correct: green dot + green button, advance after 0.8s
            // Don't replay the note — they already heard it as the question.
            AudioPlayer.shared.stopAll()
            withAnimation(.easeInOut(duration: 0.2)) {
                answerResult = true         // dot turns green in FretboardView
                correctNote  = pos?.note    // button turns green
                answerFlash  = .green
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation { answerFlash = .clear }
                answerResult = nil
                correctNote  = nil
                isLocked     = false
                session.advance()
            }
        } else {
            // Wrong: tapped button red, correct button green, play correct note
            if audioSettings.isEnabled, let pos {
                AudioPlayer.shared.stopAll()
                AudioPlayer.shared.playNote(at: pos)
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                answerResult = true         // triggers label reveal
                correctNote  = pos?.note    // correct button turns green
                wrongNote    = note         // tapped button turns red
            }
            // Hold 1.5s so user sees and hears the correct answer, then advance
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { answerFlash = .clear }
                answerResult = nil
                correctNote  = nil
                wrongNote    = nil
                isLocked     = false
                session.advance()
            }
        }
    }

    /// Plays the current note and locks buttons briefly so it can be heard.
    private func lockForNewQuestion() {
        guard audioSettings.isEnabled else { return }
        isNewQuestionLocked = true
        if let pos = session.currentPosition {
            AudioPlayer.shared.stopAll()
            AudioPlayer.shared.playNote(at: pos)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isNewQuestionLocked = false
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
