//
//  CompositionView.swift
//  Guitar Man
//
//  Compose: write a chord progression in Roman numerals on a staff, and optionally a melody
//  over it. Pick the key, 4/4 or 3/4, 2–16 measures, and the length of each chord or note as
//  you write it; rests fill the gaps.
//
//  Writing is like typing: tapping a numeral (or a note) puts it at the cursor on the staff and
//  moves the cursor past it, adding a measure at the end if need be. Tapping a beat moves the
//  cursor there, and an empty beat also pops up the key's chords to pick from on the spot.
//  Numerals can be dragged onto a beat too.
//
//  The palette is pinned above Play Along and stays one row of buttons however much it offers:
//  after a numeral is tapped its versions (its 7th, sus chords, in minor the major V) show as
//  chips under the row, and picking one changes the chord just written; swiping the row goes to
//  borrowed and secondary chords (♭VII, iv, V/V…); and the Chords | Melody switch swaps the
//  numerals for the key's notes. Long-press a chord or note on the staff to change
//  its length or inversion, see where to play it, or duplicate or clear its measure; Undo,
//  Redo, the How to Compose guide (ComposeGuideView) and Compose Settings are in the ⋯ menu. With a melody, the staff reads like a lead sheet: the melody's
//  notes, with the chords named above and numbered below.
//
//  You play it, optionally with Play Along listening and marking each chord (or note) green.
//  Hear Compositions, in Compose Settings, adds a speaker button that plays it (see
//  CompositionPlayer), lighting each measure as it's reached with a playhead sweeping through. A tour (ComposeWalkthrough) lights up each part the first time a
//  composition is opened each launch, until it's turned off.
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
    /// The saved composition being renamed, and the name typed so far.
    @State private var renaming: Composition? = nil
    @State private var nameDraft = ""
    @State private var deleting: Composition? = nil

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
                Section {
                    ForEach(store.compositions) { composition in
                        NavigationLink(value: Route.saved(composition.id)) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(composition.name)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(edited(composition.updatedAt))
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Text(summary(of: composition))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                deleting = composition
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                startRenaming(composition)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.indigo)
                        }
                        .contextMenu {
                            Button {
                                startRenaming(composition)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleting = composition
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Saved")
                } footer: {
                    Text("Swipe left on one to rename or delete it.")
                }
            }
        }
        .navigationTitle("Compose")
        .alert("Rename Composition", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $nameDraft)
            Button("Save") {
                if let renaming { store.rename(renaming.id, to: nameDraft) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(deleting.map { "Delete \u{201C}\($0.name)\u{201D}?" } ?? "",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let deleting { store.delete(deleting.id) }
            }
        } message: {
            Text("It can't be brought back.")
        }
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .new:
                CompositionEditorView(composition: newComposition(), store: store)
            case .saved(let id):
                if let composition = store.compositions.first(where: { $0.id == id }) {
                    CompositionEditorView(composition: composition, store: store)
                }
            case .templates:
                templateList
            case .template(let id):
                if let template = CompositionTemplate.all.first(where: { $0.id == id }) {
                    CompositionEditorView(composition: newComposition(from: template), store: store)
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

    /// A blank composition (or one from `template`) with a name no saved one has.
    private func newComposition(from template: CompositionTemplate? = nil) -> Composition {
        var composition = template?.makeComposition() ?? Composition()
        composition.name = store.unusedName(template?.name ?? "Untitled")
        return composition
    }

    private func startRenaming(_ composition: Composition) {
        nameDraft = composition.name
        renaming = composition
    }

    /// "Today, 3:41 PM", "Yesterday", or a date, for when it was last changed.
    private func edited(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let sameYear = calendar.isDate(date, equalTo: .now, toGranularity: .year)
        return date.formatted(sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
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
    /// The button tapped last: its versions show as chips.
    @State private var selectedSlot: PaletteSlot? = nil
    /// Where that button's chord was written, so a chip can change it.
    @State private var lastWritten: Int? = nil
    /// The beat the next chord goes on (`totalBeats` past the end: the next adds a measure).
    @State private var chordCursor: Int
    /// The beat whose pop-up chord menu is open.
    @State private var chordMenuBeat: Int? = nil
    /// The version each button is set to (its 7th, sus4…), once one's been picked.
    @State private var chosenVariants: [PaletteSlot: ChordSymbol] = [:]
    /// Length of the next chord placed.
    @AppStorage("compose.noteValue") private var noteValue: NoteValue = .whole

    // Melody palette.
    @State private var selectedNote: Int? = nil
    /// The eighth the next note goes on, like `chordCursor`.
    @State private var noteCursor: Int
    /// −1, 0, 1: the octave the note buttons are in, low, middle (on the staff) or high.
    @AppStorage("compose.melodyRegister") private var register = 0
    /// −1, 0, 1: flat, as in the key, or sharp, for the next note placed.
    @State private var alteration = 0
    @AppStorage("compose.melodyValue") private var melodyValue: NoteValue = .quarter

    /// "Shortened to fit" after a placement (or what to do first), briefly.
    @State private var hint: String? = nil
    @State private var hintSymbol = "arrow.left.and.right.square"
    @State private var hintTask: Task<Void, Never>? = nil
    @State private var targetedSlot: Int? = nil
    @State private var showRename = false
    @State private var nameDraft = ""
    @State private var showPlayAlong = false
    @State private var showGuide = false
    /// Key, time and measures open (they start open on an empty composition, where they're
    /// set first, and folded to one line on one that's been written, to give the staff room).
    @State private var settingsExpanded: Bool

    // Undo and redo: every change to the composition, whatever made it.
    @State private var history: [Composition] = []
    @State private var future: [Composition] = []
    @State private var isRestoring = false

    /// Hear Compositions (in Compose Settings): a speaker button that plays the composition,
    /// its chords all at once or arpeggiated.
    @AppStorage(CompositionPlayer.enabledKey) private var hearPlayback = false
    @AppStorage(CompositionPlayer.styleKey) private var playbackStyle: CompositionPlaybackStyle = .together
    @AppStorage(CompositionPlayer.tempoKey) private var playbackTempo = CompositionPlayer.defaultTempo
    @Environment(\.scenePhase) private var scenePhase
    @State private var player = CompositionPlayer()
    @State private var showSettings = false
    /// The tour's step while it's showing (see ComposeTour).
    @State private var tourStep: Int? = nil
    @AppStorage(ComposeTour.enabledKey) private var tourEnabled = true

    init(composition: Composition, store: CompositionStore) {
        self.store = store
        _composition = State(initialValue: composition)
        _settingsExpanded = State(initialValue: composition.isEmpty)
        _chordCursor = State(initialValue: composition.chords.last?.end ?? 0)
        _noteCursor = State(initialValue: composition.melody.last?.end ?? 0)
    }

    private var showsMelody: Bool { composition.hasMelody || mode == .melody }

    var body: some View {
        ScrollView {
            ScrollViewReader { scroller in
                VStack(alignment: .leading, spacing: 16) {
                    settingsCard
                        .composeTourTarget(.settings)
                        .id(ComposeTourTarget.settings)

                    CompositionStaffView(
                        composition: composition,
                        editingMelody: mode == .melody,
                        chordColors: player.playingChord.map { [$0: Color.accentColor] } ?? [:],
                        noteColors: player.playingNote.map { [$0: Color.accentColor] } ?? [:],
                        targetedSlot: targetedSlot,
                        cursorSlot: player.isPlaying || tourStep != nil ? nil : (mode == .chords ? chordCursor : noteCursor),
                        playingMeasure: player.playingMeasure,
                        playhead: player.clock,
                        editing: editing
                    )
                    .padding(.horizontal, 12)
                    .composeTourTarget(.staff)
                    .id(ComposeTourTarget.staff)

                    Text(instructions)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                        .animation(nil, value: instructions)
                }
                .padding(.vertical, 12)
                // The tour scrolls each part it lights up into view (the palette and Play Along
                // are pinned below, always in view).
                .onChange(of: tourStep) { _, step in
                    let steps = ComposeTour.steps(hearPlayback: hearPlayback)
                    guard let step, steps.indices.contains(step), let target = steps[step].target,
                          [.settings, .staff].contains(target) else { return }
                    withAnimation(.easeInOut(duration: 0.3)) { scroller.scrollTo(target, anchor: .center) }
                }
                // Keep the line being written, or played, in view.
                .onChange(of: mode == .chords ? chordCursor : noteCursor) {
                    scrollToMeasure(cursorMeasure, scroller)
                }
                .onChange(of: player.playingMeasure) { _, measure in
                    if let measure { scrollToMeasure(measure, scroller) }
                }
            }
        }
        // "Shortened to fit", floating just above the buttons so it's seen wherever you've scrolled.
        .overlay(alignment: .bottom) {
            if let hint {
                Label(hint, systemImage: hintSymbol)
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
        // The palette, pinned over Play Along like a keyboard, so it stays under your thumb
        // while the staff scrolls to follow what you write.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                palette
                    .padding(.top, 10)
                    .disabled(tourStep != nil)
                bottomBar
            }
            .background(.bar)
        }
        .overlayPreferenceValue(ComposeTourAnchors.self) { anchors in
            ComposeWalkthroughOverlay(steps: ComposeTour.steps(hearPlayback: hearPlayback), step: $tourStep,
                                      anchors: anchors) { keepShowing in
                tourEnabled = keepShowing
                tourStep = nil
            }
        }
        .toolbar(tourStep == nil ? .automatic : .hidden, for: .navigationBar)
        .onAppear {
            // The tour opens with the first composition opened since the app launched.
            guard tourEnabled, !ComposeTour.shownThisLaunch else { return }
            ComposeTour.shownThisLaunch = true
            startTour(after: 0.5)
        }
        .sheet(isPresented: $showSettings) {
            ComposeSettingsView {
                showSettings = false
                startTour(after: 0.6)
            }
        }
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
            lastWritten = nil
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
            chordCursor = min(chordCursor, updated.totalBeats)
            noteCursor = min(noteCursor, updated.totalEighths)
            // The first chord written: the key and time are set, so give the staff the room.
            if old.isEmpty && !updated.isEmpty && settingsExpanded {
                withAnimation(.easeInOut(duration: 0.25)) { settingsExpanded = false }
            }
        }
    }

    /// The measure the cursor is in (the last, when it's past the end).
    private var cursorMeasure: Int {
        let measure = mode == .chords ? chordCursor / composition.beatsPerMeasure : noteCursor / composition.eighthsPerMeasure
        return min(measure, composition.measureCount - 1)
    }

    private func scrollToMeasure(_ measure: Int, _ scroller: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.25)) {
            scroller.scrollTo(CompositionStaffView.rowID(measure: measure, showsMelody: showsMelody))
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
        .composeTourTarget(.playAlong)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// What to do next, for what's picked now.
    private var instructions: String {
        switch mode {
        case .chords:
            if let slot = selectedSlot, lastWritten != nil, variants(of: slot).count > 1 {
                return "Tap a version under the chords to change the one you just wrote, or keep tapping chords. Long-press a chord on the staff to change its length or see where to play it."
            }
            return "Tap chords to write them one after another at the blue mark. Tap a beat to move the mark there; an empty beat shows the chords to pick from. Swipe the chords for more."
        case .melody:
            return "Tap notes to write them one after another at the blue mark: each beat splits in two for eighth notes. Tap the staff to move the mark; long-press a note to change or remove it."
        }
    }

    private func startTour(after delay: TimeInterval) {
        mode = .chords
        settingsExpanded = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation { tourStep = 0 }
        }
    }

    private var moreMenu: some View {
        Menu {
            Button {
                showGuide = true
            } label: {
                Label("How to Compose", systemImage: "book")
            }
            Button {
                showSettings = true
            } label: {
                Label("Compose Settings", systemImage: "gearshape")
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
        pullCursorsBack()
    }

    private func redo() {
        guard let next = future.popLast() else { return }
        history.append(composition)
        isRestoring = true
        composition = next
        pullCursorsBack()
    }

    /// After an undo, carry on writing where the writing now ends (not after what was undone).
    private func pullCursorsBack() {
        chordCursor = min(chordCursor, composition.chords.last?.end ?? 0)
        noteCursor = min(noteCursor, composition.melody.last?.end ?? 0)
        lastWritten = nil
    }

    // MARK: - Settings

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { settingsExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("\(composition.keyName) · \(composition.meterName) · \(composition.measureCount) measures")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    Text(settingsExpanded ? "Done" : "Change")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(settingsExpanded ? "Hides the key, time and measures" : "Shows the key, time and measures to change them")

            if settingsExpanded {
                Divider()
                settingsRows
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, settingsExpanded ? 16 : 12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var settingsRows: some View {
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
            .composeTourTarget(.mode)
            .id(ComposeTourTarget.mode)

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
            .composeTourTarget(.palette)
            .id(ComposeTourTarget.palette)

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
            .composeTourTarget(.length)
            .id(ComposeTourTarget.length)
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
        .onTapGesture { write(slot) }
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
        .accessibilityHint("Writes it at the cursor")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The selected button's versions: its plain chord, 7th, sus chords… Picking one changes the
    /// chord the button just wrote, and what it writes from then on.
    private func variantChips(_ slot: PaletteSlot) -> some View {
        let current = symbol(for: slot)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(variants(of: slot), id: \.self) { variant in
                    let chord = composition.chord(variant)
                    let isCurrent = variant == current
                    Button {
                        chosenVariants[slot] = variant
                        if let start = lastWritten { composition.setSymbol(ofChordAt: start, to: variant) }
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
            selectedNote = degree
            writeNote(pitch)
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
        .accessibilityHint("Writes it at the cursor")
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
            // A tap moves the cursor; on an empty beat it also offers the chords right there.
            onTap: { slot in
                switch mode {
                case .chords:
                    chordCursor = slot
                    selectedSlot = nil
                    lastWritten = nil
                    if composition.chord(covering: slot) == nil { chordMenuBeat = slot }
                case .melody:
                    noteCursor = slot
                }
            },
            menuSlot: mode == .chords ? chordMenuBeat : nil,
            onMenuDismiss: { chordMenuBeat = nil },
            menu: { beat in AnyView(chordMenu(at: beat)) },
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
    /// eighth goes on its beat). The cursor moves on past it, as if it had been typed there.
    private func drop(_ text: String, at slot: Int) -> Bool {
        if let symbol = ChordSymbol(dragText: text) {
            chordCursor = mode == .melody ? slot / 2 : slot
            selectedSlot = nil
            writeChord(symbol)
            return true
        }
        if let pitch = Self.pitch(fromDragText: text) {
            noteCursor = mode == .melody ? slot : slot * 2
            writeNote(pitch)
            return true
        }
        return false
    }

    /// The chord on palette button `slot`, written at the cursor; its versions show as chips.
    private func write(_ slot: PaletteSlot) {
        selectedSlot = slot
        writeChord(symbol(for: slot))
    }

    /// Writes `symbol` at the cursor for the chosen length (shortened to fit before the next
    /// chord or the barline) and moves the cursor past it. Past the end, it adds a measure first.
    private func writeChord(_ symbol: ChordSymbol) {
        var updated = composition
        let beat = min(chordCursor, updated.totalBeats)
        if beat == updated.totalBeats {
            guard updated.measureCount < Composition.measureRange.upperBound else {
                return showHint("That's all \(Composition.measureRange.upperBound) measures. Tap a beat to write there.",
                                symbol: "exclamationmark.circle")
            }
            updated.setMeasureCount(updated.measureCount + 1)
        }
        guard let beats = updated.place(symbol, at: beat, value: noteValue) else { return }
        composition = updated
        lastWritten = beat
        chordCursor = beat + beats
        if beats < noteValue.beats, let fitted = NoteValue(beats: beats) {
            showHint("Shortened to a \(fitted.displayName.lowercased()) note to fit.")
        }
    }

    /// Writes `pitch` at the note cursor, like `writeChord`.
    private func writeNote(_ pitch: SpelledPitch) {
        var updated = composition
        let tick = min(noteCursor, updated.totalEighths)
        if tick == updated.totalEighths {
            guard updated.measureCount < Composition.measureRange.upperBound else {
                return showHint("That's all \(Composition.measureRange.upperBound) measures. Tap the staff to write there.",
                                symbol: "exclamationmark.circle")
            }
            updated.setMeasureCount(updated.measureCount + 1)
        }
        guard let fitted = updated.placeNote(pitch, at: tick, value: melodyValue) else { return }
        composition = updated
        noteCursor = tick + fitted.eighths
        if fitted != melodyValue {
            showHint("Shortened to \(fitted == .eighth ? "an" : "a") \(fitted.displayName.lowercased()) note to fit.")
        }
    }

    /// The key's chords (as their buttons are set), to write on the empty `beat` tapped.
    private func chordMenu(at beat: Int) -> some View {
        let beats = composition.beatsPerMeasure
        return VStack(alignment: .leading, spacing: 10) {
            Text("Measure \(beat / beats + 1), beat \(beat % beats + 1)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(58), spacing: 6), count: 4), spacing: 6) {
                ForEach(slots(onPage: 0), id: \.self) { slot in
                    let chord = composition.chord(symbol(for: slot))
                    Button {
                        chordMenuBeat = nil
                        chordCursor = beat
                        write(slot)
                    } label: {
                        VStack(spacing: 1) {
                            Text(chord.romanNumeral)
                                .font(.system(size: 16, weight: .bold, design: .serif))
                            Text(chord.name)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: 58, height: 46)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chord.longName)
                }
            }
            Text("As a \(noteValue.displayName.lowercased()) note. More chords are in the row below.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 4 * 58 + 3 * 6 + 28)
    }

    private func showHint(_ text: String, symbol: String = "arrow.left.and.right.square") {
        hintTask?.cancel()
        hint = text
        hintSymbol = symbol
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
/// each beat to invite something, a long-press menu changes what's there or its measure, the
/// writing cursor (`cursorSlot`) is marked, and `menuSlot`'s beat pops up `menu` (the chords to
/// pick from right there). Without it, it's read-only (Play Along). Either way `chordColors` (by
/// start beat) and `noteColors` (by start eighth) tint chords and notes, and while a composition
/// plays, `playingMeasure` is lit and `playhead` sweeps through it.
struct CompositionStaffView: View {

    struct Editing {
        /// Slot (a beat, or an eighth when editing the melody) tapped.
        var onTap: (Int) -> Void
        /// The slot whose pop-up menu is open, and closing it.
        var menuSlot: Int? = nil
        var onMenuDismiss: () -> Void = {}
        var menu: (Int) -> AnyView = { _ in AnyView(EmptyView()) }
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
    /// Where the next chord (or note) typed goes.
    var cursorSlot: Int? = nil
    var playingMeasure: Int? = nil
    var playhead: CompositionPlayer.Playhead? = nil
    var editing: Editing? = nil

    private let lineSpacing: CGFloat = 9

    /// The id of the line of staff `measure` is on, for scrolling to it.
    static func rowID(measure: Int, showsMelody: Bool) -> String {
        let perLine = showsMelody ? 1 : 2
        return "staff.line.\(measure / perLine * perLine)"
    }

    private var isEditable: Bool { editing != nil }
    /// Lead-sheet layout: the melody on the staff, chords as text.
    private var showsMelody: Bool { composition.hasMelody || editingMelody }
    private var measuresPerLine: Int { showsMelody ? 1 : 2 }
    /// Slots per measure the cells are cut into.
    private var slotsPerMeasure: Int { editingMelody ? composition.eighthsPerMeasure : composition.beatsPerMeasure }

    var body: some View {
        let key = composition.keySignature
        // Room between lines so one line's numerals don't run into the next line's chord names.
        VStack(spacing: 12) {
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
                .id(Self.rowID(measure: first, showsMelody: showsMelody))
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
                         edgeToEdge: true, lineSpacing: lineSpacing, alignsLabels: true)
            .frame(maxWidth: .infinity)
            .background {
                // The measure playing, lit.
                if playingMeasure == measure {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.08))
                        .padding(.vertical, 22)
                }
            }
            .overlay {
                if isEditable {
                    HStack(spacing: 0) {
                        ForEach(first..<first + slotsPerMeasure, id: \.self) { slot in
                            slotCell(slot, measure: measure, emptyMeasure: emptyMeasure)
                        }
                    }
                }
            }
            .overlay {
                if playingMeasure == measure, let playhead {
                    playheadLine(playhead, measure: measure)
                }
            }
            .accessibilityElement(children: isEditable ? .contain : .combine)
    }

    /// A line sweeping through the measure in time with the playback.
    private func playheadLine(_ playhead: CompositionPlayer.Playhead, measure: Int) -> some View {
        let beats = Double(composition.beatsPerMeasure)
        return TimelineView(.animation) { context in
            let into = playhead.beat(at: context.date) - Double(measure) * beats
            GeometryReader { geo in
                if (0..<beats).contains(into) {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 2.5, height: lineSpacing * 6)
                        .position(x: geo.size.width * into / beats, y: geo.size.height / 2)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        let isCursor = cursorSlot == slot
        // Past the last slot: the next one written adds a measure, so the cursor waits at the end.
        let lastSlot = composition.measureCount * slotsPerMeasure - 1
        let cursorAfter = slot == lastSlot && cursorSlot == lastSlot + 1
        let cell = Rectangle()
            .fill(targetedSlot == slot ? Color.accentColor.opacity(0.18) : Color.clear)
            .overlay {
                if emptyMeasure && onBeat && !isCursor {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                } else if emptyMeasure && editingMelody && !isCursor {
                    Circle().fill(Color(.tertiaryLabel)).frame(width: 3, height: 3)
                }
            }
            // The cursor: a tinted slot with a bar at its start, where the next one typed goes.
            .overlay(alignment: .leading) {
                if isCursor {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.accentColor.opacity(0.14))
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: 3)
                    }
                    .frame(height: lineSpacing * 6)
                    .transition(.opacity)
                }
            }
            .overlay(alignment: .trailing) {
                if cursorAfter {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 3, height: lineSpacing * 6)
                        .offset(x: 4)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isCursor)
            .contentShape(Rectangle())
            .onTapGesture { editing?.onTap(slot) }
            .popover(isPresented: Binding(
                get: { editing?.menuSlot == slot },
                set: { if !$0 { editing?.onMenuDismiss() } }
            ), arrowEdge: .bottom) {
                editing?.menu(slot)
                    .presentationCompactAdaptation(.popover)
            }
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
            .accessibilityHint(editingMelody ? "Tap to write the next note here"
                               : chord == nil ? "Tap to pick a chord for this beat" : "Tap to write the next chord here")

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
