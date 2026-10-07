//
//  CompositionView.swift
//  Guitar Man
//
//  Compose: write a chord progression by dragging Roman numerals onto a staff (or tap a
//  numeral, then tap where it goes). Pick the key, 4/4 or 3/4, 2–8 measures, and the length of
//  each chord as you place it (long-press a chord to change it); rests fill the gaps. Each
//  chord shows its name in the key (IV in E♭ is A♭). You play it, optionally with Play Along
//  listening and marking each chord green. (Hidden Playback settings add a speaker button that
//  plays it — see CompositionPlayer.) Compositions save automatically once they have a chord.
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
        let numerals = composition.chords.map { composition.chord(degree: $0.degree).romanNumeral }
        return "\(composition.keyName) · \(composition.meterName) · \(composition.measureCount) bars · "
            + numerals.joined(separator: " ")
    }
}

// MARK: - CompositionEditorView

struct CompositionEditorView: View {

    let store: CompositionStore
    @State private var composition: Composition
    /// Numeral picked in the palette for tap-to-place.
    @State private var selectedDegree: Int? = nil
    /// Length of the next chord placed.
    @AppStorage("compose.noteValue") private var noteValue: NoteValue = .whole
    /// "Shortened to fit" after a placement, briefly.
    @State private var hint: String? = nil
    @State private var hintTask: Task<Void, Never>? = nil
    @State private var targetedBeat: Int? = nil
    @State private var showRename = false
    @State private var nameDraft = ""
    @State private var showPlayAlong = false
    /// Hidden Playback settings (tap "Key" five times quickly): a speaker button that plays the
    /// progression, all at once or arpeggiated.
    @AppStorage(CompositionPlayer.unlockedKey) private var playbackSettingsUnlocked = false
    @AppStorage(CompositionPlayer.enabledKey) private var hearPlayback = false
    @AppStorage(CompositionPlayer.styleKey) private var playbackStyle: CompositionPlaybackStyle = .together
    @AppStorage(CompositionPlayer.tempoKey) private var playbackTempo = CompositionPlayer.defaultTempo
    @Environment(\.scenePhase) private var scenePhase
    @State private var player = CompositionPlayer()
    @State private var keyTaps = 0
    @State private var lastKeyTap = Date.distantPast

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
                    chordColors: player.playingChord.map { [$0: Color.accentColor] } ?? [:],
                    targetedBeat: targetedBeat,
                    onTap: { beat in place(selectedDegree, at: beat) },
                    onDrop: { beat, degree in place(degree, at: beat) },
                    onRemove: { beat in composition.removeChord(covering: beat) },
                    onSetLength: { start, value in composition.setLength(ofChordAt: start, to: value) },
                    onTargetChange: { targetedBeat = $0 }
                )
                .padding(.horizontal, 12)

                palette

                Text("Drag a numeral onto a beat, or tap a numeral and then tap the beat. Long-press a chord to change its length or remove it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            }
            .padding(.vertical, 12)
        }
        // "Shortened to fit", floating just above the buttons so it's seen wherever you've scrolled.
        .overlay(alignment: .bottom) {
            if let hint {
                Label(hint, systemImage: "arrow.left.and.right.square")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .animation(.spring(duration: 0.3), value: hint)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                if hearPlayback {
                    Button {
                        player.isPlaying ? player.stop() : player.play(composition, style: playbackStyle, bpm: playbackTempo)
                    } label: {
                        Image(systemName: player.isPlaying ? "stop.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(composition.isEmpty ? Color.secondary : Color.accentColor)
                            .frame(width: 52)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(composition.isEmpty)
                    .accessibilityLabel(player.isPlaying ? "Stop" : "Hear the progression")
                }
                Button {
                    player.stop()
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
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
        // Playback is of what's on screen as it's set up now: any change stops it.
        .onDisappear { player.stop() }
        .onChange(of: playbackStyle) { player.stop() }
        .onChange(of: playbackTempo) { player.stop() }
        .onChange(of: hearPlayback) { player.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.stop() }
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
                        composition.clearChords()
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
        // Save as you go, once there's something to keep (and keep saving a saved one, so
        // clearing its chords sticks).
        .onChange(of: composition) { _, updated in
            player.stop()
            if !updated.isEmpty || store.compositions.contains(where: { $0.id == updated.id }) {
                store.save(updated)
            }
        }
    }

    // MARK: - Settings

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Key")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .contentShape(Rectangle())
                    .onTapGesture { tapKeyLabel() }
                    .sensoryFeedback(.success, trigger: playbackSettingsUnlocked)
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

            HStack {
                Text("Time")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Picker("Time Signature", selection: Binding(
                    get: { composition.beatsPerMeasure },
                    set: { composition.setBeatsPerMeasure($0) }
                )) {
                    ForEach(Composition.meters, id: \.self) { beats in
                        Text("\(beats)/4").tag(beats)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            Stepper("\(composition.measureCount) measures", value: Binding(
                get: { composition.measureCount },
                set: { composition.setMeasureCount($0) }
            ), in: Composition.measureRange)
            .font(.system(size: 15, weight: .semibold, design: .rounded))

            if playbackSettingsUnlocked {
                playbackSettings
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    /// The hidden Playback settings.
    private var playbackSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Toggle(isOn: $hearPlayback) {
                Label("Hear Compositions", systemImage: "speaker.wave.2")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            if hearPlayback {
                HStack(spacing: 10) {
                    Picker("Playback Style", selection: $playbackStyle) {
                        ForEach(CompositionPlaybackStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 190)
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text("\(playbackTempo)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("BPM")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .fixedSize()
                    Stepper("Tempo", value: $playbackTempo, in: CompositionPlayer.tempoRange, step: 5)
                        .labelsHidden()
                        .accessibilityValue("\(playbackTempo) beats per minute")
                }
            }
        }
    }

    /// Five taps on "Key", each within a second of the last, shows or hides the Playback settings.
    private func tapKeyLabel() {
        let now = Date()
        keyTaps = now.timeIntervalSince(lastKeyTap) < 1 ? keyTaps + 1 : 1
        lastKeyTap = now
        guard keyTaps >= 5 else { return }
        keyTaps = 0
        withAnimation(.spring(duration: 0.3)) { playbackSettingsUnlocked.toggle() }
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

            Picker("Length", selection: $noteValue) {
                ForEach(composition.noteValues) { value in
                    Text(value.displayName).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .accessibilityHint("The length of the next chord you place")
        }
        // A whole note doesn't fit in 3/4.
        .onChange(of: composition.beatsPerMeasure, initial: true) { _, beats in
            if noteValue.beats > beats { noteValue = NoteValue(beats: beats) ?? .quarter }
        }
    }

    private func place(_ degree: Int?, at beat: Int) {
        guard let degree, let beats = composition.place(degree, at: beat, value: noteValue) else { return }
        guard beats < noteValue.beats, let fitted = NoteValue(beats: beats) else { return }
        hintTask?.cancel()
        hint = "Shortened to a \(fitted.displayName.lowercased()) note to fit."
        hintTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { hint = nil }
        }
    }
}

// MARK: - CompositionStaffView

/// The composition on a staff, two measures per line, each measure split into its beats. A
/// chord is written on the beat it starts on, as its note value; gaps are written as rests (an
/// empty measure in the editor shows a + on each beat instead, to invite a chord). With the
/// editing closures every beat takes taps and drops, and a chord's long-press menu changes its
/// length or removes it; without them it's read-only (Play Along) and `chordColors` (by start
/// beat) tints chords.
struct CompositionStaffView: View {

    let composition: Composition
    var chordColors: [Int: Color] = [:]
    var targetedBeat: Int? = nil
    var onTap: ((Int) -> Void)? = nil
    var onDrop: ((_ beat: Int, _ degree: Int) -> Void)? = nil
    var onRemove: ((Int) -> Void)? = nil
    var onSetLength: ((_ start: Int, _ value: NoteValue) -> Void)? = nil
    var onTargetChange: ((Int?) -> Void)? = nil

    private let lineSpacing: CGFloat = 9
    private let measuresPerLine = 2

    private var isEditable: Bool { onDrop != nil }

    var body: some View {
        let key = composition.keySignature
        VStack(spacing: 4) {
            ForEach(Array(stride(from: 0, to: composition.measureCount, by: measuresPerLine)), id: \.self) { first in
                let meter: Int? = first == 0 ? composition.beatsPerMeasure : nil
                HStack(spacing: 0) {
                    StaffView(keySignature: key, columns: [], beatsPerMeasure: meter, lineSpacing: lineSpacing)
                        .frame(width: StaffView.headerWidth(keySignature: key, beatsPerMeasure: meter,
                                                            lineSpacing: lineSpacing))
                    ForEach(first..<min(first + measuresPerLine, composition.measureCount), id: \.self) { measure in
                        measureView(measure)
                    }
                    // A short last line keeps its measure the same width as on a full line.
                    if first + measuresPerLine > composition.measureCount {
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 120)
            }
        }
    }

    // MARK: Measure

    private func measureView(_ measure: Int) -> some View {
        let beats = composition.beatsPerMeasure
        let first = measure * beats
        return StaffView(keySignature: composition.keySignature, columns: columns(inMeasure: measure),
                         showsClef: false, showsKeySignature: false, showsEndBarline: true,
                         edgeToEdge: true, lineSpacing: lineSpacing)
            .frame(maxWidth: .infinity)
            .overlay {
                if isEditable {
                    HStack(spacing: 0) {
                        ForEach(first..<first + beats, id: \.self) { beat in
                            beatCell(beat, emptyMeasure: composition.rests(inMeasure: measure).first?.glyph == .whole)
                        }
                    }
                }
            }
            .accessibilityElement(children: isEditable ? .contain : .combine)
    }

    private func columns(inMeasure measure: Int) -> [StaffColumn] {
        let beats = composition.beatsPerMeasure
        let first = measure * beats
        let rests = composition.rests(inMeasure: measure)
        if rests.first?.glyph == .whole {
            // Empty: + signs in the editor (drawn by the cells), else one whole rest, centered.
            return isEditable ? [] : [StaffColumn(id: first, pitches: [], rest: .whole)]
        }
        return (first..<first + beats).map { beat in
            if let placed = composition.chords.first(where: { $0.start == beat }) {
                let chord = composition.chord(degree: placed.degree)
                return StaffColumn(id: beat, pitches: chord.pitches, value: placed.value,
                                   above: chord.name, below: chord.romanNumeral, color: chordColors[beat])
            }
            if let rest = rests.first(where: { $0.start == beat }) {
                return StaffColumn(id: beat, pitches: [], color: Color(.secondaryLabel), rest: rest.glyph)
            }
            return StaffColumn(id: beat, pitches: [])
        }
    }

    // MARK: Beat (editor)

    private func beatCell(_ beat: Int, emptyMeasure: Bool) -> some View {
        let covering = composition.chord(covering: beat)
        return Rectangle()
            .fill(targetedBeat == beat ? Color.accentColor.opacity(0.18) : Color.clear)
            .overlay {
                if emptyMeasure {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap?(beat) }
            .contextMenu {
                if let covering {
                    let room = composition.room(at: covering.start)
                    Section("Length") {
                        ForEach(composition.noteValues.filter { $0.beats <= room }) { value in
                            Button {
                                onSetLength?(covering.start, value)
                            } label: {
                                if value == covering.value {
                                    Label(value.displayName, systemImage: "checkmark")
                                } else {
                                    Text(value.displayName)
                                }
                            }
                        }
                    }
                    Button(role: .destructive) {
                        onRemove?(covering.start)
                    } label: {
                        Label("Remove Chord", systemImage: "trash")
                    }
                }
            } preview: {
                chordPreview(covering)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let onDrop, let degree = items.first.flatMap({ Int($0) }), (1...7).contains(degree) else {
                    return false
                }
                onDrop(beat, degree)
                return true
            } isTargeted: { targeted in
                if targeted {
                    onTargetChange?(beat)
                } else if targetedBeat == beat {
                    onTargetChange?(nil)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(beat: beat, covering: covering))
            .accessibilityHint("Tap to place the selected chord here")
    }

    @ViewBuilder
    private func chordPreview(_ placed: Composition.PlacedChord?) -> some View {
        if let placed {
            let chord = composition.chord(degree: placed.degree)
            VStack(spacing: 2) {
                StaffView(keySignature: composition.keySignature,
                          columns: [StaffColumn(id: 0, pitches: chord.pitches, value: placed.value,
                                                above: chord.name, below: chord.romanNumeral)],
                          showsClef: true, lineSpacing: lineSpacing)
                    .frame(width: 130, height: 120)
                Text("\(chord.longName) · \(placed.value.displayName.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 12)
        } else {
            Color.clear.frame(width: 1, height: 1)
        }
    }

    private func accessibilityLabel(beat: Int, covering: Composition.PlacedChord?) -> String {
        let beats = composition.beatsPerMeasure
        let place = "Measure \(beat / beats + 1), beat \(beat % beats + 1)"
        guard let covering else { return "\(place): rest" }
        let chord = composition.chord(degree: covering.degree)
        let what = "\(chord.romanNumeral), \(chord.longName), \(covering.value.displayName.lowercased())"
        return covering.start == beat ? "\(place): \(what)" : "\(place): \(what) still ringing"
    }
}

#Preview {
    NavigationStack {
        CompositionListView()
    }
}
