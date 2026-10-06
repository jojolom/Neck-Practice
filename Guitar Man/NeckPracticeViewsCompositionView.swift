//
//  CompositionView.swift
//  Guitar Man
//
//  Compose: write a chord progression by dragging Roman numerals onto a staff (or tap a
//  numeral, then tap where it goes). Pick the key, 2–8 measures, and the note value. Each
//  chord shows its name in the key (IV in E♭ is A♭). The app doesn't play it back — you do,
//  optionally with Play Along listening and marking each chord green.
//  Compositions save automatically once they have a chord.
//

import SwiftUI

// MARK: - CompositionListView

struct CompositionListView: View {

    @State private var store = CompositionStore()

    var body: some View {
        List {
            Section {
                NavigationLink {
                    CompositionEditorView(composition: Composition(), store: store)
                } label: {
                    Label("New Composition", systemImage: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
            } footer: {
                Text("Drag Roman numerals onto the staff to build a progression, then play it yourself.")
            }

            if !store.compositions.isEmpty {
                Section("Saved") {
                    ForEach(store.compositions) { composition in
                        NavigationLink {
                            CompositionEditorView(composition: composition, store: store)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(composition.name)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                Text(summary(of: composition))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { store.delete(store.compositions[index].id) }
                    }
                }
            }
        }
        .navigationTitle("Compose")
    }

    private func summary(of composition: Composition) -> String {
        let numerals = composition.slots.compactMap { $0 }.map { composition.chord(degree: $0).romanNumeral }
        return "\(composition.keyName) · \(composition.measureCount) bars · " + numerals.joined(separator: " ")
    }
}

// MARK: - CompositionEditorView

struct CompositionEditorView: View {

    let store: CompositionStore
    @State private var composition: Composition
    /// Numeral picked in the palette for tap-to-place.
    @State private var selectedDegree: Int? = nil
    @State private var targetedSlot: Int? = nil
    @State private var showRename = false
    @State private var nameDraft = ""
    @State private var showPlayAlong = false

    init(composition: Composition, store: CompositionStore) {
        self.store = store
        _composition = State(initialValue: composition)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsCard

                CompositionStaffView(
                    composition: composition,
                    targetedSlot: targetedSlot,
                    onTap: { slot in place(selectedDegree, at: slot) },
                    onDrop: { slot, degree in place(degree, at: slot) },
                    onRemove: { slot in composition.slots[slot] = nil },
                    onTargetChange: { targetedSlot = $0 }
                )
                .padding(.horizontal, 12)

                palette

                Text("Drag a numeral onto the staff, or tap a numeral and then tap where it goes. Long-press a chord to remove it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
            .padding(.vertical, 12)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                showPlayAlong = true
            } label: {
                Label("Play Along", systemImage: "music.mic")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(composition.isEmpty ? Color.gray.opacity(0.4) : Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(composition.isEmpty)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .navigationTitle(composition.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        nameDraft = composition.name
                        showRename = true
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        composition.slots = Array(repeating: nil, count: composition.slotCount)
                    } label: {
                        Label("Clear All Chords", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .alert("Rename Composition", isPresented: $showRename) {
            TextField("Name", text: $nameDraft)
            Button("Save") {
                let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { composition.name = trimmed }
            }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showPlayAlong) {
            CompositionPlayAlongView(composition: composition)
        }
        // Save as you go, once there's something to keep.
        .onChange(of: composition) { _, updated in
            if !updated.isEmpty { store.save(updated) }
        }
    }

    // MARK: - Settings

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Key")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Picker("Key", selection: Binding(
                    get: { composition.keyRoot },
                    set: { composition.keyRoot = $0 }
                )) {
                    ForEach(Note.circleOfFifthsKeys(asMinor: composition.isMinor)) { note in
                        Text(keyLabel(note)).tag(note)
                    }
                }
                .pickerStyle(.menu)
                Picker("Scale", selection: $composition.isMinor) {
                    Text("Major").tag(false)
                    Text("Minor").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            Stepper("\(composition.measureCount) measures", value: Binding(
                get: { composition.measureCount },
                set: { composition.reshape(measureCount: $0, noteValue: composition.noteValue) }
            ), in: Composition.measureRange)
            .font(.system(size: 15, weight: .semibold, design: .rounded))

            Picker("Note Value", selection: Binding(
                get: { composition.noteValue },
                set: { composition.reshape(measureCount: composition.measureCount, noteValue: $0) }
            )) {
                ForEach(NoteValue.allCases) { value in
                    Text(value.displayName).tag(value)
                }
            }
            .pickerStyle(.segmented)

            if composition.noteValue == .dottedHalf {
                Text("Dotted halves fill a measure of 3/4.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func keyLabel(_ note: Note) -> String {
        let key = KeySignature(root: note, isMinor: composition.isMinor)
        let name = composition.isMinor ? key.minorKeyName : key.majorKeyName
        return name.components(separatedBy: " ").first ?? name
    }

    // MARK: - Palette

    private var palette: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let degree = selectedDegree {
                let chord = composition.chord(degree: degree)
                Text("\(chord.romanNumeral) in \(composition.keyName) is \(chord.longName)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 20)
            } else {
                Text("Chords in \(composition.keyName)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 20)
            }

            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { degree in
                    let chord = composition.chord(degree: degree)
                    let isSelected = selectedDegree == degree
                    VStack(spacing: 2) {
                        Text(chord.romanNumeral)
                            .font(.system(size: 17, weight: .bold, design: .serif))
                        Text(chord.name)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                    }
                    .foregroundStyle(isSelected ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture {
                        selectedDegree = isSelected ? nil : degree
                    }
                    .draggable(String(degree)) {
                        Text("\(chord.romanNumeral)  \(chord.name)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                    .accessibilityLabel("\(chord.romanNumeral), \(chord.longName)")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func place(_ degree: Int?, at slot: Int) {
        guard let degree, composition.slots.indices.contains(slot) else { return }
        composition.slots[slot] = degree
    }
}

// MARK: - CompositionStaffView

/// The composition on a staff, two measures per line. With the editing closures it accepts
/// drops and taps per slot; without them it's read-only (Play Along) and `slotColors` tints chords.
struct CompositionStaffView: View {

    let composition: Composition
    var slotColors: [Int: Color] = [:]
    var targetedSlot: Int? = nil
    var onTap: ((Int) -> Void)? = nil
    var onDrop: ((_ slot: Int, _ degree: Int) -> Void)? = nil
    var onRemove: ((Int) -> Void)? = nil
    var onTargetChange: ((Int?) -> Void)? = nil

    private let lineSpacing: CGFloat = 9
    private let measuresPerLine = 2

    private var isEditable: Bool { onDrop != nil }

    var body: some View {
        let key = composition.keySignature
        VStack(spacing: 4) {
            ForEach(Array(stride(from: 0, to: composition.measureCount, by: measuresPerLine)), id: \.self) { first in
                let beats: Int? = first == 0 ? composition.beatsPerMeasure : nil
                HStack(spacing: 0) {
                    StaffView(keySignature: key, columns: [], beatsPerMeasure: beats, lineSpacing: lineSpacing)
                        .frame(width: StaffView.headerWidth(keySignature: key, beatsPerMeasure: beats,
                                                            lineSpacing: lineSpacing))
                    ForEach(first..<min(first + measuresPerLine, composition.measureCount), id: \.self) { measure in
                        ForEach(0..<composition.slotsPerMeasure, id: \.self) { beat in
                            slotView(measure * composition.slotsPerMeasure + beat,
                                     endsMeasure: beat == composition.slotsPerMeasure - 1)
                        }
                    }
                    // A short last line keeps measures the same width as full ones.
                    if first + measuresPerLine > composition.measureCount {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 120)
            }
        }
    }

    @ViewBuilder
    private func slotView(_ slot: Int, endsMeasure: Bool) -> some View {
        let degree = composition.slots.indices.contains(slot) ? composition.slots[slot] : nil
        let chord = degree.map { composition.chord(degree: $0) }
        let columns: [StaffColumn] = chord.map {
            [StaffColumn(id: slot, pitches: $0.pitches, value: composition.noteValue,
                         above: $0.name, below: $0.romanNumeral, color: slotColors[slot])]
        } ?? []

        StaffView(keySignature: composition.keySignature, columns: columns,
                  showsClef: false, showsKeySignature: false, showsEndBarline: endsMeasure,
                  lineSpacing: lineSpacing)
            .frame(maxWidth: .infinity)
            .background(targetedSlot == slot ? Color.accentColor.opacity(0.18) : Color.clear)
            .overlay {
                if chord == nil && isEditable {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap?(slot) }
            .contextMenu {
                if chord != nil, let onRemove {
                    Button(role: .destructive) {
                        onRemove(slot)
                    } label: {
                        Label("Remove Chord", systemImage: "trash")
                    }
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let onDrop, let degree = items.first.flatMap({ Int($0) }), (1...7).contains(degree) else {
                    return false
                }
                onDrop(slot, degree)
                return true
            } isTargeted: { targeted in
                guard isEditable else { return }
                if targeted {
                    onTargetChange?(slot)
                } else if targetedSlot == slot {
                    onTargetChange?(nil)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chord.map { "\($0.romanNumeral), \($0.longName)" } ?? "Empty beat")
            .accessibilityHint(isEditable ? "Tap to place the selected chord" : "")
    }
}

#Preview {
    NavigationStack {
        CompositionListView()
    }
}
