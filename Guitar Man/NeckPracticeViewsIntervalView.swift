//
//  IntervalView.swift
//  Guitar Man
//
//  Interval Trainer:
//  Step 1 — Name the interval written on the staff (multiple choice).
//  Step 2 — Right answer only: the fretboard opens with the first note placed; tap the second.
//  Step 3 — Sometimes: a bonus question (invert it, or add / remove an octave).
//  A wrong name shows the answer and moves on without the fretboard.
//

import SwiftUI

private enum IntervalStep: Equatable {
    case identify
    case locate
    case bonus
}

struct IntervalView: View {

    @State private var session: IntervalSession

    init(override: IntervalStepConfig? = nil) {
        let session = IntervalSession()
        session.apply(override: override)
        _session = State(initialValue: session)
    }

    @State private var step: IntervalStep = .identify
    @State private var showSettings = false
    /// The choice tapped in step 1 or 3, colored once answered.
    @State private var pickedChoice: Interval? = nil
    /// Reveal the right choice (green) and the note names on the staff.
    @State private var revealAnswer = false
    @State private var tappedPosition: FretboardPosition? = nil
    @State private var locateResult: Bool? = nil
    @State private var isLocked = false
    @State private var isNewQuestionLocked = false

    @Environment(AudioSettings.self) private var audioSettings

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    statsBar
                    Divider().padding(.top, 12)

                    if let q = session.currentQuestion {
                        promptArea(q)
                        staff(q)

                        if step == .identify {
                            choiceGrid(q.choices, answer: q.interval) { handleIdentify($0) }
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        } else {
                            fretboard(q)
                            if step == .bonus, let bonus = session.bonus {
                                bonusArea(bonus)
                            }
                        }
                    } else {
                        Text("No interval fits these settings.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Interval Trainer")
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
                IntervalSettingsView(session: session)
            }
            // Drawing a question bumps questionNumber, which resets the screen and plays it.
            .onAppear { session.start() }
            .onChange(of: session.questionNumber) {
                newQuestion()
            }
        }
    }

    // MARK: - Sections

    private var statsBar: some View {
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
    }

    @ViewBuilder
    private func promptArea(_ q: IntervalQuestion) -> some View {
        VStack(spacing: 4) {
            switch step {
            case .identify:
                Text("What interval is this?")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(q.keySignature.fifths == 0 ? "No sharps or flats in the key"
                                                 : "Key of \(q.keySignature.majorKeyName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .locate:
                Text(q.interval.name)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.green)
                Text(locateResult == nil
                     ? "\(q.first.name) is on the neck. Tap where \(q.second.name) sits."
                     : (locateResult == true ? "Nice — every green dot plays \(q.second.name)."
                                             : "Here's every place \(q.second.name) sits."))
                    .font(.headline)
                    .foregroundStyle(.secondary)
            case .bonus:
                Text("Bonus")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.orange)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .frame(minHeight: 64)
    }

    private func staff(_ q: IntervalQuestion) -> some View {
        let showNames = revealAnswer || step != .identify
        // The play button sits above the staff, not over it, so a high second note isn't covered.
        return VStack(alignment: .trailing, spacing: 0) {
            Button {
                playQuestion()
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Circle())
            }
            .padding(.trailing, 24)
            .accessibilityLabel("Play the notes")

            StaffView(keySignature: q.keySignature, columns: [
                StaffColumn(id: 0, pitches: [q.first], below: showNames ? q.first.name : nil),
                StaffColumn(id: 1, pitches: [q.second], below: showNames ? q.second.name : nil),
            ], lineSpacing: 11)
            .frame(height: 150)
            .padding(.horizontal, 20)
        }
    }

    private func fretboard(_ q: IntervalQuestion) -> some View {
        let anchor = session.anchorPosition
        let answered = locateResult != nil
        var labels: [FretboardPosition: String] = [:]
        if let anchor { labels[anchor] = q.first.name }
        for target in session.targetPositions { labels[target] = q.second.name }

        return FretboardView(
            highlightedPositions: anchor.map { Set([$0]) } ?? [],
            correctPositions: answered ? session.targetPositions : [],
            selectedPositions: tappedPosition.map { Set([$0]) } ?? [],
            answerResult: locateResult,
            onTap: { handleLocate($0) },
            maxFret: IntervalSession.maxFret,
            showHighlightedLabels: true,
            customLabels: labels
        )
        .frame(height: 260)
        .padding(.horizontal, 8)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func bonusArea(_ bonus: IntervalBonus) -> some View {
        VStack(spacing: 10) {
            Text(bonus.prompt)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(bonus.hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            choiceGrid(bonus.choices, answer: bonus.answer) { handleBonus($0) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func choiceGrid(_ choices: [Interval], answer: Interval,
                            action: @escaping (Interval) -> Void) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                  spacing: 10) {
            ForEach(choices) { choice in
                let isCorrect = revealAnswer && choice == answer
                let isWrong = revealAnswer && choice == pickedChoice && choice != answer
                Button {
                    action(choice)
                } label: {
                    Text(choice.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle((isCorrect || isWrong) ? .white : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isCorrect ? Color.green : isWrong ? Color.red : Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isLocked || isNewQuestionLocked)
            }
        }
    }

    // MARK: - Handlers

    private func handleIdentify(_ choice: Interval) {
        guard !isLocked, !isNewQuestionLocked, step == .identify else { return }
        isLocked = true
        pickedChoice = choice
        let correct = session.answerInterval(choice)
        withAnimation(.easeInOut(duration: 0.2)) { revealAnswer = true }

        DispatchQueue.main.asyncAfter(deadline: .now() + (correct ? 0.8 : 1.8)) {
            if correct {
                withAnimation(.easeInOut(duration: 0.3)) {
                    pickedChoice = nil
                    revealAnswer = false
                    step = .locate
                }
                isLocked = false
                if audioSettings.isEnabled, let anchor = session.anchorPosition {
                    AudioPlayer.shared.playNote(at: anchor)
                }
            } else {
                session.advance()
            }
        }
    }

    private func handleLocate(_ position: FretboardPosition) {
        guard !isLocked, step == .locate, locateResult == nil else { return }
        isLocked = true
        tappedPosition = position
        let correct = session.answerPosition(position)
        if audioSettings.isEnabled { AudioPlayer.shared.playNote(at: position) }
        withAnimation(.easeInOut(duration: 0.2)) { locateResult = correct }

        DispatchQueue.main.asyncAfter(deadline: .now() + (correct ? 1.2 : 2.0)) {
            if session.bonus != nil {
                withAnimation(.easeInOut(duration: 0.3)) { step = .bonus }
                isLocked = false
            } else {
                session.advance()
            }
        }
    }

    private func handleBonus(_ choice: Interval) {
        guard !isLocked, step == .bonus else { return }
        isLocked = true
        pickedChoice = choice
        let correct = session.answerBonus(choice)
        withAnimation(.easeInOut(duration: 0.2)) { revealAnswer = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + (correct ? 0.9 : 1.8)) {
            session.advance()
        }
    }

    /// Resets the screen for the question the session just drew, and plays it.
    private func newQuestion() {
        step = .identify
        pickedChoice = nil
        revealAnswer = false
        tappedPosition = nil
        locateResult = nil
        isLocked = false
        isNewQuestionLocked = true
        playQuestion()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isNewQuestionLocked = false
        }
    }

    /// Plays the two notes in the order they're written.
    private func playQuestion() {
        guard audioSettings.isEnabled, let q = session.currentQuestion else { return }
        AudioPlayer.shared.stopAll()
        AudioPlayer.shared.playNote(q.first.note, octave: q.first.soundingOctave)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            AudioPlayer.shared.playNote(q.second.note, octave: q.second.soundingOctave)
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

// MARK: - Settings

struct IntervalSettingsView: View {

    @Bindable var session: IntervalSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(session.maxAccidentals == 0 ? "C major only"
                                                        : "Up to \(session.maxAccidentals) sharps or flats",
                            value: $session.maxAccidentals, in: 0...6)
                } header: {
                    Text("Key Signatures")
                }

                Section {
                    Toggle("Higher Note First Sometimes", isOn: $session.includeDescending)
                    Toggle("Compound Intervals (9ths–13ths)", isOn: $session.includeCompound)
                } header: {
                    Text("Intervals")
                } footer: {
                    Text("Always measure from the lower note, even when it's written second.")
                }

                Section {
                    Toggle("Bonus Questions", isOn: $session.bonusQuestions)
                    Stepper("\(session.choiceCount) choices", value: $session.choiceCount, in: 3...6)
                } header: {
                    Text("Questions")
                } footer: {
                    Text("Bonus questions ask what an interval inverts to, or what it becomes with an octave added or taken away.")
                }
            }
            .navigationTitle("Interval Settings")
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
    IntervalView()
        .environment(AudioSettings())
}
