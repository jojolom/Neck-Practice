//
//  PentatonicSettingsView.swift
//  Neck Practice
//

import SwiftUI

struct PentatonicSettingsView: View {

    @Bindable var session: PentatonicSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {

                Section {
                    Picker("Quality", selection: $session.qualityFilter) {
                        Text("Both").tag(Optional<PentatonicQuality>.none)
                        ForEach(PentatonicQuality.allCases, id: \.self) { quality in
                            Text(quality.displayName).tag(Optional(quality))
                        }
                    }
                } header: {
                    Text("Scale Quality")
                } footer: {
                    Text("Practice naming Minor roots, Major roots, or a mix of both.")
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
                            in: 7...22,
                            step: 1
                        )
                    }
                } header: {
                    Text("Fret Range")
                } footer: {
                    Text("Shapes will appear anywhere between fret 1 and \(session.maxFret). Higher values push shapes up the neck.")
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

                Section("Position Reference") {
                    positionReferenceRow(
                        position: 1,
                        subtitle: "\"The Blues Box\"",
                        notes: "S6[0,3]  S5[0,2]  S4[0,2]  S3[0,2]  S2[0,3]  S1[0,3]",
                        roots: "Low E (open), D string (+2), High e (open)"
                    )
                    positionReferenceRow(
                        position: 2,
                        subtitle: nil,
                        notes: "S6[3,5]  S5[2,5]  S4[2,5]  S3[2,4]  S2[3,5]  S1[3,5]",
                        roots: "D string (+2), B string (+5)"
                    )
                    positionReferenceRow(
                        position: 3,
                        subtitle: nil,
                        notes: "S6[5,7]  S5[5,7]  S4[5,7]  S3[4,7]  S2[5,8]  S1[5,7]",
                        roots: "A string (+7), B string (+5)"
                    )
                    positionReferenceRow(
                        position: 4,
                        subtitle: nil,
                        notes: "S6[7,10]  S5[7,10]  S4[7,9]  S3[7,9]  S2[8,10]  S1[7,10]",
                        roots: "A string (+7), G string (+9)"
                    )
                    positionReferenceRow(
                        position: 5,
                        subtitle: nil,
                        notes: "S6[-2,0]  S5[-2,0]  S4[-3,0]  S3[-3,0]  S2[-2,0]  S1[-2,0]",
                        roots: "Low E (anchor), G string (-3), High e (anchor)"
                    )
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
    private func positionReferenceRow(position: Int, subtitle: String?, notes: String, roots: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Position \(position)")
                    .font(.subheadline.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(notes)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("Roots: \(roots)")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    PentatonicSettingsView(session: PentatonicSession())
}
