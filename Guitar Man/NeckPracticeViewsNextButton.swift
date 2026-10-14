//
//  NextButton.swift
//  Guitar Man
//
//  The games' Next button, shown under the answers while a NextGate is waiting, and the
//  After Answering setting each game's Settings sheet includes (see AnswerPacing).
//

import SwiftUI

struct NextButton: View {

    let gate: NextGate

    var body: some View {
        if gate.isWaiting {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { gate.next() }
            } label: {
                Label("Next", systemImage: "arrow.right")
                    .labelStyle(.titleAndIcon)
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
            .keyboardShortcut(.defaultAction)
        }
    }
}

/// The After Answering choice, for a game's Settings form. It's one setting for every game.
struct AnswerPacingSection: View {

    @AppStorage(AnswerPacing.key) private var pacing: AnswerPacing = .always

    var body: some View {
        Section {
            Picker("After Answering", selection: $pacing) {
                ForEach(AnswerPacing.allCases) { pacing in
                    Text(pacing.displayName).tag(pacing)
                }
            }
        } footer: {
            Text("Wait for Next leaves the answer on screen until you tap Next. This setting applies to every game.")
        }
    }
}
