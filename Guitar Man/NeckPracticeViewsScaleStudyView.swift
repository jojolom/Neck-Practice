//
//  ScaleStudyView.swift
//  Neck Practice
//
//  Structured scale practice: 4-scale cycle with metronome and theory quizzes.
//

import SwiftUI

struct ScaleStudyView: View {

    @State private var session: ScaleStudySession
    @State private var metronome = Metronome()
    @State private var showingSettings = false

    init(override: ScaleStudyStepConfig? = nil) {
        let session = ScaleStudySession()
        session.apply(override: override)
        _session = State(initialValue: session)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch session.phase {
                case .setup:         setupPhase
                case .practice:      practicePhase
                case .quiz:          quizPhase
                case .reveal:        revealPhase
                case .roundComplete: roundCompletePhase
                }
            }
            .navigationTitle("Scale Study")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Label("Settings", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                ScaleStudySettingsView(session: session)
            }
            .onDisappear { metronome.stop() }
            .onChange(of: session.phase) { _, newPhase in
                if newPhase == .practice {
                    startMetronome()
                } else {
                    metronome.stop()
                }
            }
        }
    }

    // MARK: - Setup Phase

    private var setupPhase: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "music.quarternote.3")
                .font(.system(size: 56))
                .foregroundStyle(.mint)

            VStack(spacing: 8) {
                Text("Scale Study")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Practice 4 related scales per round\nwith metronome and theory quizzes")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                session.startNewRound()
                startMetronome()
            } label: {
                Text("Start")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.mint)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Practice Phase

    private var practicePhase: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Round \(session.roundNumber)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Scale \(session.currentIndex + 1) of 4")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            // Tempo & Rhythm
            VStack(spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    NoteSymbolView(rhythm: session.rhythm, size: 38)
                    Text("= \(session.bpm)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                }

                Text(session.rhythm.label)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(session.rhythm.shortLabel)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            // Beat indicators
            HStack(spacing: 10) {
                ForEach(0..<metronome.beatsPerMeasure, id: \.self) { beat in
                    Circle()
                        .fill(beat == metronome.currentBeat && metronome.isPlaying
                              ? (beat == 0 ? Color.red : Color.mint)
                              : Color(.systemGray4))
                        .frame(width: beat == 0 ? 28 : 22,
                               height: beat == 0 ? 28 : 22)
                        .scaleEffect(beat == metronome.currentBeat && metronome.isPlaying ? 1.3 : 1.0)
                        .animation(.easeOut(duration: 0.1), value: metronome.currentBeat)
                }
            }
            .padding(.top, 20)

            Spacer()

            // Scale card
            scaleCard(session.currentScale)
                .padding(.horizontal, 20)

            Spacer()

            // Done button
            Button {
                session.donePracticing()
            } label: {
                Label("Done", systemImage: "checkmark")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.mint)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Quiz Phase

    private var quizPhase: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Round \(session.roundNumber)")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Scale \(session.currentIndex + 1) of 4")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer()

            // Question
            VStack(spacing: 12) {
                Text("What is the")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                Text(session.quizRelationship)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.mint)

                if let prev = session.previousScale {
                    Text("of \(prev.fullLabel)?")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                }
            }

            Spacer()

            // Reveal button
            Button {
                session.revealAnswer()
            } label: {
                Text("Reveal")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Reveal Phase

    private var revealPhase: some View {
        VStack(spacing: 0) {
            Spacer()

            // Context
            if let prev = session.previousScale {
                VStack(spacing: 4) {
                    Text("The \(session.quizRelationship.lowercased())")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    Text("of \(prev.fullLabel) is:")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            // Answer card
            scaleCard(session.currentScale)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            Spacer()

            // Self-grade buttons
            HStack(spacing: 16) {
                Button {
                    session.grade(correct: true)
                } label: {
                    Label("Got It", systemImage: "checkmark")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                Button {
                    session.grade(correct: false)
                } label: {
                    Label("Missed", systemImage: "xmark")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.red.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Round Complete Phase

    private var roundCompletePhase: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)

                Text("Round Complete!")
                    .font(.system(size: 26, weight: .bold, design: .rounded))

                // Scale chain
                VStack(spacing: 8) {
                    ForEach(Array(session.round.enumerated()), id: \.offset) { index, entry in
                        HStack(spacing: 8) {
                            if index > 0 {
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                            Text(entry.fullLabel)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(entry.isMajor ? Color.accentColor : .orange)
                        }
                    }
                }
                .padding(.vertical, 8)

                // Quiz score
                if session.totalQuizzed > 0 {
                    Text("Quiz: \(session.correctCount)/\(session.totalQuizzed) correct")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                session.nextRound()
                startMetronome()
            } label: {
                Label("Next Round", systemImage: "arrow.right")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.mint)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Shared Components

    @ViewBuilder
    private func scaleCard(_ entry: ScaleEntry?) -> some View {
        if let entry {
            VStack(spacing: 8) {
                Text(entry.fullLabel)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(entry.isMajor ? Color.accentColor : .orange)
                Text(entry.rootFretInfo)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
    }

    // MARK: - Metronome Control

    private func startMetronome() {
        metronome.bpm = session.bpm
        metronome.start()
    }
}

// MARK: - Note Symbol View

/// Draws a musical note with the correct number of flags for the given rhythm.
private struct NoteSymbolView: View {
    let rhythm: Rhythm
    let size: CGFloat

    private var flagCount: Int {
        switch rhythm {
        case .quarter:   return 0
        case .eighth:    return 1
        case .triplet:   return 1
        case .sixteenth: return 2
        }
    }

    private var isTriplet: Bool { rhythm == .triplet }
    private var headFilled: Bool { true }

    var body: some View {
        Canvas { context, canvasSize in
            let headRadius = size * 0.18
            let headCenter = CGPoint(
                x: canvasSize.width * 0.42,
                y: canvasSize.height - headRadius - size * 0.02
            )

            // Note head (filled oval, slightly tilted)
            let headRect = CGRect(
                x: headCenter.x - headRadius * 1.25,
                y: headCenter.y - headRadius * 0.85,
                width: headRadius * 2.5,
                height: headRadius * 1.7
            )
            var headPath = Path(ellipseIn: headRect)
            let tilt = CGAffineTransform(translationX: -headCenter.x, y: -headCenter.y)
                .concatenating(CGAffineTransform(rotationAngle: -.pi / 8))
                .concatenating(CGAffineTransform(translationX: headCenter.x, y: headCenter.y))
            headPath = headPath.applying(tilt)
            context.fill(headPath, with: .foreground)

            // Stem
            let stemX = headCenter.x + headRadius * 1.1
            let stemBottom = headCenter.y - headRadius * 0.3
            let stemTop = size * 0.08
            let stemWidth = size * 0.05

            let stemRect = CGRect(x: stemX - stemWidth / 2, y: stemTop, width: stemWidth, height: stemBottom - stemTop)
            context.fill(Path(stemRect), with: .foreground)

            // Flags
            if flagCount > 0 {
                for i in 0..<flagCount {
                    let flagY = stemTop + CGFloat(i) * size * 0.18
                    var flagPath = Path()
                    flagPath.move(to: CGPoint(x: stemX, y: flagY))
                    flagPath.addQuadCurve(
                        to: CGPoint(x: stemX + size * 0.22, y: flagY + size * 0.22),
                        control: CGPoint(x: stemX + size * 0.28, y: flagY + size * 0.06)
                    )
                    flagPath.addQuadCurve(
                        to: CGPoint(x: stemX, y: flagY + size * 0.16),
                        control: CGPoint(x: stemX + size * 0.18, y: flagY + size * 0.2)
                    )
                    flagPath.closeSubpath()
                    context.fill(flagPath, with: .foreground)
                }
            }

            // Triplet "3" annotation above the stem
            if isTriplet {
                context.draw(
                    Text("3")
                        .font(.system(size: size * 0.3, weight: .bold, design: .rounded)),
                    at: CGPoint(x: stemX, y: stemTop - size * 0.08),
                    anchor: .bottom
                )
            }
        }
        .frame(width: size * (isTriplet ? 0.75 : 0.7), height: size * (isTriplet ? 1.1 : 1.0))
    }
}

#Preview {
    ScaleStudyView()
}
