//
//  BluesBuddyView.swift
//  Guitar Man
//
//  Blues Buddy: pick a key, a form (the 12-bar and its cousins, or one chord), a feel and a
//  tempo, or start from a preset, and it comps a blues on the nylon guitar for you to solo
//  over: a picked bass, chords here and there, and pentatonic fills, each with its own switch
//  and never the same twice (every Play is a new take: see BluesGroove). The Grooves button at
//  the top names the groove playing and opens the Grooves sheet (save it, pick one of yours or
//  a preset). Under it: the chord you're on and the next one, the form's bars with the one
//  playing lit, what to solo with (the minor or major pentatonic, the blues scale, or both
//  pentatonics at once, in one part of the neck; or Follow the Chords, which changes it bar by
//  bar), and the settings. In Trade Licks it plays a lick, each note lighting up on the
//  fretboard as it sounds, then comps while you answer; the card says whose turn it is. The
//  groove playing is remembered, and saved grooves are kept (SavedBluesGrooves).
//

import SwiftUI

struct BluesBuddyView: View {

    @State private var track = BackingTrack()
    @State private var groove: BluesGroove = SavedBluesGrooves.loadCurrent()
    @State private var saved: [SavedBlues] = SavedBluesGrooves.load()
    /// Names the take: a new one every time Play is tapped.
    @State private var seed = UInt64.random(in: 0...UInt64.max)
    @AppStorage("bluesBuddy.countIn") private var countsIn = true
    @AppStorage("bluesBuddy.click") private var clicks = false
    @AppStorage("bluesBuddy.position") private var position = 1
    @State private var showGrooves = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationContainer {
            ScrollView {
                VStack(spacing: 16) {
                    grooveHeader
                    // What you need while soloing: the chord you're on, where you are, and the scale.
                    nowPlaying
                    formChart
                    scaleCard
                    playsCard
                    settingsCard
                }
                .padding(.vertical, 12)
            }
            .safeAreaInset(edge: .bottom) { playBar }
            .navigationTitle("Blues Buddy")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showGrooves) {
                BluesGroovesSheet(groove: groove, saved: $saved) { picked in
                    withAnimation(.easeInOut(duration: 0.2)) { groove = picked }
                }
            }
            .onAppear {
                track.groove = BluesBacking(groove: groove, seed: seed, position: position)
                track.countsIn = countsIn
                track.clicks = clicks
            }
            .onDisappear { track.stop() }
            .onChange(of: groove) { _, updated in
                // Changed from its preset: it's no longer that preset.
                if let preset = BluesPreset.preset(updated.presetID), !preset.groove.sameMusic(as: updated) {
                    groove.presetID = nil
                }
                track.groove = BluesBacking(groove: updated, seed: seed, position: position)
                SavedBluesGrooves.storeCurrent(updated)
            }
            // Licks are played where the fretboard shows them.
            .onChange(of: position) {
                track.groove = BluesBacking(groove: groove, seed: seed, position: position)
            }
            .onChange(of: saved) { _, updated in SavedBluesGrooves.store(updated) }
            .onChange(of: countsIn) { track.countsIn = countsIn }
            .onChange(of: clicks) { track.clicks = clicks }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { track.stop() }
            }
        }
    }

    // MARK: - Grooves

    /// The groove playing, and the button to the Grooves sheet (saving, yours, presets).
    private var grooveHeader: some View {
        Button {
            showGrooves = true
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(BluesGroovesSheet.name(of: groove, saved: saved))
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if BluesGroovesSheet.hasUnsavedChanges(groove, saved: saved) {
                            Text("Edited")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.tertiarySystemFill), in: Capsule())
                        }
                    }
                    Text(BluesGroovesSheet.detail(of: groove))
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Label("Grooves", systemImage: "square.stack.fill")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Color.accentColor, in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityLabel("Grooves. Playing \(BluesGroovesSheet.name(of: groove, saved: saved)), \(BluesGroovesSheet.detail(of: groove))")
        .accessibilityHint("Save this groove or pick another")
    }

    // MARK: - Now playing

    private var nowPlaying: some View {
        let barIndex = track.bar ?? 0
        let current = groove.chord(forBar: barIndex)
        let next = groove.chord(forBar: barIndex + 1)
        return VStack(spacing: 8) {
            if track.isCountingIn {
                Text("\(track.beat + 1)")
                    .font(.system(size: 46, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("Get ready…")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(current.name)
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                    Text(current.romanNumeral)
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(.secondary)
                }
                Text(groove.barCount > 1 ? "Next: \(next.name)" : "One chord: make it sing")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .opacity(track.isPlaying || groove.barCount <= 1 ? 1 : 0.6)
            }
            turnBanner
            beatDots
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    /// Trade Licks: whose turn it is, and how long is left of it.
    @ViewBuilder
    private var turnBanner: some View {
        if groove.mode == .trade {
            let bar: Int? = track.isPlaying && !track.isCountingIn ? track.bar : nil
            let turn: BluesGroove.Turn? = bar.flatMap { groove.turn(atBar: $0) }
            let barsLeft = bar.map { groove.turnStart(ofBar: $0) + groove.tradeBars - $0 } ?? 0
            Text(turnText(turn, barsLeft: barsLeft))
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(turn == .you ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(turn == .you ? Color.orange : Color(.tertiarySystemFill), in: Capsule())
                .animation(.easeOut(duration: 0.15), value: turn)
        }
    }

    private func turnText(_ turn: BluesGroove.Turn?, barsLeft: Int) -> String {
        switch turn {
        case .some(.buddy):
            return barsLeft > 1 ? "Buddy's lick · your turn in \(barsLeft) bars" : "Buddy's lick · you're next"
        case .some(.you):
            return barsLeft > 1 ? "Your turn · \(barsLeft) bars left" : (groove.tradeBars > 1 ? "Your turn · last bar" : "Your turn")
        case .none:
            return "Buddy plays first, then it's your turn"
        }
    }

    private var beatDots: some View {
        HStack(spacing: 10) {
            ForEach(0..<BluesGroove.beatsPerBar, id: \.self) { beat in
                Circle()
                    .fill(track.isPlaying && track.beat == beat
                          ? (beat == 0 ? Color.orange : Color.accentColor)
                          : Color(.systemGray4))
                    .frame(width: 12, height: 12)
            }
        }
        .padding(.top, 4)
        .animation(.easeOut(duration: 0.08), value: track.beat)
        .accessibilityHidden(true)
    }

    // MARK: - Form

    /// The form's bars in lines of four, the one playing lit (nothing to chart on one chord).
    @ViewBuilder
    private var formChart: some View {
        let chords = groove.chords
        if chords.count > 1 {
            let playing: Int? = track.isPlaying && !track.isCountingIn ? track.bar.map({ groove.index(ofBar: $0) }) : nil
            VStack(spacing: 6) {
                ForEach(Array(stride(from: 0, to: chords.count, by: 4)), id: \.self) { lineStart in
                    HStack(spacing: 6) {
                        ForEach(lineStart..<min(lineStart + 4, chords.count), id: \.self) { index in
                            let chord = chords[index]
                            let isOn = playing == index
                            VStack(spacing: 1) {
                                Text(chord.name)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.6)
                                Text(chord.romanNumeral)
                                    .font(.system(size: 11, weight: .semibold, design: .serif))
                                    .foregroundStyle(isOn ? .white.opacity(0.85) : .secondary)
                            }
                            .foregroundStyle(isOn ? .white : .primary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(isOn ? Color.accentColor : Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(groove.form.displayName) blues: " + chords.map(\.name).joined(separator: ", "))
        }
    }

    // MARK: - Scale

    /// The bar the fretboard shows: the one playing, or the first while stopped.
    private var shownBar: Int {
        track.isPlaying && !track.isCountingIn ? track.bar ?? 0 : 0
    }

    /// The neck is drawn to the highest fret any position's area reaches (and the fret or two
    /// a neighbouring box adds), so it keeps one width whatever shows.
    private var neckFrets: Int {
        let highest = (1...allPentatonicShapes.count).map { groove.area(position: $0).maxFret + 2 }.max() ?? 12
        return max(highest, 12)
    }

    /// The dots that aren't the usual indigo (or the root's orange).
    private func colors(for board: BluesFretboard) -> [FretboardPosition: Color] {
        var colors: [FretboardPosition: Color] = [:]
        for (dot, mark) in board.marks {
            switch mark {
            case .root, .tone: break
            case .minorOnly:   colors[dot] = .blue
            case .majorOnly:   colors[dot] = .green
            case .blueNote:    colors[dot] = .teal
            }
        }
        return colors
    }

    private func legend(for shown: BluesGroove.ScaleChoice) -> String {
        switch shown.scale {
        case .minor, .major:
            return "Orange dots are the root, \(shown.rootName)."
        case .blues:
            return "Orange dots are the root, \(shown.rootName). Teal dots are the ♭5, the blue note: pass through it on the way to the 4th or the 5th."
        case .both:
            return "The numbers are scale degrees, 1 being \(shown.rootName). Blue dots are in the minor pentatonic only, green in the major only. The ♭3 and the 3 sit a fret apart: that's the switch."
        }
    }

    private var scaleCard: some View {
        let shown = groove.shownScale(forBar: shownBar)
        let board = groove.fretboard(position: position, bar: shownBar)
        // Buddy's lick lights up note by note.
        var dotColors = colors(for: board)
        if let cue = track.cue { dotColors[BluesBacking.position(forCue: cue)] = .pink }
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(groove.followsChords ? "Following the chords" : "Solo with")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(shown.name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 20)

            // A minor blues wants the minor pentatonic or the blues scale: the major
            // pentatonic's 3rd fights its chords.
            Picker("Scale", selection: $groove.scale) {
                ForEach(groove.isMinor ? BluesScale.forMinorBlues : BluesScale.allCases) { scale in
                    Text(scale.displayName).tag(scale)
                }
            }
            .pickerStyle(.segmented)
            .disabled(groove.followsChords)
            .padding(.horizontal, 20)

            followControls
                .padding(.horizontal, 20)

            HStack {
                // The frets here too: the numbers under the neck can be out of sight.
                VStack(alignment: .leading, spacing: 1) {
                    Text("Position")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("Frets \(board.frets.lowerBound)–\(board.frets.upperBound)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: board.frets.lowerBound)
                }
                Spacer()
                Picker("Position", selection: $position) {
                    ForEach(1...allPentatonicShapes.count, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                .accessibilityLabel("Position on the neck")
            }
            .padding(.horizontal, 20)

            FretboardView(
                highlightedPositions: Set(board.marks.keys),
                rootPositions: board.roots,
                maxFret: neckFrets,
                showHighlightedLabels: true,
                keyContext: FretboardView.KeyContext(root: board.root, isMinor: board.spellsAsMinor),
                customLabels: board.labels,
                customColors: dotColors,
                focusFrets: board.focus
            )
            .frame(height: 280)
            .padding(.horizontal, 8)
            .animation(.easeInOut(duration: 0.3), value: position)

            Text(legend(for: shown) + (groove.mode == .trade ? " Buddy's lick lights up in pink as it sounds." : ""))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
        }
    }

    /// Follow the Chords, and the rule it follows by (a minor blues has only the one).
    private var followControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $groove.followsChords) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Follow the Chords")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("The fretboard changes scale as the chords go by.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if groove.followsChords {
                if !groove.isMinor {
                    HStack {
                        Text("Rule").font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                        Picker("Rule", selection: $groove.followRule) {
                            ForEach(BluesFollowRule.allCases) { rule in
                                Text(rule.displayName).tag(rule)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                Text(groove.form == .vamp
                     ? "On one chord there's nothing to follow: pick a form with changes."
                     : groove.activeFollowRule.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - What it plays

    /// Jam Along or Trade Licks, and the switches for what Buddy plays. The last one on can't
    /// be switched off: something has to play. Trading, the licks take the fills' place.
    private var playsCard: some View {
        let trading = groove.mode == .trade
        let onCount = (trading ? [groove.bassPicking, groove.chordStabs]
                               : [groove.bassPicking, groove.chordStabs, groove.fills]).filter { $0 }.count
        return VStack(alignment: .leading, spacing: 12) {
            Picker("Mode", selection: Binding(
                get: { groove.mode },
                set: { mode in
                    groove.mode = mode
                    // Something has to comp while you answer.
                    if mode == .trade && !groove.bassPicking && !groove.chordStabs { groove.bassPicking = true }
                }
            )) {
                ForEach(BluesMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Text(trading
                 ? "Buddy plays a lick, then comps while you answer it. Its notes light up on the fretboard as they sound."
                 : "Buddy comps and throws in fills while you solo.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, -6)

            if trading {
                HStack {
                    Text("Each Turn").font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Picker("Bars each turn", selection: $groove.tradeBars) {
                        ForEach(BluesGroove.tradeLengths, id: \.self) { bars in
                            Text(bars == 1 ? "1 Bar" : "\(bars) Bars").tag(bars)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }
            }

            Divider()
            Text(trading ? "Buddy Comps With" : "Buddy Plays")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            playsToggle("Bass Picking", "A boogie, a walk or a steady thumb that keeps the time.",
                        isOn: $groove.bassPicking, isLastOn: onCount == 1 && groove.bassPicking)
            playsToggle("Chord Stabs", "A full chord or a triad, dropped in here and there.",
                        isOn: $groove.chordStabs, isLastOn: onCount == 1 && groove.chordStabs)
            if !trading {
                playsToggle("Fills", "Short pentatonic licks, mostly at the ends of lines.",
                            isOn: $groove.fills, isLastOn: onCount == 1 && groove.fills)
            }
            Text("It's different every time you tap Play.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private func playsToggle(_ title: String, _ detail: String, isOn: Binding<Bool>, isLastOn: Bool) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isLastOn)
    }

    // MARK: - Settings

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Key").font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Picker("Key", selection: $groove.keyRoot) {
                    ForEach(Note.circleOfFifthsKeys(asMinor: groove.isMinor)) { note in
                        Text(keyLabel(note)).tag(note)
                    }
                }
                .pickerStyle(.menu)
            }

            HStack {
                Text("Form").font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Picker("Form", selection: Binding(
                    get: { groove.form },
                    set: { form in
                        groove.form = form
                        if form.isMinor && !BluesScale.forMinorBlues.contains(groove.scale) { groove.scale = .minor }
                    }
                )) {
                    ForEach(BluesForm.allCases) { form in
                        Text(form.displayName).tag(form)
                    }
                }
                .pickerStyle(.menu)
            }
            Text(groove.form.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, -8)

            HStack {
                Text("Feel").font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Picker("Feel", selection: Binding(
                    get: { groove.feel },
                    set: { feel in
                        groove.feel = feel
                        groove.bpm = feel.defaultBPM
                    }
                )) {
                    ForEach(BluesFeel.allCases) { feel in
                        Text(feel.displayName).tag(feel)
                    }
                }
                .pickerStyle(.menu)
            }
            Text(groove.feel.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, -8)

            HStack(spacing: 10) {
                Text("Tempo").font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(groove.bpm)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("BPM")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Stepper("Tempo", value: $groove.bpm, in: BluesGroove.tempoRange, step: 5)
                    .labelsHidden()
                    .accessibilityValue("\(groove.bpm) beats per minute")
            }

            Divider()
            Toggle("Count In", isOn: $countsIn)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Toggle("Click", isOn: $clicks)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    /// The key's tonic as it's spelled in the key: "B♭".
    private func keyLabel(_ note: Note) -> String {
        var key = groove
        key.keyRoot = note
        return key.tonicName
    }

    // MARK: - Play

    private var playBar: some View {
        Button {
            if track.isPlaying {
                track.stop()
            } else {
                // A new take.
                seed = UInt64.random(in: 0...UInt64.max)
                track.groove = BluesBacking(groove: groove, seed: seed, position: position)
                track.start()
            }
        } label: {
            Label(track.isPlaying ? "Stop" : "Play", systemImage: track.isPlaying ? "stop.fill" : "play.fill")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(track.isPlaying ? Color.red.opacity(0.85) : Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

// MARK: - BluesGroovesSheet

/// The Grooves sheet: the groove playing (save it, or save changes to one you saved), your
/// saved grooves (swipe to rename or delete), and the presets. Picking one plays it.
private struct BluesGroovesSheet: View {

    let groove: BluesGroove
    @Binding var saved: [SavedBlues]
    let onPick: (BluesGroove) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Naming: Equatable {
        case new
        case rename(UUID)
    }

    @State private var naming: Naming? = nil
    @State private var nameDraft = ""
    @State private var deleting: SavedBlues? = nil

    // MARK: Names

    /// Its saved name, its preset's, or "My Blues".
    static func name(of groove: BluesGroove, saved: [SavedBlues]) -> String {
        if let id = groove.savedID, let mine = saved.first(where: { $0.id == id }) { return mine.name }
        return BluesPreset.preset(groove.presetID)?.name ?? "My Blues"
    }

    /// "A · 12-Bar · Shuffle · 95 BPM".
    static func detail(of groove: BluesGroove) -> String {
        "\(groove.keyName) · \(groove.form.displayName) · \(groove.feel.displayName) · \(groove.bpm) BPM"
    }

    /// Opened from a saved groove and changed since.
    static func hasUnsavedChanges(_ groove: BluesGroove, saved: [SavedBlues]) -> Bool {
        guard let id = groove.savedID, let mine = saved.first(where: { $0.id == id }) else { return false }
        return !mine.groove.sameMusic(as: groove)
    }

    /// "Bass, chords and fills", or trading, "Bass, chords and licks".
    static func playsList(_ groove: BluesGroove) -> String {
        let plays = groove.plays
        let parts = [plays.bass ? "bass" : nil, plays.stabs ? "chords" : nil, plays.fills ? "fills" : nil,
                     groove.mode == .trade ? "licks" : nil].compactMap { $0 }
        let list = parts.count > 1 ? parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "") : parts.first ?? ""
        return list.prefix(1).uppercased() + String(list.dropFirst())
    }

    private var current: SavedBlues? {
        groove.savedID.flatMap { id in saved.first { $0.id == id } }
    }

    private var hasChanges: Bool { Self.hasUnsavedChanges(groove, saved: saved) }

    // MARK: Body

    var body: some View {
        NavigationStack {
            List {
                playingNow
                mine
                Section("Blues") {
                    ForEach(BluesPreset.all) { preset in
                        row(title: preset.name, subtitle: preset.detail, detail: Self.detail(of: preset.groove),
                            isOn: groove.presetID == preset.id) {
                            play(preset.groove)
                        }
                    }
                }
            }
            .navigationTitle("Grooves")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(namingTitle, isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
                TextField("Name", text: $nameDraft)
                Button("Save") { finishNaming() }
                Button("Cancel", role: .cancel) { }
            }
            .confirmationDialog(deleting.map { "Delete \u{201C}\($0.name)\u{201D}?" } ?? "",
                                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let deleting { saved.removeAll { $0.id == deleting.id } }
                }
            }
        }
    }

    private var playingNow: some View {
        Section {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(Self.name(of: groove, saved: saved))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    if hasChanges {
                        Text("Edited")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                }
                Text(Self.playsList(groove))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                Text(Self.detail(of: groove))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)

            if let current, hasChanges {
                Button {
                    update(current)
                } label: {
                    Label("Save Changes to \u{201C}\(current.name)\u{201D}", systemImage: "square.and.arrow.down")
                }
            }
            if current == nil || hasChanges {
                Button {
                    startNaming(.new)
                } label: {
                    Label(current == nil ? "Save This Groove…" : "Save as a New Groove…", systemImage: "plus.square.on.square")
                }
            }
        } header: {
            Text("Playing Now")
        }
    }

    private var mine: some View {
        Section {
            if saved.isEmpty {
                Text("Grooves you save show up here, ready to play.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(saved) { item in
                row(title: item.name, subtitle: Self.playsList(item.groove), detail: Self.detail(of: item.groove),
                    isOn: groove.savedID == item.id) {
                    play(item.playable)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleting = item
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        startNaming(.rename(item.id))
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    .tint(.indigo)
                }
                .contextMenu {
                    Button {
                        startNaming(.rename(item.id))
                    } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        deleting = item
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("My Grooves")
        } footer: {
            if !saved.isEmpty { Text("Swipe left on one to rename or delete it.") }
        }
    }

    private func row(title: String, subtitle: String, detail: String, isOn: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: Actions

    private func play(_ next: BluesGroove) {
        onPick(next)
        dismiss()
    }

    private var namingTitle: String {
        if case .rename = naming { return "Rename Groove" }
        return "Save Groove"
    }

    private func startNaming(_ what: Naming) {
        switch what {
        case .new:
            let base = groove.presetID != nil || current != nil ? Self.name(of: groove, saved: saved) : "My Blues"
            nameDraft = SavedBluesGrooves.unusedName(base, in: saved)
        case .rename(let id):
            nameDraft = saved.first { $0.id == id }?.name ?? ""
        }
        naming = what
    }

    private func finishNaming() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let what = naming else { return }
        switch what {
        case .new:
            var music = groove
            music.savedID = nil
            music.presetID = nil
            let item = SavedBlues(name: name, groove: music)
            saved.insert(item, at: 0)
            // The groove playing is now that saved one.
            onPick(item.playable)
        case .rename(let id):
            if let index = saved.firstIndex(where: { $0.id == id }) { saved[index].name = name }
        }
    }

    private func update(_ item: SavedBlues) {
        guard let index = saved.firstIndex(where: { $0.id == item.id }) else { return }
        var music = groove
        music.savedID = nil
        music.presetID = nil
        saved[index].groove = music
        saved[index].savedAt = .now
        saved.sort { $0.savedAt > $1.savedAt }
    }
}

#Preview {
    NavigationStack { BluesBuddyView() }
}
