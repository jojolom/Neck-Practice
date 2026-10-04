//
//  SaveLayersView.swift
//  Neck Practice
//
//  Sheet for saving looper layers to the library: pick which layers (or Select all), name
//  each one right here, preview with ▶, then Save writes one SavedLoop per checked layer.
//

import SwiftUI
import SwiftData

struct SaveLayersView: View {

    let looper: Looper

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<Int> = []
    @State private var names: [Int: String] = [:]
    @State private var preview = LoopPreviewPlayer()
    @State private var errorMessage: String?
    /// Fixed when the sheet opens so default names carry a stable date.
    @State private var openedAt = Date()

    private var layerCount: Int { looper.layerCount }
    private var allSelected: Bool { layerCount > 0 && selected.count == layerCount }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        toggleAll()
                    } label: {
                        HStack(spacing: 12) {
                            checkbox(allSelected)
                            Text("Select all")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    ForEach(0..<layerCount, id: \.self) { index in
                        layerRow(index)
                    }
                } header: {
                    Text("Layers")
                } footer: {
                    Text("Each checked layer is saved on its own, so you can mix them into any loop later.")
                }
            }
            .navigationTitle("Save Layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(selected.isEmpty)
                }
            }
            .alert("Couldn't Save", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage ?? "")
            }
            .onDisappear { preview.stop() }
        }
    }

    // MARK: - Rows

    private func layerRow(_ index: Int) -> some View {
        let isSelected = selected.contains(index)
        let color = LayerPalette.colors[index % LayerPalette.colors.count]

        return HStack(spacing: 12) {
            Button {
                toggle(index)
            } label: {
                checkbox(isSelected)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Layer \(index + 1)")
            .accessibilityValue(isSelected ? "Selected" : "Not selected")

            Circle()
                .fill(color.gradient)
                .frame(width: 34, height: 34)
                .overlay(
                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Layer \(index + 1)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                if isSelected {
                    TextField("Name", text: nameBinding(index))
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.done)
                }
            }

            Spacer(minLength: 8)

            Button {
                togglePreview(index)
            } label: {
                Image(systemName: preview.playingID == AnyHashable(index) ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(color)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview layer \(index + 1)")
        }
        .padding(.vertical, 2)
    }

    private func checkbox(_ isOn: Bool) -> some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(isOn ? Color.accentColor : .secondary)
    }

    // MARK: - Selection & names

    private func defaultName(for index: Int) -> String {
        "Layer \(index + 1) – \(openedAt.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func nameBinding(_ index: Int) -> Binding<String> {
        Binding(
            get: { names[index] ?? defaultName(for: index) },
            set: { names[index] = $0 }
        )
    }

    private func toggle(_ index: Int) {
        if selected.contains(index) {
            selected.remove(index)
        } else {
            selected.insert(index)
        }
    }

    private func toggleAll() {
        selected = allSelected ? [] : Set(0..<layerCount)
    }

    // MARK: - Preview

    private func togglePreview(_ index: Int) {
        guard let samples = looper.layerSamples(at: index) else { return }
        // Keep the loop out of the way so you can hear the layer on its own.
        looper.stopPlayback()
        preview.playSamples(id: index, samples: samples, sampleRate: looper.sampleRate)
    }

    // MARK: - Save

    private func save() {
        preview.stop()
        let rate = looper.sampleRate
        var writtenFiles: [String] = []

        do {
            for index in selected.sorted() {
                guard let samples = looper.layerSamples(at: index) else { continue }
                let fileName = try LoopLibrary.write(samples: samples, sampleRate: rate)
                writtenFiles.append(fileName)

                let typed = names[index]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                modelContext.insert(SavedLoop(
                    name: typed.isEmpty ? defaultName(for: index) : typed,
                    createdAt: .now,
                    duration: Double(samples.count) / rate,
                    sampleRate: rate,
                    fileName: fileName
                ))
            }
            try modelContext.save()
            dismiss()
        } catch {
            // Don't leave half a save behind.
            modelContext.rollback()
            for fileName in writtenFiles { LoopLibrary.delete(fileName: fileName) }
            errorMessage = "Your layers couldn't be written to this device. Check that there's free storage and try again."
        }
    }
}
