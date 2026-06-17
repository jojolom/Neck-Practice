//
//  TriadView.swift
//  Neck Practice
//
//  Three-step exercise:
//  Step 1 — Identify the quality (Major / Minor)
//  Step 2 — Identify the inversion (Root / 1st / 2nd)
//  Step 3 — Name the root note
//

import SwiftUI

// MARK: - Answer step state

private enum AnswerStep: Equatable {
    case quality                            // waiting for Major/Minor tap
    case inversion(qualityWasCorrect: Bool) // quality answered; now pick inversion
    case root                               // inversion answered; now pick root note
}

// MARK: - TriadView

struct TriadView: View {

    @State private var session: TriadSession

    init(override: TriadStepConfig? = nil) {
        let session = TriadSession()
        session.apply(override: override)
        _session = State(initialValue: session)
    }
    @State private var step: AnswerStep = .quality
    @State private var answerResult: Bool? = nil
    @State private var isLocked       = false
    @State private var showSettings   = false
    @State private var showRootHint   = false
    /// The correct quality, set after answering quality step to highlight the right button.
    @State private var correctQuality: TriadQuality? = nil
    /// The wrong quality tapped by the user, to highlight it red.
    @State private var wrongQuality: TriadQuality? = nil
    /// The correct inversion, set after answering to highlight the right button.
    @State private var correctInversion: TriadInversion? = nil
    /// The wrong inversion tapped by the user, to highlight it red.
    @State private var wrongInversion: TriadInversion? = nil
    /// The correct root note, set after answering root step to highlight the right button.
    @State private var correctRoot: Note? = nil
    /// The wrong root note tapped by the user, to highlight it red.
    @State private var wrongRoot: Note? = nil
    /// Sorted, subset root-note choices.
    @State private var rootChoices: [Note] = []
    /// True during the "new question just appeared" lock period so the chord can be heard first.
    @State private var isNewQuestionLocked = false

    @Environment(AudioSettings.self) private var audioSettings

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
                    // After answering root, merge root into highlighted so its label shows.
                    let revealRoot = showRootHint && answerResult != nil
                    let highlighted: Set<FretboardPosition> = revealRoot
                        ? Set(q.triadPositions).union([q.rootPosition])
                        : Set(q.triadPositions)
                    // On wrong root guess, force root position to green so user sees the answer.
                    let correctDots: Set<FretboardPosition> = (correctRoot != nil && showRootHint)
                        ? [q.rootPosition] : []
                    FretboardView(
                        highlightedPositions: highlighted,
                        correctPositions: correctDots,
                        answerResult: answerResult,
                        maxFret: session.maxFret,
                        showNoteLabels: false,
                        keyContext: FretboardView.KeyContext(
                            root: q.rootNote,
                            isMinor: q.shape.quality == .minor
                        )
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
                lockForNewQuestion()
            }
            .onChange(of: session.currentQuestion?.shape.id) {
                step               = .quality
                answerResult       = nil
                correctQuality     = nil
                wrongQuality       = nil
                correctInversion   = nil
                wrongInversion     = nil
                correctRoot        = nil
                wrongRoot          = nil
                showRootHint       = false
                isLocked           = false
                lockForNewQuestion()
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
            case .inversion(let qualityWasCorrect):
                VStack(spacing: 4) {
                    if let q = session.currentQuestion {
                        Text(q.shape.quality.displayName)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(qualityWasCorrect ? .green : .primary)
                    }
                    Text("What inversion is this?")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            case .root:
                VStack(spacing: 4) {
                    if let q = session.currentQuestion {
                        HStack(spacing: 8) {
                            Text(q.shape.quality.displayName)
                                .font(.title3.weight(.bold))
                            Text("·")
                                .foregroundStyle(.secondary)
                            Text(q.shape.inversion.displayName)
                                .font(.title3.weight(.bold))
                        }
                    }
                    Text("What is the root note?")
                        .font(.headline)
                        .foregroundStyle(.secondary)
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
                    let isCorrect = correctQuality == quality
                    let isWrong   = wrongQuality == quality
                    Button {
                        handleQualityAnswer(quality)
                    } label: {
                        Text(quality.displayName)
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle((isCorrect || isWrong) ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(isCorrect ? Color.green : isWrong ? Color.red : Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLocked || isNewQuestionLocked)
                }
            }

        case .inversion:
            HStack(spacing: 12) {
                ForEach(TriadInversion.allCases, id: \.self) { inv in
                    let isCorrect = correctInversion == inv
                    let isWrong   = wrongInversion == inv
                    Button {
                        handleInversionAnswer(inv)
                    } label: {
                        Text(inv.displayName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle((isCorrect || isWrong) ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(isCorrect ? Color.green : isWrong ? Color.red : Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(isLocked || isNewQuestionLocked)
                }
            }

        case .root:
            let isMinorQ = session.currentQuestion?.shape.quality == .minor
            HStack(spacing: 8) {
                ForEach(rootChoices) { note in
                    let isCorrect = correctRoot == note
                    let isWrong   = wrongRoot == note
                    Button {
                        handleRootAnswer(note)
                    } label: {
                        Text(note.keyName(asMinor: isMinorQ))
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
        }
    }

    // MARK: - Handlers

    private func handleQualityAnswer(_ quality: TriadQuality) {
        guard !isLocked, !isNewQuestionLocked else { return }
        let correct = session.answerQuality(quality)
        isLocked = true

        let currentQuality = session.currentQuestion?.shape.quality

        if correct {
            if audioSettings.isEnabled { playCurrentTriad() }
            withAnimation(.easeInOut(duration: 0.2)) {
                correctQuality = currentQuality
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation {
                    correctQuality = nil
                    step           = .inversion(qualityWasCorrect: true)
                    isLocked       = false
                }
            }
        } else {
            if audioSettings.isEnabled { playCurrentTriad() }
            withAnimation(.easeInOut(duration: 0.2)) {
                correctQuality = currentQuality
                wrongQuality   = quality
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation {
                    correctQuality = nil
                    wrongQuality   = nil
                    step           = .inversion(qualityWasCorrect: false)
                    isLocked       = false
                }
            }
        }
    }

    private func handleInversionAnswer(_ inversion: TriadInversion) {
        guard !isLocked, !isNewQuestionLocked, case .inversion = step else { return }
        let correct = session.answerInversion(inversion)
        isLocked = true

        let currentInversion = session.currentQuestion?.shape.inversion

        if correct {
            withAnimation(.easeInOut(duration: 0.2)) {
                correctInversion = currentInversion
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                refreshRootChoices()
                withAnimation {
                    correctInversion = nil
                    showRootHint     = true
                    step             = .root
                    isLocked         = false
                }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                correctInversion = currentInversion
                wrongInversion   = inversion
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                refreshRootChoices()
                withAnimation {
                    correctInversion = nil
                    wrongInversion   = nil
                    showRootHint     = true
                    step             = .root
                    isLocked         = false
                }
            }
        }
    }

    private func handleRootAnswer(_ note: Note) {
        guard !isLocked, !isNewQuestionLocked, case .root = step else { return }
        let correct = session.answerRoot(note)
        isLocked = true
        let q = session.currentQuestion

        if correct {
            // Correct: root dot + root button turn green, play note, advance after 0.8s
            if audioSettings.isEnabled, let q {
                AudioPlayer.shared.playNote(at: q.rootPosition)
            }
            withAnimation(.easeInOut(duration: 0.2)) {
                answerResult = true         // label reveal in FretboardView
                correctRoot  = q?.rootNote  // button turns green
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation { answerResult = nil }
                correctRoot = nil
                isLocked = false
                session.advance()
            }
        } else {
            // Wrong: tapped button red, correct button green, play correct note
            withAnimation(.easeInOut(duration: 0.2)) {
                answerResult = true         // triggers label reveal on the correct dot
                correctRoot  = q?.rootNote  // correct button turns green
                wrongRoot    = note         // tapped button turns red
            }
            if audioSettings.isEnabled, let q {
                AudioPlayer.shared.playNote(at: q.rootPosition)
            }
            // Hold for 1.5s so user absorbs the correct answer, then advance
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation { answerResult = nil }
                correctRoot = nil
                wrongRoot   = nil
                isLocked    = false
                session.advance()
            }
        }
    }

    /// Plays the current triad and locks the buttons for a moment so it can be heard first.
    private func lockForNewQuestion() {
        isNewQuestionLocked = true
        playCurrentTriad()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isNewQuestionLocked = false
        }
    }

    private func refreshRootChoices() {
        guard let q = session.currentQuestion else {
            rootChoices = Array(Note.allCases.prefix(session.rootChoiceCount))
            return
        }
        let correct = q.rootNote
        let count = min(session.rootChoiceCount, Note.allCases.count)
        let distractors = Array(correct.circleOfFifthsDistractors().prefix(count - 1))
        rootChoices = ([correct] + distractors).sorted { $0.rawValue < $1.rawValue }
    }

    private func resetSession() {
        step               = .quality
        answerResult       = nil
        correctQuality     = nil
        wrongQuality       = nil
        correctInversion   = nil
        wrongInversion     = nil
        correctRoot        = nil
        wrongRoot          = nil
        showRootHint       = false
        isLocked           = false
        isNewQuestionLocked = false
        session.reset()
    }

    private func playCurrentTriad() {
        guard audioSettings.isEnabled, let q = session.currentQuestion else { return }
        AudioPlayer.shared.playNotes(q.triadPositions)
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
