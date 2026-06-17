//
//  RomanNumeralView.swift
//  Neck Practice
//
//  Practice identifying chords by roman numeral in diatonic scales.
//  Given a key and a highlighted roman numeral, name the chord root.
//  A scale degree chart shows the full structure for reinforcement.
//

import SwiftUI

struct RomanNumeralView: View {

    @State private var session: RomanNumeralSession

    init(override: RomanNumeralStepConfig? = nil) {
        let session = RomanNumeralSession()
        session.apply(override: override)
        _session = State(initialValue: session)
    }
    @State private var answerResult: Bool? = nil
    @State private var isLocked = false
    @State private var showSettings = false
    @State private var choices: [String] = []
    @State private var correctChoice: String? = nil
    @State private var wrongChoice: String? = nil
    @State private var showNext = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // ── Stats bar ────────────────────────────────────────────
                HStack(spacing: 24) {
                    statPill(label: "Score",
                             value: "\(session.score)/\(session.totalAnswered)")
                    statPill(label: "Streak", value: "\(session.streak)")
                    statPill(label: "Accuracy",
                             value: session.totalAnswered > 0
                                ? String(format: "%.0f%%", session.accuracy * 100)
                                : "—")
                }
                .padding(.horizontal)
                .padding(.top, 8)

                Divider().padding(.top, 12)

                ScrollView {
                    VStack(spacing: 16) {

                        // ── Key label ────────────────────────────────────
                        if let q = session.currentQuestion {
                            Text("Key of \(q.keyDisplayName)")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .padding(.top, 20)
                                .padding(.bottom, 4)
                        }

                        // ── Degree chart ─────────────────────────────────
                        if let q = session.currentQuestion {
                            degreeChart(for: q)
                                .padding(.horizontal, 16)
                        }

                        // ── Question prompt ──────────────────────────────
                        if let q = session.currentQuestion {
                            questionPrompt(for: q)
                                .padding(.top, 4)
                        }

                        // ── Answer buttons ───────────────────────────────
                        answerArea
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        // ── Next button (appears after feedback delay) ──
                        if showNext {
                            Button {
                                advanceToNext()
                            } label: {
                                Text("Next")
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.accentColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.bottom, 20)
                }

                Spacer()
            }
            .navigationTitle("Roman Numerals")
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
                RomanNumeralSettingsView(session: session)
            }
            .onAppear {
                session.start()
                choices = session.generateChoices()
            }
        }
    }

    // MARK: - Degree Chart

    @ViewBuilder
    private func degreeChart(for q: RomanNumeralQuestion) -> some View {
        let numerals = q.scale.romanNumerals
        let chordNames = q.allChordsInKey
        let targetIndex = q.degree - 1
        let revealed = answerResult != nil

        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                let isTarget = i == targetIndex

                let cardBG: Color = {
                    if revealed && isTarget { return .green }
                    if isTarget { return Color.accentColor }
                    if revealed { return Color(.secondarySystemBackground) }
                    return Color(.tertiarySystemBackground)
                }()

                VStack(spacing: 2) {
                    // Numeral — always visible (learning scaffold)
                    Text(numerals[i])
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(isTarget ? .white : .primary)

                    // Divider line
                    Rectangle()
                        .fill(isTarget ? Color.white.opacity(0.3) : Color.primary.opacity(0.08))
                        .frame(height: 1)
                        .padding(.horizontal, 4)

                    // Chord name — hidden until answered (unless easy mode)
                    Group {
                        if revealed {
                            Text(chordNames[i])
                        } else if !isTarget && session.easyMode {
                            Text(chordNames[i])
                        } else {
                            Text("?")
                                .opacity(isTarget ? 0.8 : 0.3)
                        }
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isTarget ? .white.opacity(0.9) : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(cardBG)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Question Prompt

    @ViewBuilder
    private func questionPrompt(for q: RomanNumeralQuestion) -> some View {
        Text("What is the \(q.romanNumeral)?")
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }

    // MARK: - Answer Area

    @ViewBuilder
    private var answerArea: some View {
        let columns = [GridItem(.flexible(), spacing: 10),
                       GridItem(.flexible(), spacing: 10)]
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(choices, id: \.self) { choice in
                let isCorrect = correctChoice == choice
                let isWrong = wrongChoice == choice
                Button {
                    handleAnswer(choice)
                } label: {
                    Text(choice)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle((isCorrect || isWrong) ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isCorrect ? Color.green : isWrong ? Color.red : Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isLocked)
            }
        }
    }

    // MARK: - Handler

    private func handleAnswer(_ choice: String) {
        guard !isLocked else { return }
        let correct = session.answer(choice)
        isLocked = true

        withAnimation(.easeInOut(duration: 0.2)) {
            answerResult = correct
            correctChoice = session.correctAnswer
            if !correct { wrongChoice = choice }
        }

        // Show Next button after a brief delay so user can see the feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeInOut(duration: 0.25)) {
                showNext = true
            }
        }
    }

    private func advanceToNext() {
        withAnimation {
            answerResult = nil
            correctChoice = nil
            wrongChoice = nil
            isLocked = false
            showNext = false
        }
        session.advance()
        choices = session.generateChoices()
    }

    private func resetSession() {
        answerResult = nil
        correctChoice = nil
        wrongChoice = nil
        isLocked = false
        showNext = false
        session.reset()
        choices = session.generateChoices()
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
    RomanNumeralView()
}
