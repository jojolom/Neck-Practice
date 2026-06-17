//
//  PracticeSessionView.swift
//  Neck Practice
//
//  Runs one day's practice — embeds the current step's trainer view,
//  shows a countdown timer banner, and advances on completion.
//

import SwiftUI
import UIKit

/// Aggregate report passed back when a practice session ends.
struct PracticeSessionResult {
    var stepsCompleted: Int
    var totalMinutes: Int
    var completedKinds: [PracticeStepKind]
}

struct PracticeSessionView: View {

    let plan: PracticePlan
    /// Called when the user finishes or exits. Callee is responsible for
    /// logging + dismissal.
    let onFinish: (PracticeSessionResult) -> Void

    @State private var currentIndex: Int = 0
    @State private var remainingSeconds: Int = 0
    @State private var isPaused: Bool = false
    @State private var showingExitConfirm: Bool = false
    @State private var completedSteps: Int = 0
    @State private var completedKinds: [PracticeStepKind] = []
    @State private var totalMinutesCompleted: Int = 0
    @State private var timerTask: Task<Void, Never>? = nil
    @State private var didFireWarningForCurrentStep: Bool = false
    @State private var isFinished: Bool = false

    @AppStorage("practice.cuesEnabled") private var cuesEnabled: Bool = true

    private var currentStep: PracticeStep? {
        plan.steps.indices.contains(currentIndex) ? plan.steps[currentIndex] : nil
    }

    private var isFinalStep: Bool {
        currentIndex >= plan.steps.count - 1
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                timerBanner

                Divider()

                // Embed the current step's trainer view full-bleed.
                Group {
                    if let step = currentStep {
                        stepContent(for: step.kind)
                    } else {
                        finishedView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Exit") { showingExitConfirm = true }
                }
                ToolbarItem(placement: .principal) {
                    if let step = currentStep {
                        Text("Step \(currentIndex + 1) of \(plan.steps.count) · \(step.kind.displayName)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .confirmationDialog(
                "Exit practice?",
                isPresented: $showingExitConfirm,
                titleVisibility: .visible
            ) {
                Button("Exit", role: .destructive) {
                    onFinish(currentResult)
                }
                Button("Keep Going", role: .cancel) { }
            } message: {
                Text(completedSteps == 0
                     ? "Today won't count toward your streak unless you complete at least one step."
                     : "Your progress so far will still count.")
            }
            .onAppear {
                startStep()
                startTicker()
            }
            .onDisappear { timerTask?.cancel() }
        }
    }

    // MARK: - Banner

    private var isWarningActive: Bool {
        currentStep != nil && remainingSeconds > 0 && remainingSeconds <= 5
    }

    private var timerBanner: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: currentStep?.kind.systemImage ?? "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(currentStep?.kind.accentColor ?? .green)

                VStack(alignment: .leading, spacing: 1) {
                    Text(currentStep?.kind.displayName ?? "Session Complete")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    if currentStep != nil {
                        Text(timeText)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(isWarningActive ? .orange : .secondary)
                            .monospacedDigit()
                    }
                }

                Spacer()

                Button {
                    cuesEnabled.toggle()
                } label: {
                    Image(systemName: cuesEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Color(.tertiarySystemFill))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(cuesEnabled ? "Mute cues" : "Unmute cues")

                if currentStep != nil {
                    Button {
                        isPaused.toggle()
                    } label: {
                        Image(systemName: isPaused ? "play.fill" : "pause.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 38, height: 38)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                    }

                    Button {
                        advanceStep()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 38, height: 38)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Circle())
                    }
                }
            }

            ProgressView(value: progress)
                .tint(isWarningActive ? .orange : (currentStep?.kind.accentColor ?? .green))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            (isWarningActive ? Color.orange.opacity(0.12) : Color(.systemBackground))
                .animation(.easeInOut(duration: 0.25), value: isWarningActive)
        )
        .scaleEffect(isWarningActive ? 1.015 : 1.0)
        .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isWarningActive)
    }

    private var timeText: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%d:%02d remaining", m, s)
    }

    private var progress: Double {
        guard let step = currentStep, step.minutes > 0 else { return 0 }
        let total = Double(step.minutes * 60)
        return 1 - Double(remainingSeconds) / total
    }

    // MARK: - Step content

    @ViewBuilder
    private func stepContent(for kind: PracticeStepKind) -> some View {
        let config = currentStep?.config
        switch kind {
        case .noteGuesser:  QuizView(override: config?.quiz)
        case .pentatonic:   PentatonicView(override: config?.pentatonic)
        case .triad:        TriadView(override: config?.triad)
        case .romanNumeral: RomanNumeralView(override: config?.romanNumeral)
        case .scaleStudy:   ScaleStudyView(override: config?.scaleStudy)
        case .sightReading: SightReadingView(override: config?.sightReading)
        }
    }

    private var finishedView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 72, weight: .semibold))
                .foregroundStyle(.green)
            Text("Session Complete")
                .font(.system(size: 24, weight: .bold, design: .rounded))
            Text("\(completedSteps) of \(plan.steps.count) step\(plan.steps.count == 1 ? "" : "s") completed.")
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                onFinish(currentResult)
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Timer

    private func startStep() {
        guard let step = currentStep else { return }
        remainingSeconds = step.minutes * 60
        isPaused = false
        didFireWarningForCurrentStep = false
    }

    private func startTicker() {
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                tick()
            }
        }
    }

    private func tick() {
        guard currentStep != nil, !isPaused else { return }
        if remainingSeconds > 0 {
            remainingSeconds -= 1
            // Fire the 5-second warning once, when the timer first ticks
            // into the final five seconds of the step.
            if remainingSeconds == 5 && !didFireWarningForCurrentStep {
                didFireWarningForCurrentStep = true
                playWarningCue()
            }
        } else {
            advanceStep()
        }
    }

    // MARK: - Cues

    private func playStepStartCue() {
        guard cuesEnabled else { return }
        AudioPlayer.shared.playTriad(root: .c, isMajor: true, octave: 4)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func playWarningCue() {
        guard cuesEnabled else { return }
        AudioPlayer.shared.playNote(.g, octave: 5)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func playFinishCue() {
        guard cuesEnabled else { return }
        // Quick V → I cadence for a more conclusive finish.
        AudioPlayer.shared.playTriad(root: .g, isMajor: true, octave: 4)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            AudioPlayer.shared.playTriad(root: .c, isMajor: true, octave: 4)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func advanceStep() {
        guard let step = currentStep else { return }
        completedSteps += 1
        completedKinds.append(step.kind)
        totalMinutesCompleted += step.minutes
        if isFinalStep {
            currentIndex = plan.steps.count   // triggers finishedView
            isFinished = true
            playFinishCue()
        } else {
            currentIndex += 1
            startStep()
            playStepStartCue()
        }
    }

    private var currentResult: PracticeSessionResult {
        PracticeSessionResult(
            stepsCompleted: completedSteps,
            totalMinutes: totalMinutesCompleted,
            completedKinds: completedKinds
        )
    }
}

#Preview {
    PracticeSessionView(plan: PracticePlan.defaults[0]) { _ in }
}
