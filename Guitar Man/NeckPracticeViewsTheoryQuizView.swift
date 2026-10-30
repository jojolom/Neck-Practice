//
//  TheoryQuizView.swift
//  Guitar Man
//
//  Theory Basics: multiple-choice theory questions from the topics switched on in Settings.
//  Circle-of-fifths questions show a blank wheel with one key filled in and a "?" slice; once
//  answered, every slice gets its name.
//

import SwiftUI

struct TheoryQuizView: View {

    @State private var session = TheoryQuizSession()
    @State private var picked: String? = nil
    @State private var revealAnswer = false
    @State private var isLocked = false
    @State private var showSettings = false
    /// Holds the move to the next question until Next is tapped (see AnswerPacing).
    @State private var nextGate = NextGate()

    var body: some View {
        NavigationContainer {
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
                        NextButton(gate: nextGate)
                            .padding(.top, 8)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Theory Basics")
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
            .sheet(isPresented: $showSettings, onDismiss: skipHiddenTopic) {
                TheoryQuizSettingsView(session: session)
            }
            // Drawing a question bumps questionNumber, which resets the screen.
            .onAppear { session.start() }
            .onChange(of: session.questionNumber) {
                nextGate.cancel()
                picked = nil
                revealAnswer = false
                isLocked = false
            }
        }
    }

    @ViewBuilder
    private func question(_ q: TheoryQuestion) -> some View {
        Text(q.kind.topic.displayName.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 16)

        Text(q.prompt)
            .font(.system(size: 20, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.top, 4)

        if let wheel = q.wheel {
            TheoryWheelView(wheel: wheel, answeredCorrectly: revealAnswer ? picked == q.answer : nil)
                .frame(maxWidth: 340)
                .padding(.horizontal, 16)
                .padding(.top, 12)
        }

        if revealAnswer {
            Text(q.explanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .padding(.top, 12)
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
        .padding(.top, 12)
    }

    private func handleAnswer(_ choice: String) {
        guard !isLocked else { return }
        isLocked = true
        picked = choice
        let correct = session.answer(choice)
        withAnimation(.easeInOut(duration: 0.2)) { revealAnswer = true }
        nextGate.after(correct ? 1.5 : 3, correct: correct) {
            session.advance()
        }
    }

    /// Settings closed with the current question's topic switched off: move on to one that's on.
    private func skipHiddenTopic() {
        guard let q = session.currentQuestion, !session.topics.contains(q.kind.topic) else { return }
        nextGate.cancel()
        session.advance()
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

// MARK: - Wheel

/// The circle of fifths, C at the top: major keys in the outer ring, minor keys in the inner one.
/// Only the shown key and the "?" are filled in until the question is answered.
struct TheoryWheelView: View {

    let wheel: TheoryWheel
    /// Nil until answered.
    let answeredCorrectly: Bool?

    /// Each ring's inner and outer edge, as a fraction of the radius.
    private static let outerRing: (inner: CGFloat, outer: CGFloat) = (0.64, 1.0)
    private static let innerRing: (inner: CGFloat, outer: CGFloat) = (0.3, 0.64)

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                ForEach(0..<12, id: \.self) { position in
                    slice(position: position, isMinor: false)
                    slice(position: position, isMinor: true)
                }
                ForEach(0..<12, id: \.self) { position in
                    sliceLabel(position: position, isMinor: false, size: size, center: center)
                    sliceLabel(position: position, isMinor: true, size: size, center: center)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private func slice(position: Int, isMinor: Bool) -> some View {
        let ring = isMinor ? Self.innerRing : Self.outerRing
        let shape = WheelSlice(position: position, inner: ring.inner, outer: ring.outer)
        return shape
            .fill(sliceColor(position: position, isMinor: isMinor))
            .overlay(shape.stroke(Color(.systemGray3), lineWidth: 0.5))
    }

    private func sliceColor(position: Int, isMinor: Bool) -> Color {
        let ringColor = isMinor ? Color.orange : Color.accentColor
        if Self.matches(wheel.shown, position, isMinor) { return ringColor.opacity(0.35) }
        if Self.matches(wheel.asked, position, isMinor) {
            switch answeredCorrectly {
            case .some(true):  return Color.green.opacity(0.35)
            case .some(false): return Color.red.opacity(0.3)
            case .none:        return Color.yellow.opacity(0.3)
            }
        }
        return ringColor.opacity(0.06)
    }

    @ViewBuilder
    private func sliceLabel(position: Int, isMinor: Bool, size: CGFloat, center: CGPoint) -> some View {
        let ring = isMinor ? Self.innerRing : Self.outerRing
        let radius = size / 2 * (ring.inner + ring.outer) / 2
        let angle = Angle(degrees: 30 * Double(position) - 90)
        let point = CGPoint(x: center.x + radius * cos(angle.radians), y: center.y + radius * sin(angle.radians))
        let fontSize = size * (isMinor ? 0.04 : 0.05)

        if Self.matches(wheel.shown, position, isMinor) {
            Text(wheel.shown.label)
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .position(point)
        } else if Self.matches(wheel.asked, position, isMinor) {
            Text(answeredCorrectly == nil ? "?" : wheel.asked.label)
                .font(.system(size: fontSize * 1.15, weight: .heavy, design: .rounded))
                .position(point)
        } else if answeredCorrectly != nil {
            // Answered: name the rest of the circle too, so the whole wheel sinks in.
            Text(TheoryKey.onWheel(position, isMinor: isMinor).shortName)
                .font(.system(size: fontSize * 0.85, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .position(point)
        }
    }

    private static func matches(_ slice: TheoryWheel.Slice, _ position: Int, _ isMinor: Bool) -> Bool {
        slice.position == position && slice.isMinor == isMinor
    }

    private var accessibilityDescription: String {
        let shown = wheel.shown, asked = wheel.asked
        let place: String
        if asked.position == shown.position {
            place = "on the same slice, in the \(asked.isMinor ? "inner" : "outer") ring"
        } else if (asked.position - shown.position + 12) % 12 == 1 {
            place = "one slice clockwise"
        } else {
            place = "one slice counterclockwise"
        }
        let answer = answeredCorrectly == nil ? "a question mark" : asked.label
        return "Circle of fifths showing \(shown.label), with \(answer) \(place)."
    }
}

/// One slice of one ring: 30°, centred on `position` (0 = top, clockwise).
private struct WheelSlice: Shape {
    let position: Int
    /// Inner and outer edge, as a fraction of the radius.
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let start = Angle(degrees: 30 * Double(position) - 90 - 15)
        let end = Angle(degrees: 30 * Double(position) - 90 + 15)
        var path = Path()
        path.addArc(center: center, radius: radius * outer, startAngle: start, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: radius * inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - Settings

struct TheoryQuizSettingsView: View {

    @Bindable var session: TheoryQuizSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                AnswerPacingSection()

                Section {
                    ForEach(TheoryTopic.allCases) { topic in
                        Toggle(topic.displayName, isOn: Binding(
                            get: { session.topics.contains(topic) },
                            set: { isOn in
                                if isOn { session.topics.insert(topic) } else { session.topics.remove(topic) }
                            }))
                        // Keep at least one topic on.
                        .disabled(session.topics == [topic])
                    }
                } header: {
                    Text("Topics")
                } footer: {
                    Text("Questions are drawn at random from the topics that are on.")
                }
            }
            .navigationTitle("Theory Basics Settings")
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
    TheoryQuizView()
}
