//
//  CompositionView.swift
//  Guitar Man
//
//  Compose: write a chord progression by dragging Roman numerals onto a staff (or tap a
//  numeral, then tap where it goes), and optionally a melody over it. Pick the key, 4/4 or 3/4,
//  2–16 measures, and the length of each chord or note as you place it; rests fill the gaps.
//
//  The palette stays one row of buttons however much it offers: tapping a numeral shows its
//  versions (its 7th, sus chords, in minor the major V) as chips under the row; swiping the
//  row goes to borrowed and secondary chords (♭VII, iv, V/V…); and the Chords | Melody switch
//  swaps the numerals for the key's notes. Long-press a chord or note on the staff to change
//  its length or inversion, see where to play it, or duplicate or clear its measure; Undo,
//  Redo and the How to Compose guide (ComposeGuideView) are in the ⋯ menu. With a melody, the staff reads like a lead sheet: the melody's
//  notes, with the chords named above and numbered below.
//
//  You play it, optionally with Play Along listening and marking each chord (or note) green.
//  (Hidden Playback settings add a speaker button that plays it — see CompositionPlayer.)
//  Compositions save automatically once they have something in them.
//

import SwiftUI

// MARK: - CompositionListView

struct CompositionListView: View {

    /// The editor, for a new composition, a saved one (by id), or one from a template; and the
    /// templates. Pushed through the enclosing stack's path, like everything else on Home's stack.
    private enum Route: Hashable {
        case new
        case saved(UUID)
        case templates
        case template(String)
    }

    @State private var store = CompositionStore()

    var body: some View {
        List {
            Section {
                NavigationLink(value: Route.new) {
                    Label("New Composition", systemImage: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                NavigationLink(value: Route.templates) {
                    Label("Start From a Progression", systemImage: "music.note.list")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
            } footer: {
                Text("Drag Roman numerals onto the staff to build a progression, add a melody if you like, then play it yourself.")
            }

            if !store.compositions.isEmpty {
                Section("Saved") {
                    ForEach(store.compositions) { composition in
                        NavigationLink(value: Route.saved(composition.id)) {
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
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .new:
                CompositionEditorView(composition: Composition(), store: store)
            case .saved(let id):
                if let composition = store.compositions.first(where: { $0.id == id }) {
                    CompositionEditorView(composition: composition, store: store)
                }
            case .templates:
                templateList
            case .template(let id):
                if let template = CompositionTemplate.all.first(where: { $0.id == id }) {
                    CompositionEditorView(composition: template.makeComposition(), store: store)
                }
            }
        }
    }

    private var templateList: some View {
        List {
            Section {
                ForEach(CompositionTemplate.all) { template in
                    NavigationLink(value: Route.template(template.id)) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(template.name)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            Text(template.numerals)
                                .font(.system(size: 14, weight: .semibold, design: .serif))
                                .lineLimit(1)
                            Text(template.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } footer: {
                Text("They start in C major or A minor. Change the key and the whole progression moves with it.")
            }
        }
        .navigationTitle("Start From a Progression")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summary(of composition: Composition) -> String {
        let numerals = composition.chords.map { composition.chord($0.symbol).romanNumeral }
        var parts = ["\(composition.keyName)", composition.meterName, "\(composition.measureCount) bars"]
        if composition.hasMelody { parts.append("melody") }
        return parts.joined(separator: " · ") + (numerals.isEmpty ? "" : " · " + numerals.joined(separator: " "))
    }
}

// MARK: - CompositionEditorView

struct CompositionEditorView: View {

    private enum Mode: String, CaseIterable {
        case chords = "Chords"
        case melody = "Melody"
    }

    /// A button in the chord palette: page 0 is the key's own chords, page 1 the borrowed ones.
    private struct PaletteSlot: Hashable {
        let page: Int
        let index: Int
    }

    let store: CompositionStore
    @State private var composition: Composition
    @State private var mode: Mode = .chords

    // Chord palette.
    @State private var palettePage = 0
    @State private var selectedSlot: PaletteSlot? = nil
    /// The version each button is set to (its 7th, sus4…), once one's been picked.
    @State private var chosenVariants: [PaletteSlot: ChordSymbol] = [:]
    /// Length of the next chord placed.
    @AppStorage("compose.noteValue") private var noteValue: NoteValue = .whole

    // Melody palette.
    @State private var selectedNote: Int? = nil
    /// −1, 0, 1: the octave the note buttons are in, low, middle (on the staff) or high.
    @AppStorage("compose.melodyRegister") private var register = 0
    /// −1, 0, 1: flat, as in the key, or sharp, for the next note placed.
    @State private var alteration = 0
    @AppStorage("compose.melodyValue") private var melodyValue: NoteValue = .quarter

    /// "Shortened to fit" after a placement, briefly.
    @State private var hint: String? = nil
    @State private var hintTask: Task<Void, Never>? = nil
    @State private var targetedSlot: Int? = nil
    @State private var showRename = false
    @State private var nameDraft = ""
    @State private var showPlayAlong = false
    @State private var showGuide = false

    // Undo and redo: every change to the composition, whatever made it.
    @State private var history: [Composition] = []
    @State private var future: [Composition] = []
    @State private var isRestoring = false

    /// Hidden Playback settings (tap "Key" five times quickly): a speaker button that plays the
    /// composition, its chords all at once or arpeggiated.
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
                    editingMelody: mode == .melody,
                    chordColors: player.playingChord.map { [$0: Color.accentColor] } ?? [:],
                    noteColors: player.playingNote.map { [$0: Color.accentColor] } ?? [:],
                    targetedSlot: targetedSlot,
                    editing: editing
                )
                .padding(.horizontal, 12)

                palette

                Text(mode == .chords
                     ? "Drag a numeral onto a beat, or tap it and then tap the beat. Tap a numeral for its 7th and other versions; swipe the numerals for borrowed chords. Long-press a chord on the staff to change it, see where to play it, or copy its measure."
                     : "Pick a note, then tap where it goes: each beat splits in two for eighth notes. Long-press a note on the staff to change its length or remove it.")
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
        .safeAreaInset(edge: .bottom) { bottomBar }
        // Playback is of what's on screen as it's set up now: any change stops it.
        .onDisappear { player.stop() }
        .onChange(of: playbackStyle) { player.stop() }
        .onChange(of: playbackTempo) { player.stop() }
        .onChange(of: hearPlayback) { player.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.stop() }
        }
        // The borrowed chords differ between major and minor keys.
        .onChange(of: composition.isMinor) {
            chosenVariants = [:]
            selectedSlot = nil
        }
        .navigationTitle(composition.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
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
        .sheet(isPresented: $showGuide) {
            ComposeGuideView()
        }
        // Save as you go, once there's something to keep (and keep saving a saved one, so
        // clearing it sticks). Every change can be undone.
        .onChange(of: composition) { old, updated in
            player.stop()
            if isRestoring {
                isRestoring = false
            } else {
                history.append(old)
                if history.count > 100 { history.removeFirst() }
                future.removeAll()
            }
            if !updated.isEmpty || store.compositions.contains(where: { $0.id == updated.id }) {
                store.save(updated)
            }
        }
    }

    // MARK: - Bottom bar and menu

    private var bottomBar: some View {
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
                .accessibilityLabel(player.isPlaying ? "Stop" : "Hear the composition")
            }
            Button {
                player.stop()
                // A composition started from a template is kept once you play it, even unedited.
                if !composition.isEmpty { store.save(composition) }
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

    private var moreMenu: some View {
        Menu {
            Button {
                showGuide = true
            } label: {
                Label("How to Compose", systemImage: "book")
            }
            Section {
                Button {
                    undo()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(history.isEmpty)
                Button {
                    redo()
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(future.isEmpty)
            }
            Button {
                nameDraft = composition.name
                showRename = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Section {
                Button(role: .destructive) {
                    composition.clearChords()
                } label: {
                    Label("Clear All Chords", systemImage: "trash")
                }
                .disabled(composition.chords.isEmpty)
                if composition.hasMelody {
                    Button(role: .destructive) {
                        composition.clearMelody()
                    } label: {
                        Label("Clear Melody", systemImage: "trash")
                    }
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    private func undo() {
        guard let previous = history.popLast() else { return }
        future.append(composition)
        isRestoring = true
        composition = previous
    }

    private func redo() {
        guard let next = future.popLast() else { return }
        history.append(composition)
        isRestoring = true
        composition = next
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
            Picker("Write", selection: $mode.animation(.easeInOut(duration: 0.2))) {
                ForEach(Mode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)
            .padding(.horizontal, 16)
            .padding(.bottom, 2)

            switch mode {
            case .chords: chordPalette
            case .melody: melodyPalette
            }
        }
    }

    // MARK: Chords

    private var borrowed: [(chord: ChordSymbol, seventh: ChordSymbol)] {
        CompositionChord.borrowed(isMinor: composition.isMinor)
    }

    private func slots(onPage page: Int) -> [PaletteSlot] {
        (0..<(page == 0 ? 7 : borrowed.count)).map { PaletteSlot(page: page, index: $0) }
    }

    private func variants(of slot: PaletteSlot) -> [ChordSymbol] {
        if slot.page == 0 {
            return CompositionChord.variants(degree: slot.index + 1, keySignature: composition.keySignature,
                                             isMinor: composition.isMinor)
        }
        guard borrowed.indices.contains(slot.index) else { return [] }
        return [borrowed[slot.index].chord, borrowed[slot.index].seventh]
    }

    /// What the button places: the version picked for it, else its plain chord.
    private func symbol(for slot: PaletteSlot) -> ChordSymbol {
        let options = variants(of: slot)
        if let chosen = chosenVariants[slot], options.contains(chosen) { return chosen }
        return options.first ?? ChordSymbol(degree: 1)
    }

    private var selectedSymbol: ChordSymbol? { selectedSlot.map(symbol(for:)) }

    private var chordPalette: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Group {
                    if let symbol = selectedSymbol {
                        let chord = composition.chord(symbol)
                        Text("\(chord.romanNumeral) in \(composition.keyName) is \(chord.longName)")
                    } else {
                        Text(palettePage == 0 ? "Chords in \(composition.keyName)" : "Borrowed & secondary chords")
                    }
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                pageDots
            }
            .padding(.horizontal, 20)

            TabView(selection: $palettePage) {
                ForEach(0..<2, id: \.self) { page in
                    HStack(spacing: 6) {
                        ForEach(slots(onPage: page), id: \.self) { slot in
                            chordButton(slot)
                        }
                    }
                    .padding(.horizontal, 16)
                    .tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 58)

            if let slot = selectedSlot, variants(of: slot).count > 1 {
                variantChips(slot)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

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
        .animation(.easeInOut(duration: 0.2), value: selectedSlot)
        // A whole note doesn't fit in 3/4.
        .onChange(of: composition.beatsPerMeasure, initial: true) { _, beats in
            if noteValue.beats > beats { noteValue = NoteValue(beats: beats) ?? .quarter }
        }
    }

    /// Two dots: which page of chords is showing (tap one to go there).
    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { page in
                Circle()
                    .fill(page == palettePage ? Color.primary : Color(.systemGray4))
                    .frame(width: 7, height: 7)
                    .contentShape(Rectangle().inset(by: -6))
                    .onTapGesture { withAnimation { palettePage = page } }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(palettePage == 0 ? "Chords in the key" : "Borrowed and secondary chords")
        .accessibilityHint("Swipe the chords to switch")
        .accessibilityAdjustableAction { direction in
            withAnimation { palettePage = direction == .increment ? 1 : 0 }
        }
    }

    private func chordButton(_ slot: PaletteSlot) -> some View {
        let symbol = symbol(for: slot)
        let chord = composition.chord(symbol)
        let isSelected = selectedSlot == slot
        return VStack(spacing: 2) {
            Text(chord.romanNumeral)
                .font(.system(size: 17, weight: .bold, design: .serif))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(chord.name)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
        .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        // A dot when the button has other versions to pick from.
        .overlay(alignment: .topTrailing) {
            if variants(of: slot).count > 1 && !isSelected {
                Circle()
                    .fill(Color(.systemGray3))
                    .frame(width: 4, height: 4)
                    .padding(5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            selectedSlot = isSelected ? nil : slot
        }
        .draggable(symbol.dragText) {
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

    /// The selected button's versions: its plain chord, 7th, sus chords…
    private func variantChips(_ slot: PaletteSlot) -> some View {
        let current = symbol(for: slot)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(variants(of: slot), id: \.self) { variant in
                    let chord = composition.chord(variant)
                    let isCurrent = variant == current
                    Button {
                        chosenVariants[slot] = variant
                    } label: {
                        HStack(spacing: 5) {
                            Text(chord.romanNumeral)
                                .font(.system(size: 14, weight: .bold, design: .serif))
                            Text(chord.name)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(isCurrent ? .white.opacity(0.85) : .secondary)
                        }
                        .foregroundStyle(isCurrent ? .white : .primary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(isCurrent ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chord.longName)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: Melody

    /// The note button `degree` (1–7) places: the key's note in the chosen octave, sharpened or
    /// flattened if that's picked.
    private func melodyPitch(_ degree: Int) -> SpelledPitch {
        let note = composition.scalePitches(octave: 3 + register)[degree - 1]
        return SpelledPitch(letter: note.letter, accidental: max(-2, min(2, note.accidental + alteration)), octave: note.octave)
    }

    private var registerName: String { ["Low", "Middle", "High"][register + 1] }

    private static let ordinals = ["1st", "2nd", "3rd", "4th", "5th", "6th", "7th"]

    private var melodyPalette: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Group {
                    if let degree = selectedNote {
                        let pitch = melodyPitch(degree)
                        Text(alteration == 0
                             ? "\(pitch.name), the \(Self.ordinals[degree - 1]) note of \(composition.keyName)"
                             : "\(pitch.name), the \(Self.ordinals[degree - 1]) note \(alteration > 0 ? "raised" : "lowered")")
                    } else {
                        Text("Notes in \(composition.keyName)")
                    }
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    Button {
                        register = max(-1, register - 1)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(register <= -1)
                    .accessibilityLabel("Lower octave")
                    Text(registerName)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 46)
                    Button {
                        register = min(1, register + 1)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(register >= 1)
                    .accessibilityLabel("Higher octave")
                }
                .font(.system(size: 13, weight: .semibold))
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 20)

            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { degree in
                    noteButton(degree)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 58)

            HStack {
                Picker("Accidental", selection: $alteration) {
                    Text("♭ Flat").tag(-1)
                    Text("In Key").tag(0)
                    Text("♯ Sharp").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .accessibilityHint("Flattens or sharpens the next note you place")
                Spacer(minLength: 8)
                Menu {
                    Picker("Length", selection: $melodyValue) {
                        ForEach(composition.melodyValues) { value in
                            Text(value.displayName).tag(value)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(melodyValue.displayName)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                }
                .accessibilityLabel("Note length, \(melodyValue.displayName)")
            }
            .padding(.horizontal, 16)
            .padding(.top, 2)
        }
        .onChange(of: composition.beatsPerMeasure, initial: true) { _, beats in
            if melodyValue.eighths > beats * 2 { melodyValue = .dottedHalf }
        }
    }

    private func noteButton(_ degree: Int) -> some View {
        let pitch = melodyPitch(degree)
        let isSelected = selectedNote == degree
        return VStack(spacing: 2) {
            Text(pitch.name)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(degree)")
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
            selectedNote = isSelected ? nil : degree
        }
        .draggable(Self.dragText(for: pitch)) {
            Text(pitch.name)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(Capsule())
        }
        .accessibilityLabel("\(pitch.name), scale note \(degree)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private static func dragText(for pitch: SpelledPitch) -> String {
        "note:" + ((try? JSONEncoder().encode(pitch)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}")
    }

    private static func pitch(fromDragText text: String) -> SpelledPitch? {
        guard text.hasPrefix("note:") else { return nil }
        return try? JSONDecoder().decode(SpelledPitch.self, from: Data(text.dropFirst(5).utf8))
    }

    // MARK: - Editing

    /// What the staff can do. Its slots are beats while writing chords, eighths while writing the melody.
    private var editing: CompositionStaffView.Editing {
        CompositionStaffView.Editing(
            onTap: { slot in
                switch mode {
                case .chords: placeChord(selectedSymbol, at: slot)
                case .melody: placeNote(selectedNote.map(melodyPitch), at: slot)
                }
            },
            onDrop: { slot, text in drop(text, at: slot) },
            onRemove: { slot in
                switch mode {
                case .chords: composition.removeChord(covering: slot)
                case .melody: composition.removeNote(covering: slot)
                }
            },
            onSetLength: { start, value in
                switch mode {
                case .chords: composition.setLength(ofChordAt: start, to: value)
                case .melody: composition.setLength(ofNoteAt: start, to: value)
                }
            },
            onSetSymbol: { start, symbol in composition.setSymbol(ofChordAt: start, to: symbol) },
            onDuplicateMeasure: { composition.duplicateMeasure($0) },
            onClearMeasure: { composition.clearMeasure($0) },
            onTargetChange: { targetedSlot = $0 }
        )
    }

    /// A chord or a note dropped on `slot`; either can go on either staff (a chord dropped on an
    /// eighth goes on its beat).
    private func drop(_ text: String, at slot: Int) -> Bool {
        if let symbol = ChordSymbol(dragText: text) {
            placeChord(symbol, at: mode == .melody ? slot / 2 : slot)
            return true
        }
        if let pitch = Self.pitch(fromDragText: text) {
            placeNote(pitch, at: mode == .melody ? slot : slot * 2)
            return true
        }
        return false
    }

    private func placeChord(_ symbol: ChordSymbol?, at beat: Int) {
        guard let symbol, let beats = composition.place(symbol, at: beat, value: noteValue) else { return }
        guard beats < noteValue.beats, let fitted = NoteValue(beats: beats) else { return }
        showHint("Shortened to a \(fitted.displayName.lowercased()) note to fit.")
    }

    private func placeNote(_ pitch: SpelledPitch?, at tick: Int) {
        guard let pitch, let fitted = composition.placeNote(pitch, at: tick, value: melodyValue) else { return }
        if fitted != melodyValue { showHint("Shortened to \(fitted == .eighth ? "an" : "a") \(fitted.displayName.lowercased()) note to fit.") }
    }

    private func showHint(_ text: String) {
        hintTask?.cancel()
        hint = text
        hintTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            if !Task.isCancelled { hint = nil }
        }
    }
}

// MARK: - CompositionStaffView

/// The composition on a staff. With chords only, two measures per line, each measure split
/// into its beats: a chord is written on the beat it starts on, as its note value, and gaps are
/// rests. With a melody (or while writing one), one measure per line split into eighths, read
/// like a lead sheet: the melody's notes and rests, each chord named above the staff and
/// numbered below where it starts. Accidentals last to the barline, as in print.
///
/// With `editing`, every beat (or eighth) takes taps and drops, an empty measure shows a + on
/// each beat to invite something, and a long-press menu changes what's there or its measure.
/// Without it, it's read-only (Play Along), and `chordColors` (by start beat) and `noteColors`
/// (by start eighth) tint chords and notes.
struct CompositionStaffView: View {

    struct Editing {
        /// Slot (a beat, or an eighth when editing the melody) tapped.
        var onTap: (Int) -> Void
        /// Drag text dropped on a slot; returns whether it was taken.
        var onDrop: (_ slot: Int, _ text: String) -> Bool
        var onRemove: (Int) -> Void
        var onSetLength: (_ start: Int, _ value: NoteValue) -> Void
        var onSetSymbol: (_ start: Int, _ symbol: ChordSymbol) -> Void
        var onDuplicateMeasure: (Int) -> Void
        var onClearMeasure: (Int) -> Void
        var onTargetChange: (Int?) -> Void
    }

    let composition: Composition
    /// The slots are eighths and edits go to the melody.
    var editingMelody = false
    var chordColors: [Int: Color] = [:]
    var noteColors: [Int: Color] = [:]
    var targetedSlot: Int? = nil
    var editing: Editing? = nil

    private let lineSpacing: CGFloat = 9

    private var isEditable: Bool { editing != nil }
    /// Lead-sheet layout: the melody on the staff, chords as text.
    private var showsMelody: Bool { composition.hasMelody || editingMelody }
    private var measuresPerLine: Int { showsMelody ? 1 : 2 }
    /// Slots per measure the cells are cut into.
    private var slotsPerMeasure: Int { editingMelody ? composition.eighthsPerMeasure : composition.beatsPerMeasure }

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
        let first = measure * slotsPerMeasure
        let emptyMeasure = composition.isMeasureEmpty(measure)
        return StaffView(keySignature: composition.keySignature,
                         columns: showsMelody ? melodyColumns(inMeasure: measure) : chordColumns(inMeasure: measure),
                         showsClef: false, showsKeySignature: false, showsEndBarline: true,
                         edgeToEdge: true, lineSpacing: lineSpacing)
            .frame(maxWidth: .infinity)
            .overlay {
                if isEditable {
                    HStack(spacing: 0) {
                        ForEach(first..<first + slotsPerMeasure, id: \.self) { slot in
                            slotCell(slot, measure: measure, emptyMeasure: emptyMeasure)
                        }
                    }
                }
            }
            .accessibilityElement(children: isEditable ? .contain : .combine)
    }

    /// Chords only: one column per beat.
    private func chordColumns(inMeasure measure: Int) -> [StaffColumn] {
        let beats = composition.beatsPerMeasure
        let first = measure * beats
        let rests = composition.rests(inMeasure: measure)
        if rests.first?.glyph == .whole {
            // Empty: + signs in the editor (drawn by the cells), else one whole rest, centered.
            return isEditable ? [] : [StaffColumn(id: first, pitches: [], rest: .whole)]
        }
        var accidentals = MeasureAccidentals(keySignature: composition.keySignature)
        return (first..<first + beats).map { beat in
            if let placed = composition.chords.first(where: { $0.start == beat }) {
                let chord = composition.chord(placed.symbol)
                return StaffColumn(id: beat, pitches: chord.pitches, value: placed.value,
                                   above: chord.name, below: chord.romanNumeral, color: chordColors[beat],
                                   accidentals: accidentals.printed(for: chord.pitches))
            }
            if let rest = rests.first(where: { $0.start == beat }) {
                return StaffColumn(id: beat, pitches: [], color: Color(.secondaryLabel), rest: rest.glyph)
            }
            return StaffColumn(id: beat, pitches: [])
        }
    }

    /// Lead sheet: one column per eighth, the melody's notes and rests, the chords as text.
    private func melodyColumns(inMeasure measure: Int) -> [StaffColumn] {
        let eighths = composition.eighthsPerMeasure
        let first = measure * eighths
        let rests = composition.melodyRests(inMeasure: measure)
        let noMelody = rests.first?.glyph == .whole
        var accidentals = MeasureAccidentals(keySignature: composition.keySignature)
        return (first..<first + eighths).map { tick in
            var column = StaffColumn(id: tick, pitches: [])
            if tick % 2 == 0, let placed = composition.chords.first(where: { $0.start == tick / 2 }) {
                let chord = composition.chord(placed.symbol)
                column.above = chord.name
                column.below = chord.romanNumeral
                column.aboveColor = chordColors[placed.start]
            }
            if let note = composition.melody.first(where: { $0.start == tick }) {
                column.pitches = [note.pitch]
                column.value = note.value
                column.color = noteColors[tick]
                column.accidentals = accidentals.printed(for: [note.pitch])
            } else if noMelody {
                // A measure with no melody: + signs while writing one, else a whole rest on beat 1.
                if !isEditable && tick == first {
                    column.rest = .whole
                    column.color = Color(.secondaryLabel)
                }
            } else if let rest = rests.first(where: { $0.start == tick }) {
                column.rest = rest.glyph
                column.color = Color(.secondaryLabel)
            }
            return column
        }
    }

    // MARK: Slot (editor)

    private func slotCell(_ slot: Int, measure: Int, emptyMeasure: Bool) -> some View {
        let chord = editingMelody ? nil : composition.chord(covering: slot)
        let note = editingMelody ? composition.note(covering: slot) : nil
        let onBeat = !editingMelody || slot % 2 == 0
        let cell = Rectangle()
            .fill(targetedSlot == slot ? Color.accentColor.opacity(0.18) : Color.clear)
            .overlay {
                if emptyMeasure && onBeat {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                } else if emptyMeasure && editingMelody {
                    Circle().fill(Color(.tertiaryLabel)).frame(width: 3, height: 3)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { editing?.onTap(slot) }
            .dropDestination(for: String.self) { items, _ in
                guard let editing, let text = items.first else { return false }
                return editing.onDrop(slot, text)
            } isTargeted: { targeted in
                if targeted {
                    editing?.onTargetChange(slot)
                } else if targetedSlot == slot {
                    editing?.onTargetChange(nil)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(slot: slot, chord: chord, note: note))
            .accessibilityHint(editingMelody ? "Tap to place the selected note here" : "Tap to place the selected chord here")

        return Group {
            if chord != nil || note != nil {
                cell.contextMenu {
                    menuItems(chord: chord, note: note, measure: measure)
                } preview: {
                    if let chord { chordPreview(chord) } else if let note { notePreview(note) }
                }
            } else {
                cell.contextMenu {
                    menuItems(chord: nil, note: nil, measure: measure)
                }
            }
        }
    }

    @ViewBuilder
    private func menuItems(chord placed: Composition.PlacedChord?, note: Composition.MelodyNote?, measure: Int) -> some View {
        if let placed {
            let chord = composition.chord(placed.symbol)
            let room = composition.room(at: placed.start)
            Section("Length") {
                ForEach(composition.noteValues.filter { $0.beats <= room }) { value in
                    checkButton(value.displayName, checked: value == placed.value) {
                        editing?.onSetLength(placed.start, value)
                    }
                }
            }
            if chord.maxInversion > 0 {
                Section("Inversion") {
                    ForEach(0...chord.maxInversion, id: \.self) { inversion in
                        let title = ["Root Position", "1st Inversion", "2nd Inversion", "3rd Inversion"][inversion]
                        let symbol = placed.symbol.inverted(inversion)
                        let bass = composition.chord(symbol).bass.name
                        checkButton(inversion == 0 ? title : "\(title) (\(bass) in the bass)",
                                    checked: placed.symbol.inversion == inversion) {
                            editing?.onSetSymbol(placed.start, symbol)
                        }
                    }
                }
            }
            Button(role: .destructive) {
                editing?.onRemove(placed.start)
            } label: {
                Label("Remove Chord", systemImage: "trash")
            }
        }
        if let note {
            let room = composition.noteRoom(at: note.start)
            Section("Length") {
                ForEach(composition.melodyValues.filter { $0.eighths <= room }) { value in
                    checkButton(value.displayName, checked: value == note.value) {
                        editing?.onSetLength(note.start, value)
                    }
                }
            }
            Button(role: .destructive) {
                editing?.onRemove(note.start)
            } label: {
                Label("Remove Note", systemImage: "trash")
            }
        }
        Section("Measure \(measure + 1)") {
            if composition.canDuplicateMeasure(measure) {
                Button {
                    editing?.onDuplicateMeasure(measure)
                } label: {
                    Label(measure + 1 < composition.measureCount ? "Copy to Next Measure" : "Copy to a New Measure",
                          systemImage: "plus.square.on.square")
                }
            }
            if !composition.isMeasureEmpty(measure) {
                Button(role: .destructive) {
                    editing?.onClearMeasure(measure)
                } label: {
                    Label("Clear Measure", systemImage: "eraser")
                }
            }
        }
    }

    private func checkButton(_ title: String, checked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if checked {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    /// The chord on its own staff, and where to play it.
    private func chordPreview(_ placed: Composition.PlacedChord) -> some View {
        let chord = composition.chord(placed.symbol)
        return VStack(spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                StaffView(keySignature: composition.keySignature,
                          columns: [StaffColumn(id: 0, pitches: chord.pitches, value: placed.value,
                                                above: chord.name, below: chord.romanNumeral)],
                          showsClef: true, lineSpacing: lineSpacing)
                    .frame(width: 130, height: 120)
                ChordShapesView(chord: chord, isInteractive: false, width: 84)
            }
            Text("\(chord.longName) · \(placed.value.displayName.lowercased())")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func notePreview(_ note: Composition.MelodyNote) -> some View {
        VStack(spacing: 2) {
            StaffView(keySignature: composition.keySignature,
                      columns: [StaffColumn(id: 0, pitches: [note.pitch], value: note.value, below: note.pitch.name)],
                      showsClef: true, lineSpacing: lineSpacing)
                .frame(width: 110, height: 120)
            Text("\(note.pitch.name) · \(note.value.displayName.lowercased())")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 12)
    }

    private func accessibilityLabel(slot: Int, chord: Composition.PlacedChord?, note: Composition.MelodyNote?) -> String {
        let beats = composition.beatsPerMeasure
        let place: String
        if editingMelody {
            let beat = slot / 2
            place = "Measure \(beat / beats + 1), beat \(beat % beats + 1)\(slot % 2 == 1 ? " and" : "")"
        } else {
            place = "Measure \(slot / beats + 1), beat \(slot % beats + 1)"
        }
        if let chord {
            let spelled = composition.chord(chord.symbol)
            let what = "\(spelled.romanNumeral), \(spelled.longName), \(chord.value.displayName.lowercased())"
            return chord.start == slot ? "\(place): \(what)" : "\(place): \(what) still ringing"
        }
        if let note {
            let what = "\(note.pitch.name), \(note.value.displayName.lowercased())"
            return note.start == slot ? "\(place): \(what)" : "\(place): \(what) still ringing"
        }
        return "\(place): rest"
    }
}

#Preview {
    NavigationStack {
        CompositionListView()
    }
}
