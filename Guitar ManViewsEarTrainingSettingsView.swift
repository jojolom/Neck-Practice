//
//  EarTrainingSettingsView.swift
//  Guitar Man
//

import SwiftUI

struct EarTrainingSettingsView: View {

    @Bindable var session: QuizSession
    @Environment(\.dismiss) private var dismiss
    @Environment(AudioSettings.self) private var audioSettings

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    @Bindable var audio = audioSettings
                    Toggle("Sound", isOn: $audio.isEnabled)
                } header: {
                    Text("Audio")
                } footer: {
                    Text("Plays the note automatically on each new question. Use \"Play Again\" to replay it anytime.")
                }

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
                    Text("Notes will appear between fret 1 and \(session.maxFret).")
                }

                Section {
                    Toggle("Naturals Only", isOn: $session.naturalsOnly)
                } header: {
                    Text("Note Set")
                } footer: {
                    Text("Start with natural notes (A–G) before adding sharps and flats.")
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
}

#Preview {
    EarTrainingSettingsView(session: QuizSession())
        .environment(AudioSettings())
}
