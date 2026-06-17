//
//  PentatonicView.swift
//  Neck Practice
//
//  Two-step exercise:
//  Step 1 — Select the root dots on the fretboard, then submit
//  Step 2 — Name the root note (major or minor pentatonic)
//

import SwiftUI

// MARK: - Answer step state

private enum PentatonicAnswerStep: Equatable {
    case selectRoots                          // tap root dots on fretboard + submit
    case root(rootsWereCorrect: Bool)         // roots answered; now pick root note name
}

// MARK: - PentatonicView

struct PentatonicView: View {

    @State private var session: PentatonicSession
    @State private var step: PentatonicAnswerStep = .selectRoots
    @State private var answerResult: Bool? = nil
    @State private var isLocked     = false
    @State private var showSettings  = false
    @State private var showRootDots  = false
    /// Dots the user has tapped during the selectRoots step.
    @State private var selectedDots: Set<FretboardPosition> = []
    /// The correct root note, set after answering to highlight the right button.
    @State private var correctRoot: Note? = nil
    /// The wrong root note tapped by the user, to highlight it red.
    @State private var wrongRoot: Note? = nil
    /// Sorted, subset root-note choices.
    @State private var rootChoices: [Note] = []

    // Snapshot of the question currently shown on screen.
    // Updated synchronously — never via onChange — so the fretboard
    // never disappears between advance() and the next draw.
    @State private var displayedQuestion: PentatonicQuestion? = nil

    init(override: PentatonicStepConfig? = nil) {
        let session = PentatonicSession()
        session.apply(override: override)
        _session = State(initialValue: session)
    }

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
                // displayedQuestion is a frozen snapshot so the fretboard never
                // flickers to empty between advance() and the next draw.
                if let q = displayedQuestion ?? session.currentQuestion {
                    let isRootStep: Bool = {
                        if case .root = step { return true }
                        return false
                    }()
                    let highlighted: Set<FretboardPosition> = isRootStep && showRootDots
                        ? Set(q.shapePositions).union(q.effectiveRootPositions)
                        : Set(q.shapePositions)
                    // After root selection submit: correct roots shown in green
                    let correctDots: Set<FretboardPosition> = answerResult != nil
                        ? q.effectiveRootPositions : []
                    // During root-note step, also show correct root button dots green on wrong guess
                    let rootStepCorrectDots: Set<FretboardPosition> = (correctRoot != nil && showRootDots)
                        ? q.effectiveRootPositions : []
                    // Only show note labels after the user answers the root note question
                    let showLabels = isRootStep && answerResult != nil
                    FretboardView(
                        highlightedPositions: highlighted,
                        rootPositions: showRootDots ? q.effectiveRootPositions : [],
                        correctPositions: correctDots.union(rootStepCorrectDots),
                        selectedPositions: step == .selectRoots ? selectedDots : [],
                        answerResult: answerResult,
                        onTap: step == .selectRoots && !isLocked ? { pos in handleDotTap(pos) } : nil,
                        maxFret: session.maxFret,
                        showNoteLabels: false,
                        showHighlightedLabels: showLabels,
                        keyContext: FretboardView.KeyContext(
                            root: q.effectiveRootNote,
                            isMinor: q.quality.isMinor
                        )
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
                // Always sync the snapshot — covers both first appearance and back-navigation.
                // start() guards against re-drawing, so currentQuestion is already stable.
                displayedQuestion = session.currentQuestion
            }
        }
    }

    // MARK: - Prompt

    @ViewBuilder
    private var promptArea: some View {
        Group {
            switch step {
            case .selectRoots:
                VStack(spacing: 4) {
                    if let q = displayedQuestion ?? session.currentQuestion {
                        Text("Select the \(q.quality.displayName) root notes")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Position \(q.shape.id)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("Tap the root positions, then submit")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

            case .root(let rootsWereCorrect):
                VStack(spacing: 4) {
                    if let q = displayedQuestion {
                        Text("\(q.quality.displayName) Pentatonic")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(rootsWereCorrect ? .green : .primary)
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
        case .selectRoots:
            VStack(spacing: 12) {
                Text("\(selectedDots.count) dot\(selectedDots.count == 1 ? "" : "s") selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    handleRootsSubmit()
                } label: {
                    Text("Submit")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(selectedDots.isEmpty ? Color.gray.opacity(0.4) : Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(selectedDots.isEmpty || isLocked)
            }

        case .root:
            let isMinorQ = (displayedQuestion ?? session.currentQuestion)?.quality.isMinor ?? false
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
                    .disabled(isLocked)
                }
            }
        }
    }

    // MARK: - Handlers

    private func handleDotTap(_ pos: FretboardPosition) {
        guard !isLocked, case .selectRoots = step else { return }
        let q = displayedQuestion ?? session.currentQuestion
        // Only allow tapping dots that are part of the shape
        guard let q, Set(q.shapePositions).contains(pos) else { return }
        if selectedDots.contains(pos) {
            selectedDots.remove(pos)
        } else {
            selectedDots.insert(pos)
        }
    }

    private func handleRootsSubmit() {
        guard !isLocked, case .selectRoots = step else { return }
        let correct = session.answerRoots(selectedDots)
        isLocked = true

        // answerResult triggers FretboardView to color selected dots green/red
        withAnimation(.easeInOut(duration: 0.2)) {
            answerResult = correct
        }

        let delay: Double = correct ? 0.8 : 1.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            refreshRootChoices()
            withAnimation {
                answerResult = nil
                selectedDots = []
                showRootDots = true
                step         = .root(rootsWereCorrect: correct)
                isLocked     = false
            }
        }
    }

    private func handleRootAnswer(_ note: Note) {
        guard !isLocked, case .root = step else { return }
        let q = displayedQuestion ?? session.currentQuestion
        let correct = session.answerRoot(note)
        isLocked = true

        if correct {
            withAnimation(.easeInOut(duration: 0.2)) {
                answerResult = true
                correctRoot  = q?.effectiveRootNote
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                answerResult = nil
                correctRoot  = nil
                showRootDots = false
                step         = .selectRoots
                isLocked     = false
                session.advance()
                displayedQuestion = session.currentQuestion
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                answerResult = true
                correctRoot  = q?.effectiveRootNote
                wrongRoot    = note
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                answerResult = nil
                correctRoot  = nil
                wrongRoot    = nil
                showRootDots = false
                step         = .selectRoots
                isLocked     = false
                session.advance()
                displayedQuestion = session.currentQuestion
            }
        }
    }

    private func refreshRootChoices() {
        guard let q = displayedQuestion ?? session.currentQuestion else {
            rootChoices = Array(Note.allCases.prefix(session.rootChoiceCount))
            return
        }
        let correct = q.effectiveRootNote
        let count = min(session.rootChoiceCount, Note.allCases.count)
        let distractors = Array(correct.circleOfFifthsDistractors().prefix(count - 1))
        rootChoices = ([correct] + distractors).sorted { $0.rawValue < $1.rawValue }
    }

    private func resetSession() {
        answerResult      = nil
        selectedDots      = []
        correctRoot       = nil
        wrongRoot         = nil
        showRootDots      = false
        step              = .selectRoots
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
