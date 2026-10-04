//
//  SavedLoopsView.swift
//  Neck Practice
//
//  The saved-layers library: audition layers, rename or delete them, and pick some (up to the
//  number of free banks) to drop into the looper.
//

import SwiftUI
import SwiftData

/// "12.3 s", or "1:05.2" for a minute or more.
func formatLoopDuration(_ t: TimeInterval) -> String {
    if t >= 60 {
        return String(format: "%d:%04.1f", Int(t) / 60, t.truncatingRemainder(dividingBy: 60))
    }
    return String(format: "%.1f s", t)
}

struct SavedLoopsView: View {

    let looper: Looper

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SavedLoop.createdAt, order: .reverse) private var loops: [SavedLoop]

    /// Chosen layers in the order they'll fill the banks.
    @State private var selection: [UUID] = []
    @State private var preview = LoopPreviewPlayer()
    @State private var renaming: SavedLoop?
    @State private var renameText = ""
    @State private var pendingDelete: SavedLoop?
    @State private var errorMessage: String?

    private var slots: Int { looper.freeLayerSlots }

    var body: some View {
        NavigationStack {
            Group {
                if loops.isEmpty {
                    ContentUnavailableView(
                        "No Saved Layers",
                        systemImage: "tray",
                        description: Text("Use the save button on the looper to keep layers you want to reuse.")
                    )
                } else {
                    list
                }
            }
            .navigationTitle("Add from Saved")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selection.isEmpty ? "Add" : "Add \(selection.count)") { addSelected() }
                        .fontWeight(.semibold)
                        .disabled(selection.isEmpty)
                }
            }
            .alert("Rename Layer", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Save") { commitRename() }
                Button("Cancel", role: .cancel) { }
            }
            .confirmationDialog(
                "Delete \"\(pendingDelete?.name ?? "")\"?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let loop = pendingDelete { delete(loop) }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("The saved audio is removed from this device.")
            }
            .alert("Couldn't Add", isPresented: Binding(
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

    // MARK: - List

    private var list: some View {
        List {
            Section {
                ForEach(loops) { loop in
                    row(loop)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = loop
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                renameText = loop.name
                                renaming = loop
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                }
            } header: {
                Text(slots == 1 ? "Choose 1 layer" : "Choose up to \(slots) layers")
            } footer: {
                Text(footerText)
            }
        }
    }

    private var footerText: String {
        if looper.loopDuration > 0 {
            return "Added layers are padded or trimmed to the current loop (\(formatLoopDuration(looper.loopDuration))). Swipe a layer to rename or delete it."
        }
        return "The first layer you add sets the loop length; the rest are padded or trimmed to match. Swipe a layer to rename or delete it."
    }

    private func row(_ loop: SavedLoop) -> some View {
        let position = selection.firstIndex(of: loop.id)
        let isSelected = position != nil
        let atLimit = selection.count >= slots
        let disabled = !isSelected && atLimit

        return HStack(spacing: 12) {
            Button {
                toggle(loop)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(disabled)
            .accessibilityLabel(loop.name)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")

            VStack(alignment: .leading, spacing: 2) {
                Text(loop.name)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text("\(formatLoopDuration(loop.duration)) · \(loop.createdAt.formatted(.dateTime.month(.abbreviated).day().year()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if let position {
                Text("\(position + 1)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.accentColor, in: Circle())
                    .accessibilityLabel("Bank \(position + 1)")
            }

            Button {
                togglePreview(loop)
            } label: {
                Image(systemName: preview.playingID == AnyHashable(loop.id) ? "stop.circle.fill" : "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Preview \(loop.name)")
        }
        .opacity(disabled ? 0.45 : 1)
        .padding(.vertical, 2)
    }

    // MARK: - Actions

    private func toggle(_ loop: SavedLoop) {
        if let index = selection.firstIndex(of: loop.id) {
            selection.remove(at: index)
        } else if selection.count < slots {
            selection.append(loop.id)
        }
    }

    private func togglePreview(_ loop: SavedLoop) {
        // Keep the loop out of the way so you can hear the layer on its own.
        looper.stopPlayback()
        preview.playFile(id: loop.id, fileName: loop.fileName)
    }

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let loop = renaming, !trimmed.isEmpty {
            loop.name = trimmed
            try? modelContext.save()
        }
        renaming = nil
    }

    private func delete(_ loop: SavedLoop) {
        if preview.playingID == AnyHashable(loop.id) { preview.stop() }
        selection.removeAll { $0 == loop.id }
        modelContext.deleteSavedLoop(loop)
    }

    private func addSelected() {
        preview.stop()
        let rate = looper.sampleRate
        var layers: [[Float]] = []
        var failed: [String] = []

        for id in selection {
            guard let loop = loops.first(where: { $0.id == id }) else { continue }
            do {
                let audio = try LoopLibrary.read(fileName: loop.fileName)
                layers.append(LoopLibrary.resample(audio.samples, from: audio.sampleRate, to: rate))
            } catch {
                failed.append(loop.name)
            }
        }

        if !layers.isEmpty {
            looper.importLayers(layers, sampleRate: rate)
        }
        if failed.isEmpty {
            dismiss()
        } else {
            errorMessage = "These layers couldn't be loaded: \(failed.joined(separator: ", "))."
            selection.removeAll()
        }
    }
}
