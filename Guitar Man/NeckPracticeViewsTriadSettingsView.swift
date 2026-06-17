//
//  TriadSettingsView.swift
//  Neck Practice
//

import SwiftUI

struct TriadSettingsView: View {

    @Bindable var session: TriadSession
    @Environment(\.dismiss) private var dismiss
    @Environment(AudioSettings.self) private var audioSettings

    var body: some View {
        NavigationStack {
            Form {

                Section {
                    // String group filter
                    Picker("String Group", selection: $session.stringGroupFilter) {
                        Text("Both").tag(Optional<StringGroup>.none)
                        ForEach(StringGroup.allCases, id: \.self) { group in
                            Text(group.displayName).tag(Optional(group))
                        }
                    }
                } header: {
                    Text("String Group")
                } footer: {
                    Text("Practice one string group at a time or mix both.")
                }

                Section {
                    Picker("Quality", selection: $session.qualityFilter) {
                        Text("Both").tag(Optional<TriadQuality>.none)
                        ForEach(TriadQuality.allCases, id: \.self) { quality in
                            Text(quality.displayName).tag(Optional(quality))
                        }
                    }
                } header: {
                    Text("Chord Quality")
                } footer: {
                    Text("Focus on Major or Minor shapes, or practice both.")
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
                            in: 5...12,
                            step: 1
                        )
                    }
                } header: {
                    Text("Fret Range")
                } footer: {
                    Text("Shapes will appear anywhere between fret 1 and \(session.maxFret).")
                }

                Section {
                    Stepper("Root Choices: \(session.rootChoiceCount)",
                            value: $session.rootChoiceCount,
                            in: 4...12)
                } header: {
                    Text("Difficulty")
                } footer: {
                    Text("Fewer choices makes identifying the root note easier.")
                }

                Section {
                    @Bindable var audio = audioSettings
                    Toggle("Sound", isOn: $audio.isEnabled)
                } header: {
                    Text("Audio")
                } footer: {
                    Text("Play the triad when each question appears and when you answer.")
                }

                Section("Triad Shape Reference") {
                    shapeReferenceRow(label: "Major Root Position",  strings123: "[1,1,0]", strings234: "[2,1,0]", root123: "String 3", root234: "String 4")
                    shapeReferenceRow(label: "Major 1st Inversion",  strings123: "[1,0,1]", strings234: "[2,0,1]", root123: "String 1", root234: "String 2")
                    shapeReferenceRow(label: "Major 2nd Inversion",  strings123: "[0,1,1]", strings234: "[0,0,0]", root123: "String 2", root234: "String 3")
                    shapeReferenceRow(label: "Minor Root Position",  strings123: "[1,0,0]", strings234: "[2,0,0]", root123: "String 3", root234: "String 4")
                    shapeReferenceRow(label: "Minor 1st Inversion",  strings123: "[0,0,1]", strings234: "[1,0,1]", root123: "String 1", root234: "String 2")
                    shapeReferenceRow(label: "Minor 2nd Inversion",  strings123: "[0,1,0]", strings234: "[1,1,0]", root123: "String 2", root234: "String 3")
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
    private func shapeReferenceRow(label: String, strings123: String, strings234: String, root123: String, root234: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline.weight(.medium))
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("1-2-3: \(strings123)")
                    Text("Root: \(root123)")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text("2-3-4: \(strings234)")
                    Text("Root: \(root234)")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    TriadSettingsView(session: TriadSession())
}
