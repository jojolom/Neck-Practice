//
//  CompositionView.swift
//  Guitar Man
//
//  Compose: write a chord progression in Roman numerals on a staff, and optionally a melody
//  over it. Pick the key, 4/4 or 3/4, 2–16 measures, and the length of each chord or note as
//  you write it; rests fill the gaps.
//
//  Writing is like typing: tapping a numeral (or a note) puts it at the cursor on the staff,
//  sounds it, and moves the cursor past it, adding a measure at the end if need be; Rest and
//  backspace keys sit beside the lengths. Tapping an empty beat moves the cursor there.
//  Numerals can be dragged onto a beat too.
//
//  Changing is by selecting: tap a chord or note on the staff and its panel takes the palette's
//  place (length, versions and bass note or pitch, Copy, Shape, Replace, Delete); tap a
//  measure's number, then another to reach through to it, for the measures' panel (Copy,
//  Paste, Repeat, Insert, move, Clear, Delete). Nothing is on a long-press, and anything that
//  would write over or remove measures with music in them asks first. Undo and Redo are in the
//  navigation bar.
//
//  The palette is pinned above the bottom bar and stays one row of buttons however much it
//  offers: after a numeral is tapped its versions (its 7th, sus chords, in minor the major V)
//  show as chips under the row, and picking one changes the chord just written; More Chords
//  swaps the row for borrowed and secondary chords (♭VII, iv, V/V…); and the Chords | Melody
//  switch swaps the numerals for the key's notes. With a melody, the staff reads like a lead
//  sheet: the melody's notes, with the chords named above and numbered below.
//
//  Beside the keys there are two other ways in, picked by the buttons right of Chords | Melody:
//  a fretboard to tap melody notes on (ComposeFretboard), and Listen, which writes what's played
//  on the guitar (CompositionScribe): step by step at the cursor, or as a take played in time
//  after a count-in. With a melody, tablature shows under each line (CompositionTabRow).
//
//  The bottom bar plays it (CompositionPlayer: all of it, the measures selected, or from the
//  chord or note selected; once or looped; at the piece's own tempo), lighting each measure as
//  it's reached with a playhead sweeping through, and opens Play Along, which listens and marks
//  each chord green. A tour (ComposeWalkthrough) lights up each part the first time a
//  composition is opened each launch, until it's turned off.
//  Compositions save automatically once they have something in them.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - CompositionListView

struct CompositionListView: View {

    /// The editor, for a new composition, a saved one (by id), or one from a template; and the
    /// templates. Pushed through the enclosing stack's path, like everything else on Home's stack.
    private enum Route: Hashable {
        case new
        case saved(UUID)
        case examples
        case example(String)
    }

    @State private var store = CompositionStore.shared
    /// The saved composition being shared, and whether Files is open to pick one to bring in.
    @State private var sharing: Composition? = nil
    @State private var showImporter = false
    /// What came of opening a composition file, shown at the top of the list for a while. (Not
    /// an alert: a file can arrive from another app while a sheet is up, and an alert is lost then.)
    @State private var notice: String? = nil
    @State private var noticeTask: Task<Void, Never>? = nil
    private let router = DeepLinkRouter.shared
    @AppStorage(CompositionPlayer.tempoKey) private var usualTempo = CompositionPlayer.defaultTempo
    /// The saved composition being renamed, and the name typed so far.
    @State private var renaming: Composition? = nil
    @State private var nameDraft = ""
    @State private var deleting: Composition? = nil

    var body: some View {
        List {
            if let notice {
                Section {
                    Label(notice, systemImage: "tray.and.arrow.down.fill")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                .listRowBackground(Color.accentColor.opacity(0.14))
            }
            Section {
                NavigationLink(value: Route.new) {
                    Label("New Composition", systemImage: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                NavigationLink(value: Route.examples) {
                    Label("Examples", systemImage: "music.note.list")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                Button {
                    showImporter = true
                } label: {
                    Label {
                        Text("Open a Composition File")
                            .foregroundStyle(Color.primary)
                    } icon: {
                        Image(systemName: "tray.and.arrow.down")
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                .accessibilityHint("Adds a composition someone sent you, from Files")
            } footer: {
                Text("Tap Roman numerals to write a progression on the staff, add a melody if you like, then hear it and play it yourself. Examples has progressions and tunes to start from, simple to advanced.")
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
                        .swipeActions(edge: .leading) {
                            Button {
                                store.duplicate(composition.id)
                            } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            .tint(.teal)
                            Button {
                                sharing = composition
                            } label: {
                                Label("Share", systemImage: "square.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button {
                                store.duplicate(composition.id)
                            } label: {
                                Label("Duplicate", systemImage: "plus.square.on.square")
                            }
                            Button {
                                sharing = composition
                            } label: {
                                Label("Share…", systemImage: "square.and.arrow.up")
                            }
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
                    Text("Swipe left on one to rename or delete it, right to duplicate or share it.")
                }
            }
        }
        .navigationTitle("Compose")
        .sheet(item: $sharing) { composition in
            ComposeShareView(composition: composition, tempo: composition.tempo ?? usualTempo)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.guitarManComposition, .json, .data]) { result in
            if case .success(let url) = result { show(notice: CompositionImport.open(url, into: store).message) }
        }
        // A file opened from another app (Messages, Mail, AirDrop): the app has read it already.
        .onChange(of: router.composeMessage, initial: true) { _, message in
            guard let message else { return }
            router.composeMessage = nil
            show(notice: message)
        }
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
            case .examples:
                exampleList
            case .example(let id):
                if let example = CompositionExample.all.first(where: { $0.id == id }) {
                    CompositionEditorView(composition: newComposition(from: example), store: store)
                }
            }
        }
    }

    /// The examples, simplest first: each opens as a new composition of your own.
    private var exampleList: some View {
        List {
            ForEach(CompositionExample.Level.allCases) { level in
                Section {
                    ForEach(CompositionExample.all.filter { $0.level == level }) { example in
                        NavigationLink(value: Route.example(example.id)) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(example.name)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    if example.composition.hasMelody {
                                        Image(systemName: "music.note")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Color.accentColor)
                                            .accessibilityLabel("with a melody")
                                    }
                                }
                                Text(example.numerals)
                                    .font(.system(size: 14, weight: .semibold, design: .serif))
                                    .lineLimit(1)
                                Text(example.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(example.summary)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text(level.rawValue)
                } footer: {
                    Text(level.blurb)
                }
            }
            Section {
            } footer: {
                Text("An example opens as a new composition of your own, kept once you change it or play it. Change the key and the chords and the melody move with it.")
            }
        }
        .navigationTitle("Examples")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A blank composition (or a copy of `example`) with a name no saved one has.
    private func newComposition(from example: CompositionExample? = nil) -> Composition {
        var composition = example?.composition ?? Composition()
        composition.id = UUID()
        composition.name = store.unusedName(example?.name ?? "Untitled")
        return composition
    }

    private func show(notice text: String) {
        noticeTask?.cancel()
        withAnimation { notice = text }
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(8))
            if !Task.isCancelled { withAnimation { notice = nil } }
        }
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

    /// What's picked on the staff to change: a chord (by start beat), a note (by start eighth),
    /// or whole measures. While there's one, its panel takes the palette's place.
    private enum Selection: Equatable {
        case chord(Int)
        case note(Int)
        case measures(ClosedRange<Int>)
    }

    /// How notes and chords are put in: the keys, a neck to tap (melody), or by playing them.
    private enum Input {
        case keys, fretboard, listen
    }

    /// Something that would lose music, waiting for a yes.
    private enum Confirmation: Identifiable {
        case paste(Int)
        case deleteMeasures(ClosedRange<Int>)
        case clearChords, clearMelody
        /// Playing a take over measures (from this one on) that have that line written already.
        case record(Int)

        var id: String {
            switch self {
            case .paste(let measure):         return "paste.\(measure)"
            case .deleteMeasures(let range):  return "delete.\(range.lowerBound).\(range.upperBound)"
            case .clearChords:                return "clearChords"
            case .clearMelody:                return "clearMelody"
            case .record(let measure):        return "record.\(measure)"
            }
        }
    }

    let store: CompositionStore
    @State private var composition: Composition
    @State private var mode: Mode = .chords
    @State private var selection: Selection? = nil
    @State private var confirmation: Confirmation? = nil

    // Other ways in than the keys: the neck, and playing it (see CompositionScribe).
    @State private var input: Input = .keys
    @State private var scribe = CompositionScribe()
    /// Listen writes a take played in time, rather than chord by chord.
    @AppStorage("compose.listenInTime") private var listensInTime = false
    /// The measure the take being played starts at.
    @State private var takeMeasure = 0
    @State private var lastFretTapped: FretboardPosition? = nil
    @AppStorage(ComposeSettingsView.tabKey) private var showsTab = true

    // Copied things, to paste.
    @State private var clip: Composition.Clip? = nil
    @State private var copiedChord: ChordSymbol? = nil
    @State private var copiedNote: SpelledPitch? = nil

    // Chord palette.
    @State private var palettePage = 0
    /// The button tapped last: its versions show as chips.
    @State private var selectedSlot: PaletteSlot? = nil
    /// Where that button's chord was written, so a chip can change it.
    @State private var lastWritten: Int? = nil
    /// The beat the next chord goes on (`totalBeats` past the end: the next adds a measure).
    @State private var chordCursor: Int
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
    /// −1, 0, 1: flat, as in the key, or sharp, for the next note placed (then back to the key).
    @State private var alteration = 0
    @AppStorage("compose.melodyValue") private var melodyValue: NoteValue = .quarter

    /// "Shortened to fit" after a placement (or what to do first), briefly.
    @State private var hint: String? = nil
    @State private var hintSymbol = "arrow.left.and.right.square"
    @State private var hintTask: Task<Void, Never>? = nil
    /// The staff cell (by its first tick) a drag is over.
    @State private var targetedTick: Int? = nil
    @State private var showRename = false
    @State private var nameDraft = ""
    @State private var showPlayAlong = false
    @State private var showGuide = false
    @State private var showTempo = false
    /// The chord whose shapes on the neck are showing.
    @State private var shapeChord: ChordSymbol? = nil
    /// The groove made from this composition, for Solo Buddy: waiting for a yes (it's only part
    /// of the progression), and being soloed over.
    @State private var grooveOffered: SoloGroove? = nil
    @State private var soloGroove: SoloGroove? = nil
    @State private var showSoloBuddy = false
    @State private var showShare = false
    /// Key, time and measures open (they start open on an empty composition, where they're
    /// set first, and folded to one line on one that's been written, to give the staff room).
    @State private var settingsExpanded: Bool

    // Undo and redo: every change to the composition, whatever made it.
    @State private var history: [Composition] = []
    @State private var future: [Composition] = []
    @State private var isRestoring = false

    // Playback (see CompositionPlayer) and the sound of what's tapped.
    @AppStorage(CompositionPlayer.tapSoundsKey) private var tapSounds = true
    @AppStorage(CompositionPlayer.styleKey) private var playbackStyle: CompositionPlaybackStyle = .together
    /// The tempo for pieces that haven't been given their own: the one used last.
    @AppStorage(CompositionPlayer.tempoKey) private var usualTempo = CompositionPlayer.defaultTempo
    @AppStorage(CompositionPlayer.loopKey) private var loops = false
    @AppStorage(CompositionPlayer.countInKey) private var countIn = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var player = CompositionPlayer()
    @State private var showSettings = false
    /// When the cursor last moved during playback.
    @State private var cursorMovedAt = Date.distantPast
    /// Chords drawn faded behind the melody (Compose Settings).
    @AppStorage(ComposeSettingsView.chordsUnderMelodyKey) private var chordsUnderMelody = true
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

    /// What starts and restarts listening.
    private struct ListeningFor: Equatable {
        var isOn: Bool
        var mode: Mode
        var keyRoot: Note
        var isMinor: Bool
    }

    /// Whether something heard should be written at the cursor: only step by step (In Time
    /// writes takes, and nothing between them), not while the app itself is playing (the mic
    /// hears that too), nor with a panel, a question or the tour over the palette.
    private var acceptsHeard: Bool {
        input == .listen && !listensInTime && !player.isPlaying && selection == nil && tourStep == nil
            && !showPlayAlong && confirmation == nil
    }

    private var tempo: Int { composition.tempo ?? usualTempo }

    private var selectedChord: Composition.PlacedChord? {
        guard case .chord(let start) = selection else { return nil }
        return composition.chords.first { $0.start == start }
    }

    private var selectedMelodyNote: Composition.MelodyNote? {
        guard case .note(let start) = selection else { return nil }
        return composition.melody.first { $0.start == start }
    }

    private var selectedMeasures: ClosedRange<Int>? {
        guard case .measures(let range) = selection else { return nil }
        return range
    }

    /// The ticks of the staff the selected chord or note covers.
    private var selectedTicks: Range<Int>? {
        let perBeat = Composition.ticksPerBeat
        if mode == .chords, let chord = selectedChord { return chord.start * perBeat..<chord.end * perBeat }
        if mode == .melody, let note = selectedMelodyNote { return note.start..<note.end }
        return nil
    }

    /// Where the next thing typed goes, in ticks, and how wide to mark it.
    private var cursorTick: Int { mode == .chords ? chordCursor * Composition.ticksPerBeat : noteCursor }
    private var cursorWidth: Int {
        mode == .chords ? Composition.ticksPerBeat : min(max(melodyValue.ticks, 3), 6)
    }

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
                        targetedTick: targetedTick,
                        cursorTick: tourStep != nil || selection != nil ? nil : cursorTick,
                        cursorWidth: cursorWidth,
                        selectedTicks: selectedTicks,
                        selectedMeasures: selectedMeasures,
                        playingMeasure: player.playingMeasure,
                        playhead: player.clock,
                        showsChordsUnderMelody: chordsUnderMelody,
                        showsTab: showsTab,
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
                // The tour scrolls each part it lights up into view (the palette and the bottom
                // bar are pinned below, always in view).
                .onChange(of: tourStep) { _, step in
                    let steps = ComposeTour.steps
                    guard let step, steps.indices.contains(step), let target = steps[step].target,
                          [.settings, .staff].contains(target) else { return }
                    withAnimation(.easeInOut(duration: 0.3)) { scroller.scrollTo(target, anchor: .center) }
                }
                // Keep the line being written, or played, in view.
                .onChange(of: mode == .chords ? chordCursor : noteCursor) {
                    if player.isPlaying { cursorMovedAt = .now }
                    scrollToMeasure(cursorMeasure, scroller)
                }
                // While you're writing during playback, the page stays with what you're writing.
                .onChange(of: player.playingMeasure) { _, measure in
                    guard let measure, Date.now.timeIntervalSince(cursorMovedAt) > Self.cursorHold else { return }
                    scrollToMeasure(measure, scroller)
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
        // The palette, pinned over the bottom bar like a keyboard, so it stays under your thumb
        // while the staff scrolls to follow what you write. With something picked on the staff,
        // its panel is there instead.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Group {
                    if let chord = selectedChord {
                        chordPanel(chord)
                    } else if let note = selectedMelodyNote {
                        notePanel(note)
                    } else if let measures = selectedMeasures {
                        measuresPanel(measures)
                    } else {
                        palette
                    }
                }
                .padding(.top, 10)
                .disabled(tourStep != nil)
                bottomBar
            }
            .background(.bar)
            .animation(.easeInOut(duration: 0.18), value: selection)
        }
        .overlayPreferenceValue(ComposeTourAnchors.self) { anchors in
            ComposeWalkthroughOverlay(steps: ComposeTour.steps, step: $tourStep, anchors: anchors) { keepShowing in
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
        // Playback is of what's on screen as it's set up now: any change restarts the measure.
        .onDisappear {
            player.stop()
            scribe.stop()
        }
        // Listening starts with the Listen input and follows the part and the key.
        .task(id: ListeningFor(isOn: input == .listen && scenePhase == .active, mode: mode,
                               keyRoot: composition.keyRoot, isMinor: composition.isMinor)) {
            if input == .listen && scenePhase == .active {
                scribe.onChord = { heard in
                    guard acceptsHeard else { return }
                    selectedSlot = nil
                    writeChord(heard, sounds: false)
                }
                scribe.onNote = { heard in
                    guard acceptsHeard else { return }
                    writeNote(heard, sounds: false)
                }
                scribe.onTakeFull = { endTake() }
                await scribe.listen(for: mode == .chords ? .chords : .melody, in: composition)
            } else {
                scribe.stop()
            }
        }
        .onChange(of: playbackStyle) { restartPlayback() }
        .onChange(of: loops) { player.setLoops(loops) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { player.stop() }
        }
        .onChange(of: mode) {
            selection = nil
            if scribe.isRecording { _ = scribe.endTake() }
            if mode == .chords && input == .fretboard { input = .keys }
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
            ToolbarItemGroup(placement: .topBarTrailing) {
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
                moreMenu
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
        .confirmationDialog(confirmationTitle, isPresented: Binding(get: { confirmation != nil },
                                                                    set: { if !$0 { confirmation = nil } }),
                            titleVisibility: .visible) {
            Button(confirmationAction, role: .destructive) { confirm() }
        } message: {
            Text("Undo brings it back.")
        }
        .fullScreenCover(isPresented: $showPlayAlong) {
            CompositionPlayAlongView(composition: composition)
        }
        .sheet(isPresented: $showGuide) {
            ComposeGuideView()
        }
        .sheet(isPresented: $showShare) {
            ComposeShareView(composition: composition, tempo: tempo)
        }
        // Over the editor, like Play Along (pushing it would go through Home's stack).
        .fullScreenCover(isPresented: $showSoloBuddy) {
            SoloBuddyView(groove: soloGroove) { showSoloBuddy = false }
                .environment(\.providesNavigationStack, false)
        }
        .alert("Solo Buddy loops up to four chords", isPresented: Binding(get: { grooveOffered != nil },
                                                                           set: { if !$0 { grooveOffered = nil } })) {
            Button("Open Solo Buddy") {
                if let grooveOffered { openSoloBuddy(grooveOffered) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will loop \(grooveOffered.map(grooveChords) ?? ""), one chord to a bar, from the chord each measure starts on.")
        }
        .sheet(isPresented: Binding(get: { shapeChord != nil }, set: { if !$0 { shapeChord = nil } })) {
            if let shapeChord { shapeSheet(composition.chord(shapeChord)) }
        }
        // Save as you go, once there's something to keep (and keep saving a saved one, so
        // clearing it sticks). Every change to the music can be undone.
        .onChange(of: composition) { old, updated in
            player.restartMeasure(updated, style: playbackStyle, bpm: updated.tempo ?? usualTempo)
            var oldAtNewTempo = old
            oldAtNewTempo.tempo = updated.tempo
            if isRestoring {
                isRestoring = false
            } else if oldAtNewTempo != updated {
                history.append(old)
                if history.count > 100 { history.removeFirst() }
                future.removeAll()
            }
            if !updated.isEmpty || store.compositions.contains(where: { $0.id == updated.id }) {
                store.save(updated)
            }
            chordCursor = min(chordCursor, updated.totalBeats)
            noteCursor = min(noteCursor, updated.totalTicks)
            // What was picked may be gone (an undo, a change of meter).
            switch selection {
            case .chord(let start) where !updated.chords.contains { $0.start == start }: selection = nil
            case .note(let start) where !updated.melody.contains { $0.start == start }: selection = nil
            case .measures(let range) where range.upperBound >= updated.measureCount: selection = nil
            default: break
            }
            // The first chord written: the key and time are set, so give the staff the room.
            if old.isEmpty && !updated.isEmpty && settingsExpanded {
                withAnimation(.easeInOut(duration: 0.25)) { settingsExpanded = false }
            }
        }
    }

    /// The measure the cursor is in (the last, when it's past the end).
    private var cursorMeasure: Int {
        let measure = mode == .chords ? chordCursor / composition.beatsPerMeasure : noteCursor / composition.ticksPerMeasure
        return min(measure, composition.measureCount - 1)
    }

    /// How long after the cursor moves the page stops following playback (seconds).
    private static let cursorHold: TimeInterval = 4

    private func restartPlayback() {
        player.restartMeasure(composition, style: playbackStyle, bpm: tempo)
    }

    private func scrollToMeasure(_ measure: Int, _ scroller: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.25)) {
            scroller.scrollTo(CompositionStaffView.rowID(measure: measure, showsMelody: showsMelody))
        }
    }

    // MARK: - Bottom bar and menu

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Button {
                togglePlay()
            } label: {
                Image(systemName: player.isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 48)
                    .background(composition.isEmpty ? Color.gray.opacity(0.4) : Color.accentColor,
                                in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(composition.isEmpty)
            .accessibilityLabel(player.isPlaying ? "Stop" : playLabel)

            Button {
                loops.toggle()
            } label: {
                Image(systemName: "repeat")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(loops ? Color.white : Color.primary)
                    .frame(width: 44, height: 48)
                    .background(loops ? Color.accentColor : Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel("Loop")
            .accessibilityAddTraits(loops ? .isSelected : [])

            Button {
                showTempo = true
            } label: {
                VStack(spacing: 0) {
                    Text("\(tempo)")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("BPM")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .frame(width: 56, height: 48)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .accessibilityLabel("Tempo, \(tempo) beats per minute")
            .accessibilityHint("Tempo, count-in and how chords sound")
            .popover(isPresented: $showTempo, arrowEdge: .bottom) {
                tempoPopover
                    .presentationCompactAdaptation(.popover)
            }

            Button {
                player.stop()
                // Play Along listens for itself.
                if input == .listen { input = .keys }
                // A composition started from a template is kept once you play it, even unedited.
                if !composition.isEmpty { store.save(composition) }
                showPlayAlong = true
            } label: {
                Label("Play Along", systemImage: "music.mic")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(composition.isEmpty ? Color.secondary : Color.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(composition.isEmpty)
        }
        .buttonStyle(.plain)
        .composeTourTarget(.playAlong)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var tempoPopover: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Tempo")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(tempo) BPM")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Stepper("Tempo", value: tempoBinding, in: CompositionPlayer.tempoRange)
                    .labelsHidden()
            }
            Slider(value: Binding(get: { Double(tempo) }, set: { tempoBinding.wrappedValue = Int($0.rounded()) }),
                   in: Double(CompositionPlayer.tempoRange.lowerBound)...Double(CompositionPlayer.tempoRange.upperBound))
                .accessibilityLabel("Tempo")
            Toggle("Count In First", isOn: $countIn)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            HStack {
                Text("Chords")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Picker("Chords", selection: $playbackStyle) {
                    ForEach(CompositionPlaybackStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)
            }
            Text("The tempo is kept with this composition.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 320)
    }

    /// The tempo, kept with the piece (and remembered as the one to start the next piece at).
    private var tempoBinding: Binding<Int> {
        Binding(get: { tempo }, set: {
            composition.tempo = $0
            usualTempo = $0
        })
    }

    private var playLabel: String {
        switch selection {
        case .measures(let range): return range.count == 1 ? "Play measure \(range.lowerBound + 1)" : "Play measures \(range.lowerBound + 1) to \(range.upperBound + 1)"
        case .chord, .note:        return "Play from here"
        case nil:                  return "Play"
        }
    }

    /// Plays the measures selected, or from the chord or note selected to the end, or all of it.
    private func togglePlay() {
        if player.isPlaying { return player.stop() }
        if scribe.isRecording { endTake() }
        let lastUsed = (0..<composition.measureCount).last { !composition.isMeasureEmpty($0) } ?? 0
        var measures: Range<Int>? = nil
        switch selection {
        case .measures(let range): measures = range.lowerBound..<(range.upperBound + 1)
        case .chord(let start):    measures = (start / composition.beatsPerMeasure)..<(lastUsed + 1)
        case .note(let start):     measures = (start / composition.ticksPerMeasure)..<(lastUsed + 1)
        case nil:                  break
        }
        player.play(composition, style: playbackStyle, bpm: tempo, measures: measures, loops: loops, countIn: countIn)
        if !player.isPlaying { showHint("Nothing to play there yet.", symbol: "speaker.slash") }
    }

    /// What to do next, for what's picked now.
    private var instructions: String {
        switch selection {
        case .chord:
            return "Change the chord below, or tap Done. Tap another chord to pick it instead."
        case .note:
            return "Change the note below, or tap Done. Tap another note to pick it instead."
        case .measures:
            return "Tap another measure number to select up to it. Play plays just these measures."
        case nil:
            break
        }
        switch mode {
        case .chords:
            return "Tap chords to write them one after another at the blue mark. Tap an empty beat to move the mark there, a chord to change it, or a measure number to copy, move or delete measures."
        case .melody:
            return "Tap notes to write them one after another at the blue mark: each beat splits in two for eighth notes. Tap the staff to move the mark, or a note to change it."
        }
    }

    private func startTour(after delay: TimeInterval) {
        mode = .chords
        input = .keys
        selection = nil
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
            Button {
                nameDraft = composition.name
                showRename = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                player.stop()
                showShare = true
            } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            .disabled(composition.isEmpty)
            Button {
                guard let made = composition.soloGroove else { return }
                if made.isWhole { openSoloBuddy(made.groove) } else { grooveOffered = made.groove }
            } label: {
                Label("Open in Solo Buddy", systemImage: "guitars")
            }
            .disabled(composition.chords.isEmpty)
            Section {
                Button(role: .destructive) {
                    confirmation = .clearChords
                } label: {
                    Label("Clear All Chords…", systemImage: "trash")
                }
                .disabled(composition.chords.isEmpty)
                if composition.hasMelody {
                    Button(role: .destructive) {
                        confirmation = .clearMelody
                    } label: {
                        Label("Clear Melody…", systemImage: "trash")
                    }
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    /// "C, G, Am and F".
    private func grooveChords(_ groove: SoloGroove) -> String {
        let names = groove.chords.map { groove.chord($0).name }
        return names.count > 1 ? names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "") : names.first ?? ""
    }

    /// Opens Solo Buddy on the groove made from this composition's chords.
    private func openSoloBuddy(_ groove: SoloGroove) {
        player.stop()
        if input == .listen { input = .keys }
        soloGroove = groove
        showSoloBuddy = true
    }

    private var confirmationTitle: String {
        switch confirmation {
        case .paste(let measure):
            let count = clip?.measures.count ?? 1
            return count == 1 ? "Paste over measure \(measure + 1)?" : "Paste over what's in measures \(measure + 1) to \(measure + count)?"
        case .deleteMeasures(let range):
            return "Delete \(measuresName(range).lowercased()) and what's in \(range.count == 1 ? "it" : "them")?"
        case .clearChords:  return "Clear all the chords?"
        case .clearMelody:  return "Clear the whole melody?"
        case .record(let measure):
            return "Play over the \(mode == .chords ? "chords" : "melody") from measure \(measure + 1) on?"
        case nil:           return ""
        }
    }

    private var confirmationAction: String {
        switch confirmation {
        case .paste:           return "Paste Over"
        case .record:          return "Record Over"
        case .deleteMeasures:  return "Delete"
        default:               return "Clear"
        }
    }

    private func confirm() {
        switch confirmation {
        case .paste(let measure):         paste(at: measure)
        case .deleteMeasures(let range):  deleteMeasures(range)
        case .clearChords:                composition.clearChords()
        case .clearMelody:                composition.clearMelody()
        case .record(let measure):        beginTake(at: measure)
        case nil:                         break
        }
        confirmation = nil
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
                    set: { composition.setKey(root: $0, isMinor: composition.isMinor) }
                )) {
                    ForEach(Note.circleOfFifthsKeys(asMinor: composition.isMinor)) { note in
                        Text(keyLabel(note)).tag(note)
                    }
                }
                .pickerStyle(.menu)
                Picker("Scale", selection: Binding(
                    get: { composition.isMinor },
                    set: { composition.setKey(root: composition.keyRoot, isMinor: $0) }
                )) {
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

            if composition.hasMelody {
                Text("Changing the key moves the melody along with the chords.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
    }

    private func keyLabel(_ note: Note) -> String {
        let key = KeySignature(root: note, isMinor: composition.isMinor)
        let name = composition.isMinor ? key.minorKeyName : key.majorKeyName
        return name.components(separatedBy: " ").first ?? name
    }

    // MARK: - Palette

    private var palette: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Write", selection: $mode.animation(.easeInOut(duration: 0.2))) {
                    ForEach(Mode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 190)
                .composeTourTarget(.mode)
                .id(ComposeTourTarget.mode)
                Spacer(minLength: 0)
                inputKeys
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 2)

            switch (input, mode) {
            case (.listen, _):          listenPanel
            case (.fretboard, .melody): fretboardPalette
            case (_, .chords):          chordPalette
            case (_, .melody):          melodyPalette
            }
        }
        .animation(.easeInOut(duration: 0.2), value: input)
        // A whole note doesn't fit in 3/4.
        .onChange(of: composition.beatsPerMeasure, initial: true) { _, beats in
            if noteValue.beats > beats { noteValue = NoteValue(beats: beats) ?? .quarter }
            if melodyValue.ticks > beats * Composition.ticksPerBeat { melodyValue = .dottedHalf }
        }
    }

    /// How to put notes in: the keys, the neck (melody), or by playing.
    private var inputKeys: some View {
        HStack(spacing: 4) {
            inputKey(.keys, symbol: "keyboard", label: "Keys", hint: "Write by tapping \(mode == .chords ? "chords" : "notes")")
            if mode == .melody {
                inputKey(.fretboard, symbol: "guitars", label: "Fretboard", hint: "Write notes by tapping where they're played on the neck")
            }
            inputKey(.listen, symbol: "mic.fill", label: "Listen", hint: "Write by playing your guitar")
        }
    }

    private func inputKey(_ kind: Input, symbol: String, label: String, hint: String) -> some View {
        let isOn = input == kind
        return Button {
            input = kind
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .frame(width: 42, height: 32)
                .background(isOn ? (kind == .listen ? Color.red : Color.accentColor) : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Fretboard

    /// The neck in place of the note keys: tap where a note is played to write it there.
    private var fretboardPalette: some View {
        VStack(alignment: .leading, spacing: 6) {
            ComposeFretboard(keySignature: composition.keySignature,
                             tonic: composition.scalePitches(octave: 3)[0].note.rawValue,
                             lastTapped: lastFretTapped) { position in
                lastFretTapped = position
                writeNote(ComposeHearing.spell(midi: position.midiNote, in: composition.keySignature), string: position.stringIndex)
            }
            melodyLengthRow(withAccidentals: false)
        }
    }

    // MARK: Listen

    /// Listen in place of the keys: play, and it's written. Step by step writes each chord or
    /// note at the cursor with the length chosen; In Time records a take against the beat.
    private var listenPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("How it listens", selection: $listensInTime) {
                Text("Step by Step").tag(false)
                Text("In Time").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .disabled(scribe.isRecording)

            listenStatus
                .padding(.horizontal, 16)
                .frame(height: 54)

            if listensInTime {
                takeControls
            } else if mode == .chords {
                chordLengthRow
            } else {
                melodyLengthRow(withAccidentals: false)
            }
        }
        .onChange(of: listensInTime) {
            if scribe.isRecording { _ = scribe.endTake() }
        }
    }

    private var listenStatus: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            HStack(spacing: 12) {
                micMeter
                if scribe.permissionDenied {
                    listenText("Microphone access is off", "Turn it on for Guitar Man in the Settings app.")
                } else if !scribe.isListening {
                    listenText("Starting the microphone…", "")
                } else if player.isPlaying {
                    listenText("Paused while it plays", "Stop playback to carry on writing.")
                } else if let clock = scribe.takeClock {
                    takeStatus(clock, at: context.date)
                } else if !listensInTime, context.date.timeIntervalSince(scribe.heardAt) < 2.5, let heard = scribe.heard {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(heard)
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                        Text("Written. Play the next one.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                } else if !listensInTime, context.date.timeIntervalSince(scribe.missedAt) < 2.5 {
                    listenText("Didn't catch that", mode == .chords ? "Strum again and let it ring. It listens for chords in \(composition.keyName)."
                                                                    : "Pluck one note and let it ring.")
                } else if listensInTime {
                    listenText("Ready when you are", "Record counts you in, then writes what you play on the beat.")
                } else {
                    listenText(mode == .chords ? "Strum a chord" : "Pluck a note",
                               "It's written at the blue mark as \(lengthPhrase).")
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func listenText(_ title: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
    }

    /// "a half note", "an eighth note": the length chosen for what's written next.
    private var lengthPhrase: String {
        (mode == .chords ? noteValue : melodyValue).phrase
    }

    /// The mic and how loud it hears.
    private var micMeter: some View {
        let level = CGFloat(min(max(scribe.level, 0), 1))
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.3))
                .frame(height: 46 * level)
            Image(systemName: scribe.isListening ? "mic.fill" : "mic.slash")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(scribe.isListening ? Color.red : Color.secondary)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 40, height: 46)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .animation(.easeOut(duration: 0.1), value: level)
        .accessibilityHidden(true)
    }

    /// The count-in, then where the take is, with a dot for each beat of the measure.
    private func takeStatus(_ clock: CompositionScribe.TakeClock, at date: Date) -> some View {
        let beat = clock.beat(at: date)
        let whole = Int(beat.rounded(.down))
        let inMeasure = ((whole % clock.beatsPerMeasure) + clock.beatsPerMeasure) % clock.beatsPerMeasure
        let what = mode == .chords ? "chord" : "note"
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(beat < 0 ? "Count in" : "Measure \(takeMeasure + whole / clock.beatsPerMeasure + 1)")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
                ForEach(0..<clock.beatsPerMeasure, id: \.self) { index in
                    Circle()
                        .fill(index == inMeasure ? (beat < 0 ? Color.orange : Color.red) : Color(.systemGray4))
                        .frame(width: index == inMeasure ? 13 : 9, height: index == inMeasure ? 13 : 9)
                        .frame(width: 13, height: 13)
                }
            }
            Text(beat < 0 ? (scribe.clicksThroughTake ? "Come in after the clicks." : "Come in after the clicks, then follow the dots. Headphones keep the click going.")
                          : "\(scribe.takeCount) \(what)\(scribe.takeCount == 1 ? "" : "s") heard. Tap Stop when you're done.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }

    private var takeControls: some View {
        HStack(spacing: 8) {
            Button {
                scribe.isRecording ? endTake() : requestTake()
            } label: {
                Label(scribe.isRecording ? "Stop" : "Record", systemImage: scribe.isRecording ? "stop.fill" : "record.circle")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 124, height: 40)
                    .background(scribe.isListening ? Color.red : Color.gray.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(!scribe.isListening)
            Text(scribe.isRecording ? "Recording from measure \(takeMeasure + 1), at \(tempo) BPM."
                                    : "From measure \(cursorMeasure + 1), at \(tempo) BPM. Tap a beat to start somewhere else.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
    }

    /// Starts a take at the cursor's measure, asking first if it would go over what's written.
    private func requestTake() {
        let measure = cursorMeasure
        let written = mode == .chords
            ? composition.chords.contains { $0.start >= measure * composition.beatsPerMeasure }
            : composition.melody.contains { $0.start >= measure * composition.ticksPerMeasure }
        if written { confirmation = .record(measure) } else { beginTake(at: measure) }
    }

    private func beginTake(at measure: Int) {
        player.stop()
        selection = nil
        takeMeasure = measure
        scribe.beginTake(bpm: tempo, beatsPerMeasure: composition.beatsPerMeasure,
                         measures: Composition.measureRange.upperBound - measure)
    }

    /// Ends the take and writes it, on the nearest beats, from the measure it started at.
    private func endTake() {
        guard scribe.isRecording else { return }
        let take = scribe.endTake()
        var updated = composition
        let written = mode == .chords ? updated.write(chords: take.chords, fromMeasure: takeMeasure)
                                      : updated.write(notes: take.notes, fromMeasure: takeMeasure)
        guard let written else {
            return showHint("Nothing was heard, so nothing's changed.", symbol: "mic.slash")
        }
        composition = updated
        selection = .measures(written)
        let count = mode == .chords ? take.chords.count : take.notes.count
        showHint("Wrote \(count) \(mode == .chords ? "chord" : "note")\(count == 1 ? "" : "s"). Play to hear it; Undo takes it back.", symbol: "checkmark.circle")
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

    /// The other versions of a chord on the staff: the versions of the palette button it came from.
    private func family(of symbol: ChordSymbol) -> [ChordSymbol] {
        let root = symbol.rootPosition
        for page in 0..<2 {
            for slot in slots(onPage: page) {
                let options = variants(of: slot)
                if options.contains(root) { return options }
            }
        }
        return [root]
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
            Group {
                if let symbol = selectedSymbol {
                    let chord = composition.chord(symbol)
                    Text("\(chord.romanNumeral) in \(composition.keyName) is \(chord.longName)")
                } else {
                    Text(palettePage == 0 ? "Chords in \(composition.keyName)" : "Borrowed and secondary chords")
                }
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) { moreChordsButton.background(.bar) }
            .padding(.horizontal, 20)

            HStack(spacing: 6) {
                ForEach(slots(onPage: palettePage), id: \.self) { slot in
                    chordButton(slot)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .composeTourTarget(.palette)
            .id(ComposeTourTarget.palette)

            if copiedChord != nil || (selectedSlot.map { variants(of: $0).count > 1 } ?? false) {
                chipRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            chordLengthRow
        }
        .animation(.easeInOut(duration: 0.2), value: selectedSlot)
    }

    private var moreChordsButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                palettePage = palettePage == 0 ? 1 : 0
                selectedSlot = nil
            }
        } label: {
            HStack(spacing: 4) {
                if palettePage == 1 { Image(systemName: "chevron.left") }
                Text(palettePage == 0 ? "More Chords" : "Chords in Key")
                if palettePage == 0 { Image(systemName: "chevron.right") }
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .padding(.leading, 8)
        }
        .accessibilityHint(palettePage == 0 ? "Shows borrowed and secondary chords" : "Shows the chords in the key")
    }

    /// How many beats the next chord lasts, with Rest and backspace.
    private var chordLengthRow: some View {
        HStack(spacing: 6) {
            ForEach(composition.noteValues) { value in
                ComposeKey(title: "\(value.beats)", isOn: value == noteValue) { noteValue = value }
                    .accessibilityLabel("\(value.displayName) note, \(value.beats) \(value.beats == 1 ? "beat" : "beats")")
            }
            Text(noteValue.beats == 1 ? "beat" : "beats")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
                .accessibilityHidden(true)
            typingKeys
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .composeTourTarget(.length)
        .id(ComposeTourTarget.length)
    }

    /// Rest and backspace, as on a keyboard.
    @ViewBuilder
    private var typingKeys: some View {
        ComposeKey(title: "Rest") { writeRest() }
            .frame(width: 58)
            .accessibilityHint("Leaves a rest at the cursor and moves on")
        ComposeKey(systemImage: "delete.backward") { backspace() }
            .frame(width: 48)
            .accessibilityLabel("Delete backward")
            .accessibilityHint("Removes what's before the cursor")
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
        .padding(.vertical, 9)
        .padding(.horizontal, 2)
        .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(chord.romanNumeral), \(chord.longName)")
        .accessibilityHint("Writes it at the cursor")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Under the chord buttons: the copied chord to paste, and the versions of the button tapped
    /// last (its plain chord, 7th, sus chords…). Picking a version changes the chord that button
    /// just wrote, and what it writes from then on.
    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if let copied = copiedChord {
                    let chord = composition.chord(copied)
                    Button {
                        selectedSlot = nil
                        writeChord(copied)
                    } label: {
                        Label("Paste \(chord.name)", systemImage: "doc.on.clipboard")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.14), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Writes the copied chord at the cursor")
                }
                if let slot = selectedSlot, variants(of: slot).count > 1 {
                    let current = symbol(for: slot)
                    ForEach(variants(of: slot), id: \.self) { variant in
                        chordChip(variant, isCurrent: variant == current) {
                            chosenVariants[slot] = variant
                            if let start = lastWritten {
                                composition.setSymbol(ofChordAt: start, to: variant)
                                audition(variant)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chordChip(_ symbol: ChordSymbol, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        let chord = composition.chord(symbol)
        return Button(action: action) {
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

    // MARK: Melody

    /// The note button `degree` (1–7) places: the key's note in the chosen octave, sharpened or
    /// flattened if that's picked.
    private func melodyPitch(_ degree: Int) -> SpelledPitch {
        let note = composition.scalePitches(octave: 3 + register)[degree - 1]
        return SpelledPitch(letter: note.letter, accidental: max(-2, min(2, note.accidental + alteration)), octave: note.octave)
    }

    private var registerName: String { ["Low", "Middle", "High"][register + 1] }

    private static let ordinals = ["1st", "2nd", "3rd", "4th", "5th", "6th", "7th"]

    private var registerControl: some View {
        HStack(spacing: 2) {
            Button {
                register = max(-1, register - 1)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 32, height: 30)
            }
            .disabled(register <= -1)
            .accessibilityLabel("Lower octave")
            Text(registerName)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(minWidth: 50)
            Button {
                register = min(1, register + 1)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 32, height: 30)
            }
            .disabled(register >= 1)
            .accessibilityLabel("Higher octave")
        }
        .font(.system(size: 14, weight: .semibold))
        .buttonStyle(.borderless)
    }

    private var melodyPalette: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Group {
                    if let degree = selectedNote {
                        let pitch = composition.scalePitches(octave: 3 + register)[degree - 1]
                        Text("\(pitch.name) is the \(Self.ordinals[degree - 1]) note of \(composition.keyName)")
                    } else {
                        Text("Notes in \(composition.keyName)")
                    }
                }
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let copied = copiedNote {
                    Button {
                        writeNote(copied)
                    } label: {
                        Label("Paste \(copied.name)", systemImage: "doc.on.clipboard")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .accessibilityHint("Writes the copied note at the cursor")
                }
                registerControl
            }
            .padding(.leading, 20)
            .padding(.trailing, 12)

            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { degree in
                    noteButton(degree)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)

            melodyLengthRow(withAccidentals: true)
        }
    }

    /// The length of the next note, with Rest and backspace; and for the note keys, ♭ and ♯.
    private func melodyLengthRow(withAccidentals: Bool) -> some View {
        HStack(spacing: 6) {
            if withAccidentals {
                Picker("Accidental", selection: $alteration) {
                    Text("♭").tag(-1)
                    Text("Key").tag(0)
                    Text("♯").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 118)
                .accessibilityHint("Flattens or sharpens the next note you write, then goes back to the key")
            }
            Menu {
                Picker("Length", selection: $melodyValue) {
                    ForEach(composition.melodyValues) { value in
                        Text(value.displayName).tag(value)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(withAccidentals ? melodyValue.displayName : "\(melodyValue.displayName) notes")
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            }
            .accessibilityLabel("Note length, \(melodyValue.displayName)")
            typingKeys
        }
        .padding(.horizontal, 16)
        .padding(.top, 2)
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
        .padding(.vertical, 9)
        .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            selectedNote = degree
            writeNote(pitch)
            // A sharp or flat is for one note.
            alteration = 0
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pitch.name), scale note \(degree)")
        .accessibilityHint("Writes it at the cursor")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private static func dragText(for pitch: SpelledPitch) -> String {
        "note:" + ((try? JSONEncoder().encode(pitch)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}")
    }

    private static func pitch(fromDragText text: String) -> SpelledPitch? {
        guard text.hasPrefix("note:") else { return nil }
        return try? JSONDecoder().decode(SpelledPitch.self, from: Data(text.dropFirst(5).utf8))
    }

    // MARK: - Panels for what's selected

    private func panelHeader(_ title: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 4)
            Button("Done") { selection = nil }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .accessibilityHint("Goes back to writing")
        }
        .padding(.horizontal, 16)
    }

    private func panelCaption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
    }

    /// The chord picked on the staff: its length, its other versions and what's in the bass,
    /// and Copy, Shape, Replace and Delete.
    private func chordPanel(_ placed: Composition.PlacedChord) -> some View {
        let chord = composition.chord(placed.symbol)
        let room = composition.room(at: placed.start)
        return VStack(alignment: .leading, spacing: 8) {
            panelHeader("\(chord.name) · \(chord.romanNumeral) · \(placed.value.displayName) note")

            HStack(spacing: 6) {
                ForEach(composition.noteValues) { value in
                    ComposeKey(title: "\(value.beats)", isOn: value == placed.value) {
                        composition.setLength(ofChordAt: placed.start, to: value)
                    }
                    .disabled(value.beats > room)
                    .accessibilityLabel("\(value.displayName) note, \(value.beats) \(value.beats == 1 ? "beat" : "beats")")
                }
                panelCaption(placed.beats == 1 ? "beat" : "beats")
                    .frame(width: 40, alignment: .leading)
                    .accessibilityHidden(true)
                ComposeKey(title: "Tie", systemImage: "link", isOn: composition.tiesForward(placed)) {
                    var updated = composition
                    if updated.toggleTie(ofChordAt: placed.start) {
                        composition = updated
                    } else {
                        showHint("A tie joins the same chord twice. A different one comes next.", symbol: "exclamationmark.circle")
                    }
                }
                .frame(width: 72)
                .accessibilityHint("Holds the chord on into the next one, over a barline too, so it's played once")
            }
            .padding(.horizontal, 16)

            let versions = family(of: placed.symbol)
            if versions.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(versions, id: \.self) { version in
                            chordChip(version, isCurrent: version == placed.symbol.rootPosition) {
                                let kept = min(placed.symbol.inversion, composition.chord(version).maxInversion)
                                change(placed, to: version.inverted(kept))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            if chord.maxInversion > 0 {
                HStack(spacing: 6) {
                    panelCaption("Lowest note")
                        .padding(.trailing, 2)
                        ForEach(0...chord.maxInversion, id: \.self) { inversion in
                            let inverted = placed.symbol.inverted(inversion)
                            let bass = composition.chord(inverted).bass.name
                            let isCurrent = placed.symbol.inversion == inversion
                            Button {
                                change(placed, to: inverted)
                            } label: {
                                Text(bass)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(isCurrent ? .white : .primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(isCurrent ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(inversion == 0 ? "Root position, \(bass) in the bass" : "\(bass) in the bass")
                            .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 6) {
                ComposeKey(title: "Copy", systemImage: "doc.on.doc") {
                    copiedChord = placed.symbol
                    showHint("Copied \(chord.name). Paste it from under the chord buttons.", symbol: "doc.on.doc")
                }
                ComposeKey(title: "Shape", systemImage: "hand.point.up.left") { shapeChord = placed.symbol }
                    .accessibilityHint("Shows where to play it on the neck")
                ComposeKey(title: "Replace", systemImage: "arrow.triangle.2.circlepath") {
                    selection = nil
                    chordCursor = placed.start
                    noteValue = placed.value
                }
                .accessibilityHint("Puts the cursor here so the next chord you tap takes its place")
                ComposeKey(title: "Delete", systemImage: "trash", isDestructive: true) {
                    composition.removeChord(covering: placed.start)
                    chordCursor = placed.start
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func change(_ placed: Composition.PlacedChord, to symbol: ChordSymbol) {
        composition.setSymbol(ofChordAt: placed.start, to: symbol)
        audition(symbol)
    }

    /// The note picked on the staff: its length and pitch, and Copy, Replace and Delete.
    private func notePanel(_ note: Composition.MelodyNote) -> some View {
        let room = composition.noteRoom(at: note.start)
        let key = composition.keySignature
        let alteration = note.pitch.accidental - key.accidental(forLetter: note.pitch.letter)
        return VStack(alignment: .leading, spacing: 8) {
            panelHeader("\(note.pitch.name) · \(note.value.displayName) note")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if note.isTriplet {
                        panelCaption("A third of its beat. To change the rhythm, write other notes over the beat.")
                            .padding(.vertical, 8)
                    }
                    ForEach(note.isTriplet ? [] : composition.melodyValues.reversed().filter { !$0.isTriplet && ($0.ticks <= room || $0 == note.value) }) { value in
                        let isCurrent = value == note.value
                        Button {
                            composition.setLength(ofNoteAt: note.start, to: value)
                        } label: {
                            Text(value.displayName)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(isCurrent ? .white : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(isCurrent ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isCurrent ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 6) {
                ComposeKey(systemImage: "arrow.down") { step(note, by: -1) }
                    .accessibilityLabel("Down a note")
                ComposeKey(systemImage: "arrow.up") { step(note, by: 1) }
                    .accessibilityLabel("Up a note")
                ComposeKey(title: "♭", isOn: alteration < 0) { alter(note, by: -1) }
                    .accessibilityLabel("Flat")
                ComposeKey(title: "Key", isOn: alteration == 0) { alter(note, by: 0) }
                    .accessibilityLabel("As in the key")
                ComposeKey(title: "♯", isOn: alteration > 0) { alter(note, by: 1) }
                    .accessibilityLabel("Sharp")
            }
            .padding(.horizontal, 16)

            HStack(spacing: 6) {
                ComposeKey(title: "Copy", systemImage: "doc.on.doc") {
                    copiedNote = note.pitch
                    showHint("Copied \(note.pitch.name). Paste it from above the note buttons.", symbol: "doc.on.doc")
                }
                ComposeKey(title: "Tie", systemImage: "link", isOn: composition.tiesForward(note)) {
                    var updated = composition
                    if updated.toggleTie(ofNoteAt: note.start) {
                        composition = updated
                    } else {
                        showHint("A tie joins the same note twice. A different one comes next.", symbol: "exclamationmark.circle")
                    }
                }
                .accessibilityHint("Holds the note on into the next one, over a barline too, so it's played once")
                ComposeKey(title: "Replace", systemImage: "arrow.triangle.2.circlepath") {
                    selection = nil
                    noteCursor = note.start
                    melodyValue = note.value
                }
                .accessibilityHint("Puts the cursor here so the next note you tap takes its place")
                ComposeKey(title: "Delete", systemImage: "trash", isDestructive: true) {
                    composition.removeNote(covering: note.start)
                    noteCursor = note.start
                }
            }
            .padding(.horizontal, 16)
        }
    }

    /// The guitar's range, low E to the top of the neck.
    private static let midiRange = 40...84

    /// Moves the note up or down the key's scale.
    private func step(_ note: Composition.MelodyNote, by steps: Int) {
        let target = note.pitch.diatonicNumber + steps
        let letter = ((target % 7) + 7) % 7
        setPitch(of: note, to: composition.keySignature.pitch(letter: letter, octave: (target - letter) / 7))
    }

    /// Flattens (−1) or sharpens (1) the note from what the key gives it, or puts it back (0).
    private func alter(_ note: Composition.MelodyNote, by alteration: Int) {
        let inKey = composition.keySignature.accidental(forLetter: note.pitch.letter)
        setPitch(of: note, to: SpelledPitch(letter: note.pitch.letter, accidental: max(-2, min(2, inKey + alteration)),
                                            octave: note.pitch.octave))
    }

    private func setPitch(of note: Composition.MelodyNote, to pitch: SpelledPitch) {
        guard Self.midiRange.contains(pitch.midi) else {
            return showHint("That's as far as the guitar goes.", symbol: "exclamationmark.circle")
        }
        composition.setPitch(ofNoteAt: note.start, to: pitch)
        if tapSounds && !player.isPlaying { CompositionPlayer.audition(pitch) }
    }

    private func measuresName(_ range: ClosedRange<Int>) -> String {
        range.count == 1 ? "Measure \(range.lowerBound + 1)" : "Measures \(range.lowerBound + 1)–\(range.upperBound + 1)"
    }

    /// The measures picked on the staff: copy, paste, repeat, insert, move, clear and delete.
    private func measuresPanel(_ range: ClosedRange<Int>) -> some View {
        let isEmpty = range.allSatisfy { composition.isMeasureEmpty($0) }
        return VStack(alignment: .leading, spacing: 8) {
            panelHeader(measuresName(range))

            HStack(spacing: 6) {
                ComposeKey(title: "Copy", systemImage: "doc.on.doc") {
                    clip = composition.clip(range)
                    showHint("Copied. Pick the measure to paste at, then tap Paste.", symbol: "doc.on.doc")
                }
                .disabled(isEmpty)
                ComposeKey(title: "Paste", systemImage: "doc.on.clipboard") {
                    guard let clip else { return }
                    if composition.pasteOverwrites(clip, at: range.lowerBound) {
                        confirmation = .paste(range.lowerBound)
                    } else {
                        paste(at: range.lowerBound)
                    }
                }
                .disabled(clip.map { !composition.canPaste($0, at: range.lowerBound) } ?? true)
                .accessibilityHint("Pastes the copied measures starting here")
                ComposeKey(title: "Repeat", systemImage: "repeat") {
                    if composition.repeatMeasures(range) {
                        selection = .measures((range.upperBound + 1)...(range.upperBound + range.count))
                    } else {
                        showFull()
                    }
                }
                .disabled(isEmpty)
                .accessibilityHint("Writes these measures again right after themselves")
            }
            .padding(.horizontal, 16)

            HStack(spacing: 6) {
                ComposeKey(title: "Insert", systemImage: "plus") {
                    if composition.insertMeasure(at: range.lowerBound) {
                        selection = .measures(range.lowerBound...range.lowerBound)
                    } else {
                        showFull()
                    }
                }
                .accessibilityHint("Adds an empty measure before these")
                ComposeKey(systemImage: "arrow.left") {
                    if let moved = composition.moveMeasures(range, by: -1) { selection = .measures(moved) }
                }
                .disabled(range.lowerBound == 0)
                .accessibilityLabel("Move earlier")
                ComposeKey(systemImage: "arrow.right") {
                    if let moved = composition.moveMeasures(range, by: 1) { selection = .measures(moved) }
                }
                .disabled(range.upperBound >= composition.measureCount - 1)
                .accessibilityLabel("Move later")
                ComposeKey(title: "Clear", systemImage: "eraser") { composition.clearMeasures(range) }
                    .disabled(isEmpty)
                    .accessibilityHint("Empties these measures and keeps them")
                ComposeKey(title: "Delete", systemImage: "trash", isDestructive: true) {
                    if isEmpty { deleteMeasures(range) } else { confirmation = .deleteMeasures(range) }
                }
                .disabled(composition.measureCount - range.count < Composition.measureRange.lowerBound)
                .accessibilityHint("Takes these measures out")
            }
            .padding(.horizontal, 16)
        }
    }

    private func showFull() {
        showHint("A composition can have \(Composition.measureRange.upperBound) measures at most.", symbol: "exclamationmark.circle")
    }

    private func paste(at measure: Int) {
        guard let clip, let filled = composition.paste(clip, at: measure) else { return }
        selection = .measures(filled)
    }

    private func deleteMeasures(_ range: ClosedRange<Int>) {
        selection = nil
        composition.deleteMeasures(range)
        pullCursorsBack()
    }

    private func shapeSheet(_ chord: CompositionChord) -> some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("\(chord.romanNumeral) in \(composition.keyName)")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                ChordShapesView(chord: chord, width: 170)
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity)
            .navigationTitle(chord.longName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { shapeChord = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Editing

    /// What the staff can do. It speaks in ticks (twelve to a beat) whichever line is being written.
    private var editing: CompositionStaffView.Editing {
        CompositionStaffView.Editing(
            // A tap on a chord or note picks it, to change; on an empty spot it moves the cursor there.
            onTap: { tick in
                selectedSlot = nil
                lastWritten = nil
                switch mode {
                case .chords:
                    let beat = tick / Composition.ticksPerBeat
                    if let chord = composition.chord(covering: beat), selection != .chord(chord.start) {
                        selection = .chord(chord.start)
                        audition(chord.symbol)
                    } else {
                        selection = nil
                        chordCursor = composition.chord(covering: beat)?.start ?? beat
                    }
                case .melody:
                    if let note = composition.note(covering: tick), selection != .note(note.start) {
                        selection = .note(note.start)
                        if tapSounds && !player.isPlaying { CompositionPlayer.audition(note.pitch) }
                    } else {
                        selection = nil
                        noteCursor = composition.note(covering: tick)?.start ?? entryTick(near: tick)
                    }
                }
            },
            // A measure number picks the measure; another then picks through to it.
            onTapMeasure: { measure in
                if case .measures(let range) = selection {
                    if range == measure...measure {
                        selection = nil
                    } else if range.contains(measure) {
                        selection = .measures(measure...measure)
                    } else {
                        selection = .measures(min(range.lowerBound, measure)...max(range.upperBound, measure))
                    }
                } else {
                    selection = .measures(measure...measure)
                }
            },
            onDrop: { tick, text in drop(text, at: tick) },
            onTargetChange: { targetedTick = $0 }
        )
    }

    /// Where the note cursor goes for a tap at `tick`: on the eighth, unless the length chosen
    /// is finer (a sixteenth, or a triplet, which goes on its third of the beat).
    private func entryTick(near tick: Int) -> Int {
        if melodyValue.isTriplet || composition.isTripletBeat(at: tick) { return composition.snapped(tick, for: .tripletEighth) }
        let step = melodyValue.ticks % 6 == 0 ? 6 : 3
        return tick / step * step
    }

    /// A chord or a note dropped on the staff cell starting at `tick`; either can go on either
    /// staff. The cursor moves on past it, as if it had been typed there.
    private func drop(_ text: String, at tick: Int) -> Bool {
        selection = nil
        if let symbol = ChordSymbol(dragText: text) {
            chordCursor = tick / Composition.ticksPerBeat
            selectedSlot = nil
            writeChord(symbol)
            return true
        }
        if let pitch = Self.pitch(fromDragText: text) {
            noteCursor = tick
            writeNote(pitch)
            return true
        }
        return false
    }

    private func audition(_ symbol: ChordSymbol) {
        guard tapSounds, !player.isPlaying else { return }
        CompositionPlayer.audition(composition.chord(symbol), style: playbackStyle)
    }

    /// The chord on palette button `slot`, written at the cursor; its versions show as chips.
    private func write(_ slot: PaletteSlot) {
        selectedSlot = slot
        writeChord(symbol(for: slot))
    }

    /// Writes `symbol` at the cursor for the chosen length (shortened to fit before the next
    /// chord or the barline) and moves the cursor past it. Past the end, it adds a measure first.
    private func writeChord(_ symbol: ChordSymbol, sounds: Bool = true) {
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
        if sounds { audition(symbol) }
        if beats < noteValue.beats, let fitted = NoteValue(beats: beats) {
            showHint("Shortened to a \(fitted.displayName.lowercased()) note to fit.")
        }
    }

    /// Writes `pitch` at the note cursor, like `writeChord`.
    private func writeNote(_ pitch: SpelledPitch, string: Int? = nil, sounds: Bool = true) {
        var updated = composition
        var tick = min(noteCursor, updated.totalTicks)
        if tick == updated.totalTicks {
            guard updated.measureCount < Composition.measureRange.upperBound else {
                return showHint("That's all \(Composition.measureRange.upperBound) measures. Tap the staff to write there.",
                                symbol: "exclamationmark.circle")
            }
            updated.setMeasureCount(updated.measureCount + 1)
        }
        tick = updated.snapped(tick, for: melodyValue)
        guard let fitted = updated.placeNote(pitch, at: tick, value: melodyValue, string: string) else { return }
        composition = updated
        noteCursor = tick + fitted.ticks
        if sounds && tapSounds && !player.isPlaying { CompositionPlayer.audition(pitch) }
        if fitted != melodyValue {
            showHint("Shortened to \(fitted.phrase) to fit.")
        }
    }

    /// A rest of the chosen length at the cursor (to the barline at most): what was there goes,
    /// and the cursor moves past it.
    private func writeRest() {
        lastWritten = nil
        selectedSlot = nil
        switch mode {
        case .chords:
            guard chordCursor < composition.totalBeats else { return showHint("That's the end. Tap a chord to add a measure.", symbol: "exclamationmark.circle") }
            let barline = (chordCursor / composition.beatsPerMeasure + 1) * composition.beatsPerMeasure
            let end = min(chordCursor + noteValue.beats, barline)
            composition.clearChords(from: chordCursor, to: end)
            chordCursor = end
        case .melody:
            guard noteCursor < composition.totalTicks else { return showHint("That's the end. Tap a note to add a measure.", symbol: "exclamationmark.circle") }
            let start = composition.snapped(noteCursor, for: melodyValue)
            let barline = (start / composition.ticksPerMeasure + 1) * composition.ticksPerMeasure
            let end = min(start + melodyValue.ticks, barline)
            composition.clearNotes(from: start, to: end)
            noteCursor = end
        }
    }

    /// Removes the chord (or note) just before the cursor and moves the cursor back to where it
    /// started; over a rest, just moves back a beat (in Melody an eighth, or a step of the finer
    /// length chosen).
    private func backspace() {
        lastWritten = nil
        selectedSlot = nil
        switch mode {
        case .chords:
            guard chordCursor > 0 else { return }
            if let chord = composition.chord(covering: chordCursor - 1) {
                composition.removeChord(covering: chord.start)
                chordCursor = chord.start
            } else {
                chordCursor -= 1
            }
        case .melody:
            guard noteCursor > 0 else { return }
            if let note = composition.note(covering: noteCursor - 1) {
                composition.removeNote(covering: note.start)
                noteCursor = note.start
            } else {
                noteCursor = entryTick(near: noteCursor - 1)
            }
        }
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

// MARK: - ComposeKey

/// A key on Compose's keyboard and panels: a rounded button that fills the room it's given.
private struct ComposeKey: View {
    var title: String? = nil
    var systemImage: String? = nil
    var isOn = false
    var isDestructive = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                }
                if let title {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .foregroundStyle(isOn ? Color.white : isDestructive ? Color.red : Color.primary)
            .opacity(isEnabled ? 1 : 0.35)
            .frame(maxWidth: .infinity, minHeight: 40)
            .padding(.horizontal, 2)
            .background(isOn ? Color.accentColor : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
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
/// each beat to invite something, the writing cursor (`cursorTick`) is marked, what's picked to
/// change (`selectedTicks`, `selectedMeasures`) is tinted, and each measure has its number
/// under it to tap. Without it, it's read-only (Play Along). Either way `chordColors` (by
/// start beat) and `noteColors` (by start eighth) tint chords and notes, and while a composition
/// plays, `playingMeasure` is lit and `playhead` sweeps through it.
struct CompositionStaffView: View {

    /// What the editor does with the staff. Places are in ticks (twelve to a beat) from the
    /// start of the piece, for chords and melody alike.
    struct Editing {
        /// The staff was tapped at this tick.
        var onTap: (Int) -> Void
        /// A measure's number tapped.
        var onTapMeasure: (Int) -> Void
        /// Drag text dropped on the cell starting at a tick; returns whether it was taken.
        var onDrop: (_ tick: Int, _ text: String) -> Bool
        /// The cell (by its first tick) a drag is over, or nil.
        var onTargetChange: (Int?) -> Void
    }

    let composition: Composition
    /// Edits go to the melody: the cells that take drops are eighths rather than beats.
    var editingMelody = false
    var chordColors: [Int: Color] = [:]
    var noteColors: [Int: Color] = [:]
    /// The cell (by its first tick) a drag is over.
    var targetedTick: Int? = nil
    /// The tick the next chord (or note) typed goes on, and how many ticks wide to mark it.
    var cursorTick: Int? = nil
    var cursorWidth = 6
    /// The ticks of the chord or note picked to change, and the measures picked.
    var selectedTicks: Range<Int>? = nil
    var selectedMeasures: ClosedRange<Int>? = nil
    var playingMeasure: Int? = nil
    var playhead: CompositionPlayer.Playhead? = nil
    /// With a melody, draw each chord's notes faded behind it (Compose Settings).
    var showsChordsUnderMelody = false
    /// With a melody, tablature under each line (Compose Settings).
    var showsTab = false
    /// Measures to a line, instead of two (one with a melody): the printed lead sheet's wider page.
    var measuresToALine: Int? = nil
    /// Only these measures, instead of all of them: one page of the lead sheet.
    var shownMeasures: Range<Int>? = nil
    var editing: Editing? = nil

    private let lineSpacing: CGFloat = 9

    /// Where across a measure of melody something on tick `tick` of it is drawn (0–1): by time,
    /// in from the barline by half an eighth, so a note on the beat sits where it always has
    /// and shorter ones fall in between. The tablature under the staff uses it too.
    static func position(ofTick tick: Int, in ticksPerMeasure: Int) -> CGFloat {
        (CGFloat(tick) + 3) / CGFloat(ticksPerMeasure)
    }

    /// The id of the line of staff `measure` is on, for scrolling to it.
    static func rowID(measure: Int, showsMelody: Bool) -> String {
        let perLine = showsMelody ? 1 : 2
        return "staff.line.\(measure / perLine * perLine)"
    }

    private var isEditable: Bool { editing != nil }
    /// Lead-sheet layout: the melody on the staff, chords as text.
    private var showsMelody: Bool { composition.hasMelody || editingMelody }
    private var measuresPerLine: Int { measuresToALine ?? (showsMelody ? 1 : 2) }
    /// Slots per measure the cells are cut into.
    private var cellTicks: Int { editingMelody ? 6 : Composition.ticksPerBeat }

    var body: some View {
        let key = composition.keySignature
        // Room between lines so one line's numerals don't run into the next line's chord names.
        VStack(spacing: 12) {
            let shown = shownMeasures?.clamped(to: 0..<composition.measureCount) ?? 0..<composition.measureCount
            ForEach(Array(stride(from: shown.lowerBound, to: shown.upperBound, by: measuresPerLine)), id: \.self) { first in
                let meter: Int? = first == 0 ? composition.beatsPerMeasure : nil
                let headerWidth = StaffView.headerWidth(keySignature: key, beatsPerMeasure: meter, lineSpacing: lineSpacing)
                let measures = first..<min(first + measuresPerLine, shown.upperBound)
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        StaffView(keySignature: key, columns: [], beatsPerMeasure: meter, lineSpacing: lineSpacing)
                            .frame(width: headerWidth)
                        ForEach(measures, id: \.self) { measure in
                            measureView(measure)
                        }
                        // A short last line keeps its measure the same width as on a full line.
                        ForEach(0..<(measuresPerLine - measures.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 120)
                    if showsTab && showsMelody && composition.hasMelody {
                        HStack(spacing: 0) {
                            Text("TAB")
                                .font(.system(size: 10, weight: .bold, design: .serif))
                                .foregroundStyle(.secondary)
                                .frame(width: headerWidth)
                                .accessibilityHidden(true)
                            ForEach(measures, id: \.self) { measure in
                                CompositionTabRow(composition: composition, measure: measure, noteColors: noteColors)
                            }
                            ForEach(0..<(measuresPerLine - measures.count), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    // The measures' numbers, to tap to pick whole measures.
                    if isEditable {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: headerWidth, height: 1)
                            ForEach(measures, id: \.self) { measure in
                                measureNumber(measure)
                            }
                            ForEach(0..<(measuresPerLine - measures.count), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                            }
                        }
                    }
                }
                .id(Self.rowID(measure: first, showsMelody: showsMelody))
            }
        }
    }

    // MARK: Measure

    private func measureNumber(_ measure: Int) -> some View {
        let isSelected = selectedMeasures?.contains(measure) ?? false
        return Button {
            editing?.onTapMeasure(measure)
        } label: {
            Text("\(measure + 1)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(minWidth: 44, minHeight: 26)
                .background(isSelected ? Color.accentColor : Color(.secondarySystemBackground), in: Capsule())
                .frame(maxWidth: .infinity, minHeight: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Measure \(measure + 1)")
        .accessibilityHint("Selects the measure to copy, move or delete it")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func measureView(_ measure: Int) -> some View {
        let ticks = composition.ticksPerMeasure
        let first = measure * ticks
        let emptyMeasure = composition.isMeasureEmpty(measure)
        return StaffView(keySignature: composition.keySignature,
                         columns: showsMelody ? melodyColumns(inMeasure: measure) : chordColumns(inMeasure: measure),
                         showsClef: false, showsKeySignature: false, showsEndBarline: true,
                         edgeToEdge: true, lineSpacing: lineSpacing, alignsLabels: true)
            .frame(maxWidth: .infinity)
            .background {
                // The measures picked, and the measure playing, lit.
                if selectedMeasures?.contains(measure) ?? false {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.12))
                        .padding(.vertical, 8)
                } else if playingMeasure == measure {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.08))
                        .padding(.vertical, 22)
                }
            }
            .overlay {
                if isEditable {
                    GeometryReader { geo in
                        let perTick = geo.size.width / CGFloat(ticks)
                        ZStack(alignment: .topLeading) {
                            HStack(spacing: 0) {
                                ForEach(Array(stride(from: first, to: first + ticks, by: cellTicks)), id: \.self) { tick in
                                    cell(at: tick, emptyMeasure: emptyMeasure)
                                }
                            }
                            // What's picked to change.
                            if let selected = selectedTicks?.clamped(to: first..<first + ticks), !selected.isEmpty {
                                // Around where it's drawn: a note shorter than an eighth sits past the end of its own time.
                                let inset = editingMelody ? max(0, 3 - CGFloat(selected.count) / 2) : 0
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.accentColor.opacity(0.18))
                                    .frame(width: perTick * max(CGFloat(selected.count), 3), height: geo.size.height - 12)
                                    .offset(x: perTick * (CGFloat(selected.lowerBound - first) + inset), y: 6)
                                    .allowsHitTesting(false)
                            }
                            // The cursor: a tinted slot with a bar at its start, where the next one typed goes.
                            if let cursorTick, (first..<first + ticks).contains(cursorTick) {
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.accentColor.opacity(0.14))
                                    Capsule()
                                        .fill(Color.accentColor)
                                        .frame(width: 3)
                                }
                                .frame(width: perTick * CGFloat(min(cursorWidth, first + ticks - cursorTick)), height: lineSpacing * 6)
                                .offset(x: perTick * (CGFloat(cursorTick - first) + (editingMelody ? max(0, 3 - CGFloat(cursorWidth) / 2) : 0)),
                                        y: (geo.size.height - lineSpacing * 6) / 2)
                                .allowsHitTesting(false)
                            } else if cursorTick == composition.totalTicks && measure == composition.measureCount - 1 {
                                // Past the end: the next one written adds a measure, so the cursor waits there.
                                Capsule()
                                    .fill(Color.accentColor)
                                    .frame(width: 3, height: lineSpacing * 6)
                                    .offset(x: geo.size.width + 1, y: (geo.size.height - lineSpacing * 6) / 2)
                                    .allowsHitTesting(false)
                            }
                        }
                        .contentShape(Rectangle())
                        // A tap is placed to the tick, so the shortest notes can be told apart.
                        .gesture(SpatialTapGesture().onEnded { tap in
                            // Where notes are shorter than an eighth, each is drawn a little past
                            // its own time, so a tap on one is read that much earlier.
                            let fine = editingMelody && composition.columnTicks(inMeasure: measure) < 6
                            let at = tap.location.x / max(perTick, 0.01) - (fine ? 1.5 : 0)
                            editing?.onTap(first + Int(max(0, min(at, CGFloat(ticks - 1)))))
                        })
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
                // One tied from the measure before is the same chord still sounding: no name again.
                let tiedOver = composition.isTiedOver(placed)
                return StaffColumn(id: beat, pitches: chord.pitches, value: placed.value,
                                   above: tiedOver ? nil : chord.name, below: tiedOver ? nil : chord.romanNumeral,
                                   color: chordColors[beat],
                                   accidentals: accidentals.printed(for: chord.pitches),
                                   tieToNext: composition.tiesForward(placed), tieFromPrevious: tiedOver && beat == first)
            }
            if let rest = rests.first(where: { $0.start == beat }) {
                return StaffColumn(id: beat, pitches: [], color: Color(.secondaryLabel), rest: rest.glyph)
            }
            return StaffColumn(id: beat, pitches: [])
        }
    }

    /// Lead sheet: the melody's notes and rests, the chords as text, in columns as fine as the
    /// measure needs (eighths, or sixteenths and thirds of a beat: see `columnTicks`).
    private func melodyColumns(inMeasure measure: Int) -> [StaffColumn] {
        let ticks = composition.ticksPerMeasure, perBeat = Composition.ticksPerBeat
        let first = measure * ticks
        let rests = composition.melodyRests(inMeasure: measure)
        let noMelody = rests.first?.glyph == .whole
        var accidentals = MeasureAccidentals(keySignature: composition.keySignature)
        return stride(from: first, to: first + ticks, by: composition.columnTicks(inMeasure: measure)).map { tick in
            var column = StaffColumn(id: tick, pitches: [])
            column.position = Self.position(ofTick: tick - first, in: ticks)
            if tick % perBeat == 0, let placed = composition.chords.first(where: { $0.start == tick / perBeat }) {
                let chord = composition.chord(placed.symbol)
                // One that's tied from the chord before is that chord held: its name in brackets.
                let held = composition.isTiedOver(placed)
                column.above = held ? "(\(chord.name))" : chord.name
                column.below = held ? nil : chord.romanNumeral
                column.aboveColor = chordColors[placed.start] ?? (held ? Color(.secondaryLabel) : nil)
                if showsChordsUnderMelody {
                    column.ghostPitches = chord.pitches
                    column.ghostValue = placed.value
                }
            }
            if let note = composition.melody.first(where: { $0.start == tick }) {
                column.pitches = [note.pitch]
                column.value = note.value
                column.color = noteColors[tick]
                column.accidentals = accidentals.printed(for: [note.pitch])
                column.tieToNext = composition.tiesForward(note)
                column.tieFromPrevious = tick == first && composition.isTiedOver(note)
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
            // The 3 goes over the middle of a triplet, note or rest.
            column.tuplet = tick % perBeat == 4 && composition.isTripletBeat(at: tick)
            return column
        }
    }

    // MARK: Cells (editor)

    /// A beat (an eighth, when writing melody) of the staff: takes drops, shows a + in an
    /// empty measure, and is what VoiceOver reads. Taps are taken by the measure, to the tick.
    private func cell(at tick: Int, emptyMeasure: Bool) -> some View {
        let perBeat = Composition.ticksPerBeat
        let chord = editingMelody ? nil : composition.chord(covering: tick / perBeat)
        let note = editingMelody ? composition.note(covering: tick) : nil
        let onBeat = tick % perBeat == 0
        let isCursor = cursorTick.map { (tick..<tick + cellTicks).contains($0) } ?? false
        return Rectangle()
            .fill(targetedTick == tick ? Color.accentColor.opacity(0.18) : Color.clear)
            .overlay {
                if emptyMeasure && onBeat && !isCursor {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                } else if emptyMeasure && editingMelody && !isCursor {
                    Circle().fill(Color(.tertiaryLabel)).frame(width: 3, height: 3)
                }
            }
            .dropDestination(for: String.self) { items, _ in
                guard let editing, let text = items.first else { return false }
                return editing.onDrop(tick, text)
            } isTargeted: { targeted in
                if targeted {
                    editing?.onTargetChange(tick)
                } else if targetedTick == tick {
                    editing?.onTargetChange(nil)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel(tick: tick, chord: chord, note: note))
            .accessibilityHint(chord != nil || note != nil ? "Selects it, to change it" : "Moves the cursor here")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { editing?.onTap(tick) }
    }

    private func accessibilityLabel(tick: Int, chord: Composition.PlacedChord?, note: Composition.MelodyNote?) -> String {
        let beats = composition.beatsPerMeasure, beat = tick / Composition.ticksPerBeat
        let place = "Measure \(beat / beats + 1), beat \(beat % beats + 1)\(tick % Composition.ticksPerBeat == 0 ? "" : " and")"
        if let chord {
            let spelled = composition.chord(chord.symbol)
            let what = "\(spelled.romanNumeral), \(spelled.longName), \(chord.value.displayName.lowercased())"
                + (composition.tiesForward(chord) ? ", tied to the next" : "")
            return chord.start == beat ? "\(place): \(what)" : "\(place): \(what) still ringing"
        }
        if editingMelody {
            // Every note that starts in this eighth: sixteenths and triplets share one.
            let starting = composition.melody.filter { (tick..<tick + cellTicks).contains($0.start) }
            if !starting.isEmpty {
                return "\(place): " + starting.map {
                    "\($0.pitch.name), \($0.value.displayName.lowercased())" + (composition.tiesForward($0) ? ", tied to the next" : "")
                }.joined(separator: ", then ")
            }
        }
        if let note { return "\(place): \(note.pitch.name), \(note.value.displayName.lowercased()) still ringing" }
        return "\(place): rest"
    }
}

#Preview {
    NavigationStack {
        CompositionListView()
    }
}
