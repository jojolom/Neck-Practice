//
//  RomanNumeralSettingsView.swift
//  Neck Practice
//

import SwiftUI

struct RomanNumeralSettingsView: View {

    @Bindable var session: RomanNumeralSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Key", selection: $session.keyFilter) {
                        Text("All Keys").tag(Optional<Note>.none)
                        ForEach(Note.allCases) { note in
                            Text(note.displayName).tag(Optional(note))
                        }
                    }
                } header: {
                    Text("Key Filter")
                } footer: {
                    Text("Drill a specific key or randomize across all twelve.")
                }

                Section {
                    Picker("Scale", selection: $session.scaleFilter) {
                        Text("Both").tag(Optional<DiatonicScale>.none)
                        ForEach(DiatonicScale.allCases, id: \.self) { scale in
                            Text(scale.displayName).tag(Optional(scale))
                        }
                    }
                } header: {
                    Text("Scale Filter")
                } footer: {
                    Text("Practice Major scales, Minor scales, or a mix of both.")
                }

                Section {
                    Toggle("Easy Mode", isOn: $session.easyMode)
                    Stepper("Choices: \(session.choiceCount)",
                            value: $session.choiceCount,
                            in: 3...7)
                } header: {
                    Text("Difficulty")
                } footer: {
                    Text("Easy mode shows the other chord names on the chart as hints. Fewer choices also makes it easier.")
                }

                Section("Major Scale Degrees") {
                    referenceRow("I",    "Major")
                    referenceRow("ii",   "Minor")
                    referenceRow("iii",  "Minor")
                    referenceRow("IV",   "Major")
                    referenceRow("V",    "Major")
                    referenceRow("vi",   "Minor")
                    referenceRow("vii\u{00B0}", "Diminished")
                }

                Section("Minor Scale Degrees") {
                    referenceRow("i",    "Minor")
                    referenceRow("ii\u{00B0}", "Diminished")
                    referenceRow("III",  "Major")
                    referenceRow("iv",   "Minor")
                    referenceRow("v",    "Minor")
                    referenceRow("VI",   "Major")
                    referenceRow("VII",  "Major")
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
    private func referenceRow(_ numeral: String, _ quality: String) -> some View {
        HStack {
            Text(numeral)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .frame(width: 50, alignment: .leading)
            Text(quality)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    RomanNumeralSettingsView(session: RomanNumeralSession())
}
