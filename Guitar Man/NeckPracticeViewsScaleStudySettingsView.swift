//
//  ScaleStudySettingsView.swift
//  Neck Practice
//

import SwiftUI

struct ScaleStudySettingsView: View {

    @Bindable var session: ScaleStudySession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {

                // Mode selection
                Section {
                    Picker("Mode", selection: $session.rhythmMode) {
                        ForEach(RhythmMode.allCases, id: \.self) { mode in
                            Text(mode == .random ? "Random" : "Fixed").tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Rhythm Mode")
                } footer: {
                    Text(session.rhythmMode == .random
                         ? "Each round assigns a random rhythm and BPM."
                         : "You choose the rhythm and BPM for every round.")
                }

                // Conditional sections
                if session.rhythmMode == .fixed {
                    fixedModeSection
                } else {
                    randomModeSection
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

    // MARK: - Fixed Mode

    private var fixedModeSection: some View {
        Group {
            Section {
                Picker("Rhythm", selection: $session.fixedRhythm) {
                    ForEach(Rhythm.allCases, id: \.self) { rhythm in
                        Text(rhythm.label).tag(rhythm)
                    }
                }
            } header: {
                Text("Rhythm")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("BPM")
                        Spacer()
                        Text("\(session.fixedBPM)")
                            .foregroundStyle(.secondary)
                    }
                    let range = session.fixedRhythm.bpmRange
                    Slider(
                        value: Binding(
                            get: { Double(session.fixedBPM) },
                            set: { session.fixedBPM = Int(($0 / 5).rounded() * 5) }
                        ),
                        in: Double(range.lowerBound)...Double(range.upperBound),
                        step: 5
                    )
                }
            } header: {
                Text("Tempo")
            } footer: {
                Text("Range: \(session.fixedRhythm.bpmRange.lowerBound)–\(session.fixedRhythm.bpmRange.upperBound) BPM for \(session.fixedRhythm.label.lowercased()).")
            }
        }
    }

    // MARK: - Random Mode

    private var randomModeSection: some View {
        Section {
            ForEach(Rhythm.allCases, id: \.self) { rhythm in
                Toggle(rhythm.label, isOn: rhythmBinding(for: rhythm))
            }
        } header: {
            Text("Included Rhythms")
        } footer: {
            Text("Deselect rhythms you want to skip. At least one must remain enabled.")
        }
    }

    private func rhythmBinding(for rhythm: Rhythm) -> Binding<Bool> {
        Binding(
            get: { session.enabledRhythms.contains(rhythm) },
            set: { newValue in
                if newValue {
                    session.enabledRhythms.insert(rhythm)
                } else if session.enabledRhythms.count > 1 {
                    session.enabledRhythms.remove(rhythm)
                }
            }
        )
    }
}

#Preview {
    ScaleStudySettingsView(session: ScaleStudySession())
}
