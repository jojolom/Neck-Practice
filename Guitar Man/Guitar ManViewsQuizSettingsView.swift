//
//  QuizSettingsView.swift
//  Guitar Man
//

import SwiftUI

struct QuizSettingsView: View {

    var session: QuizSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Max Fret")
                            Spacer()
                            Text("Fret \(session.maxFret)")
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(session.maxFret) },
                                set: { session.maxFret = Int($0) }
                            ),
                            in: 1...12,
                            step: 1
                        )
                    }
                } header: {
                    Text("Fret Range")
                } footer: {
                    Text("Quiz will cover frets 0 through \(session.maxFret). Start low and work your way up!")
                }

                Section {
                    Toggle("Naturals Only", isOn: $session.naturalsOnly)
                } header: {
                    Text("Note Set")
                } footer: {
                    Text("Master the natural notes (A–G) before adding sharps and flats.")
                }

                Section("Open String Mnemonics") {
                    mnemonicRow(string: "6 (Low E)", color: .orange)
                    mnemonicRow(string: "5 (A)", color: .yellow)
                    mnemonicRow(string: "4 (D)", color: .green)
                    mnemonicRow(string: "3 (G)", color: .teal)
                    mnemonicRow(string: "2 (B)", color: .blue)
                    mnemonicRow(string: "1 (High e)", color: .purple)
                    Text("**Eddie** Ate **D**ynamite, **G**oodbye **E**ddie")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func mnemonicRow(string: String, color: Color) -> some View {
        HStack {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text("String \(string)")
                .font(.subheadline)
        }
    }
}

#Preview {
    QuizSettingsView(session: QuizSession())
}
