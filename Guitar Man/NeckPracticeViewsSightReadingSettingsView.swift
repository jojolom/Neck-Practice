//
//  SightReadingSettingsView.swift
//  Neck Practice
//

import SwiftUI

struct SightReadingSettingsView: View {

    @Bindable var session: SightReadingSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Fretboard") {
                    Stepper("Max Fret: \(session.maxFret)",
                            value: $session.maxFret, in: 3...12)

                    Toggle("Naturals Only", isOn: $session.naturalsOnly)
                }
            }
            .navigationTitle("Sight Reading Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
