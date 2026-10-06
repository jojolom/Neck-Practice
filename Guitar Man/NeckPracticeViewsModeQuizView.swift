//
//  ModeQuizView.swift
//  Guitar Man
//
//  Mode Quiz: name the mode written on the staff, name the major key it borrows its notes
//  from, or pick how it differs from major / natural minor.
//

import SwiftUI

struct ModeQuizView: View {

    @State private var session: ModeQuizSession

    init(override: ModeStepConfig? = nil) {
        let session = ModeQuizSession()
        session.apply(override: override)
        _session = State(initialValue: session)
    }

    @State private var picked: String? = nil
    @State private var revealAnswer = false
    @State private var isLocked = false
    @State private var showSettings = false

    @Environment(AudioSettings.self) private var audioSettings

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    HStack(spacing: 24) {
                        statPill(label: "Score", value: "\(session.score)/\(session.totalAnswered)")
                        statPill(label: "Streak", value: "🔥 \(session.streak)")
                        statPill(label: "Accuracy",
                                 value: session.totalAnswered > 0
                                    ? String(format: "%.0f%%", session.accuracy * 100)
                                    : "—")
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    Divider().padding(.top, 12)

                    if let q = session.currentQuestion {
                        question(q)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Mode Quiz")
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
                        withAnimation { session.reset() }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                ModeQuizSettingsView(session: session)
            }
            // Drawing a question bumps questionNumber, which resets the screen.
            .onAppear { session.start() }
            .onChange(of: session.questionNumber) {
                picked = nil
                revealAnswer = false
                isLocked = false
                if session.currentQuestion?.kind == .nameIt { playScale() }
            }
        }
    }

    @ViewBuilder
    private func question(_ q: ModeQuestion) -> some View {
        // Note names give the mode away when you're asked to name it, until you've answered.
        let showNames = revealAnswer || q.kind != .nameIt
        let pitches = q.scale.pitches()
        let columns: [StaffColumn] = pitches.enumerated().map { (i, pitch) -> StaffColumn in
            StaffColumn(id: i, pitches: [pitch], below: showNames ? pitch.name : nil)
        }

        Text(q.prompt)
            .font(.headline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.top, 16)

        ZStack(alignment: .topTrailing) {
            StaffView(columns: columns, lineSpacing: 9)
                .frame(height: 130)
                .padding(.horizontal, 16)
            Button {
                playScale()
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }
            .padding(.trailing, 20)
            .accessibilityLabel("Play the scale")
        }
        .padding(.top, 4)

        if revealAnswer {
            Text("\(q.scale.name): \(q.scale.mode.comparison.lowercased()), the notes of \(q.scale.parentKeyName).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }

        VStack(spacing: 10) {
            ForEach(q.choices, id: \.self) { choice in
                let isCorrect = revealAnswer && choice == q.answer
                let isWrong = revealAnswer && choice == picked && choice != q.answer
                Button {
                    handleAnswer(choice)
                } label: {
                    Text(choice)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle((isCorrect || isWrong) ? .white : .primary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .padding(.horizontal, 8)
                        .background(isCorrect ? Color.green : isWrong ? Color.red : Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isLocked)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func handleAnswer(_ choice: String) {
        guard !isLocked else { return }
        isLocked = true
        picked = choice
        let correct = session.answer(choice)
        withAnimation(.easeInOut(duration: 0.2)) { revealAnswer = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + (correct ? 1.2 : 2.5)) {
            session.advance()
        }
    }

    private func playScale() {
        guard audioSettings.isEnabled, let q = session.currentQuestion else { return }
        AudioPlayer.shared.stopAll()
        for (i, pitch) in q.scale.pitches().enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.28) {
                AudioPlayer.shared.playNote(pitch.note, octave: pitch.soundingOctave)
            }
        }
    }

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

// MARK: - Settings

struct ModeQuizSettingsView: View {

    @Bindable var session: ModeQuizSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Name the Mode", isOn: $session.includeNameIt)
                    Toggle("Parent Major Key", isOn: $session.includeParentKey)
                    Toggle("Compare with Major / Minor", isOn: $session.includeCompare)
                } header: {
                    Text("Questions")
                }
                Section {
                    Stepper("\(session.choiceCount) choices", value: $session.choiceCount, in: 3...7)
                }
            }
            .navigationTitle("Mode Quiz Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    ModeQuizView()
        .environment(AudioSettings())
}
