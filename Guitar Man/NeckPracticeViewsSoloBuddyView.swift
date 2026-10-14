//
//  SoloBuddyView.swift
//  Guitar Man
//
//  Solo Buddy: pick a key, one to four chords (or the 12-bar blues), a style and a tempo, or
//  start from a preset, and it plays a backing to solo over on the nylon guitar. The card at the
//  top shows the chord you're on and the next one; the fretboard under it shows the pentatonic
//  box to solo with, any of its five positions; chords and settings come after. Chords are Roman numerals (as in
//  Compose), so a preset or your own progression plays in any key. The groove is remembered.
//

import SwiftUI

struct SoloBuddyView: View {

    private static let storageKey = "soloBuddy.groove"

    @State private var track = BackingTrack()
    @State private var groove: SoloGroove = SoloBuddyView.loadGroove()
    @AppStorage("soloBuddy.countIn") private var countsIn = true
    @AppStorage("soloBuddy.click") private var clicks = false
    @AppStorage("soloBuddy.position") private var position = 1
    @State private var showPresets = false
    /// The chord slot being picked (an index, or `chords.count` for a new one).
    @State private var pickingSlot: Int? = nil
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationContainer {
            ScrollView {
                VStack(spacing: 16) {
                    // What you need while soloing first: the chord you're on and the box.
                    nowPlaying
                    scaleCard
                    chordRow
                    settingsCard
                }
                .padding(.vertical, 12)
            }
            .safeAreaInset(edge: .bottom) { playBar }
            .navigationTitle("Solo Buddy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showPresets = true
                    } label: {
                        Label("Presets", systemImage: "music.note.list")
                    }
                }
            }
            .sheet(isPresented: $showPresets) {
                SoloPresetList { preset in
                    groove = preset.groove
                    showPresets = false
                }
            }
            .sheet(item: Binding(get: { pickingSlot.map(ChordSlot.init) }, set: { pickingSlot = $0?.index })) { slot in
                SoloChordPicker(groove: groove, slot: slot.index) { symbol in
                    setChord(symbol, at: slot.index)
                } onRemove: {
                    removeChord(at: slot.index)
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                track.groove = groove
                track.countsIn = countsIn
                track.clicks = clicks
            }
            .onDisappear { track.stop() }
            .onChange(of: groove) { _, updated in
                track.groove = updated
                if let data = try? JSONEncoder().encode(updated) {
                    UserDefaults.standard.set(data, forKey: Self.storageKey)
                }
            }
            .onChange(of: countsIn) { track.countsIn = countsIn }
            .onChange(of: clicks) { track.clicks = clicks }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { track.stop() }
            }
        }
    }

    private static func loadGroove() -> SoloGroove {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let groove = try? JSONDecoder().decode(SoloGroove.self, from: data) {
            return groove
        }
        return SoloPreset.all[0].groove
    }

    private struct ChordSlot: Identifiable {
        let index: Int
        var id: Int { index }
    }

    // MARK: - Now playing

    private var nowPlaying: some View {
        let bars = groove.bars
        let barIndex = track.bar ?? 0
        let current = groove.chord(groove.symbol(forBar: barIndex))
        let next = groove.chord(groove.symbol(forBar: barIndex + 1))
        let presetName = SoloPreset.preset(groove.presetID)?.name
        return VStack(spacing: 8) {
            Text(presetName.map { "\($0) · \(groove.keyName)" } ?? groove.keyName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if track.isCountingIn {
                Text("\(track.beat + 1)")
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("Get ready…")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(current.name)
                        .font(.system(size: 54, weight: .bold, design: .rounded))
                    Text(current.romanNumeral)
                        .font(.system(size: 22, weight: .bold, design: .serif))
                        .foregroundStyle(.secondary)
                }
                Text(bars.count > 1 ? "Next: \(next.name)" : "One chord: make it sing")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .opacity(track.isPlaying || bars.count <= 1 ? 1 : 0.6)
            }
            beatDots
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }

    private var beatDots: some View {
        HStack(spacing: 10) {
            ForEach(0..<groove.beatsPerBar, id: \.self) { beat in
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

    // MARK: - Chords

    private var chordRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(groove.form == .twelveBar ? "12-Bar Blues" : "Chords")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Picker("Form", selection: Binding(
                    get: { groove.form },
                    set: { form in
                        groove.form = form
                        groove.presetID = nil
                    }
                )) {
                    Text("My Chords").tag(SoloForm.loop)
                    Text("12-Bar Blues").tag(SoloForm.twelveBar)
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            }

            if groove.form == .twelveBar {
                twelveBarChart
            } else {
                HStack(spacing: 8) {
                    ForEach(Array(groove.chords.prefix(4).enumerated()), id: \.offset) { index, symbol in
                        chordChip(symbol, isCurrent: isCurrent(slot: index)) {
                            pickingSlot = index
                        }
                        .contextMenu {
                            if groove.chords.count > 1 {
                                Button(role: .destructive) {
                                    removeChord(at: index)
                                } label: {
                                    Label("Remove Chord", systemImage: "trash")
                                }
                            }
                        }
                    }
                    if groove.chords.count < SoloGroove.chordRange.upperBound {
                        Button {
                            pickingSlot = groove.chords.count
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 18, weight: .semibold))
                                .frame(maxWidth: .infinity, minHeight: 58)
                                .background(Color(.tertiarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Add a chord")
                    }
                }
                Text("Tap a chord to change it. Long-press to remove it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
    }

    /// The 12 bars in three lines of four, the one playing lit.
    private var twelveBarChart: some View {
        let bars = groove.bars
        let playing = track.bar.map { $0 % bars.count }
        return VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { line in
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { column in
                        let index = line * 4 + column
                        let chord = groove.chord(bars[index])
                        let isOn = track.isPlaying && playing == index
                        VStack(spacing: 1) {
                            Text(chord.name)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Twelve-bar blues: " + bars.map { groove.chord($0).name }.joined(separator: ", "))
    }

    private func isCurrent(slot: Int) -> Bool {
        guard track.isPlaying, !track.isCountingIn, let bar = track.bar else { return false }
        let barsPerChord = min(max(groove.barsPerChord, 1), 2)
        return (bar % max(groove.bars.count, 1)) / barsPerChord == slot
    }

    private func chordChip(_ symbol: ChordSymbol, isCurrent: Bool, action: @escaping () -> Void) -> some View {
        let chord = groove.chord(symbol)
        return Button(action: action) {
            VStack(spacing: 2) {
                Text(chord.name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(chord.romanNumeral)
                    .font(.system(size: 12, weight: .semibold, design: .serif))
                    .foregroundStyle(isCurrent ? .white.opacity(0.85) : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(isCurrent ? .white : .primary)
            .frame(maxWidth: .infinity, minHeight: 58)
            .padding(.horizontal, 2)
            .background(isCurrent ? Color.accentColor : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chord.romanNumeral), \(chord.longName)")
        .accessibilityHint("Tap to change it")
    }

    private func setChord(_ symbol: ChordSymbol, at index: Int) {
        if index < groove.chords.count {
            groove.chords[index] = symbol
        } else if groove.chords.count < SoloGroove.chordRange.upperBound {
            groove.chords.append(symbol)
        }
        groove.presetID = nil
        pickingSlot = nil
    }

    private func removeChord(at index: Int) {
        guard groove.chords.count > 1, groove.chords.indices.contains(index) else { return }
        groove.chords.remove(at: index)
        groove.presetID = nil
        pickingSlot = nil
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
                Picker("Scale", selection: Binding(
                    get: { groove.isMinor },
                    set: { minor in
                        groove.isMinor = minor
                        groove.scale = minor ? .minor : .major
                        groove.presetID = nil
                    }
                )) {
                    Text("Major").tag(false)
                    Text("Minor").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            HStack {
                Text("Style").font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Picker("Style", selection: Binding(
                    get: { groove.style },
                    set: { style in
                        groove.style = style
                        groove.bpm = style.defaultBPM
                    }
                )) {
                    ForEach(BackingStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.menu)
            }
            Text(groove.style.detail)
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
                Stepper("Tempo", value: $groove.bpm, in: SoloGroove.tempoRange, step: 5)
                    .labelsHidden()
                    .accessibilityValue("\(groove.bpm) beats per minute")
            }

            if groove.form == .loop {
                HStack {
                    Text("Each Chord").font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                    Picker("Bars per chord", selection: $groove.barsPerChord) {
                        Text("1 Bar").tag(1)
                        Text("2 Bars").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
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

    private func keyLabel(_ note: Note) -> String {
        let key = KeySignature(root: note, isMinor: groove.isMinor)
        let name = groove.isMinor ? key.minorKeyName : key.majorKeyName
        return name.components(separatedBy: " ").first ?? name
    }

    // MARK: - Scale

    private var box: PentatonicQuestion {
        let index = min(max(position, 1), allPentatonicShapes.count) - 1
        return PentatonicQuestion(shape: allPentatonicShapes[index], quality: groove.scale, key: groove.keyRoot)
    }

    private var scaleCard: some View {
        let box = self.box
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Solo with")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(groove.scaleName)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }
                Spacer()
                Picker("Pentatonic", selection: $groove.scale) {
                    Text("Minor").tag(PentatonicQuality.minor)
                    Text("Major").tag(PentatonicQuality.major)
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            .padding(.horizontal, 20)

            HStack {
                Text("Position")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Picker("Position", selection: $position) {
                    ForEach(1...allPentatonicShapes.count, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
                .accessibilityLabel("Pentatonic box position")
            }
            .padding(.horizontal, 20)

            FretboardView(
                highlightedPositions: Set(box.shapePositions),
                rootPositions: box.effectiveRootPositions,
                maxFret: max(box.maxFret, 5),
                showHighlightedLabels: true,
                keyContext: FretboardView.KeyContext(root: box.effectiveRootNote, isMinor: groove.scale.isMinor)
            )
            .frame(height: 280)
            .padding(.horizontal, 8)
            .animation(.easeInOut(duration: 0.3), value: position)

            Text("Orange dots are the root, \(groove.tonicName). Frets \(box.minFret)–\(box.maxFret).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Play

    private var playBar: some View {
        Button {
            track.isPlaying ? track.stop() : track.start()
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

// MARK: - SoloChordPicker

/// Pick a chord for a slot: the key's chords, their 7ths, and borrowed and secondary chords.
private struct SoloChordPicker: View {

    let groove: SoloGroove
    let slot: Int
    let onPick: (ChordSymbol) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var current: ChordSymbol? {
        groove.chords.indices.contains(slot) ? groove.chords[slot] : nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("Chords in \(groove.keyName)", (1...7).map { ChordSymbol(degree: $0) })
                    section("7th Chords", (1...7).map { ChordSymbol(degree: $0, kind: .seventh) })
                    section("Bluesy 7ths", bluesy)
                    section("Borrowed & Secondary", CompositionChord.borrowed(isMinor: groove.isMinor).flatMap { [$0.chord, $0.seventh] })
                    if current != nil && groove.chords.count > 1 {
                        Button(role: .destructive) {
                            onRemove()
                        } label: {
                            Label("Remove This Chord", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                    }
                }
                .padding(20)
            }
            .navigationTitle(current == nil ? "Add a Chord" : "Change Chord \(slot + 1)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// Dominant 7ths on I and IV (the blues), and in minor the major V and V7.
    private var bluesy: [ChordSymbol] {
        (groove.isMinor ? [ChordSymbol(degree: 5, kind: .major), ChordSymbol(degree: 5, kind: .dominant7)] : [])
            + [ChordSymbol(degree: 1, kind: .dominant7), ChordSymbol(degree: 4, kind: .dominant7)]
    }

    private func section(_ title: String, _ symbols: [ChordSymbol]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    let chord = groove.chord(symbol)
                    let isCurrent = symbol == current
                    Button {
                        onPick(symbol)
                    } label: {
                        VStack(spacing: 1) {
                            Text(chord.romanNumeral)
                                .font(.system(size: 15, weight: .bold, design: .serif))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(chord.name)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(isCurrent ? .white.opacity(0.85) : .secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(isCurrent ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .padding(.horizontal, 2)
                        .background(isCurrent ? Color.accentColor : Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(chord.longName)
                }
            }
        }
    }
}

// MARK: - SoloPresetList

private struct SoloPresetList: View {

    let onPick: (SoloPreset) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(SoloPreset.Group.allCases, id: \.self) { group in
                    Section {
                        ForEach(SoloPreset.all.filter { $0.group == group }) { preset in
                            Button {
                                onPick(preset)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(preset.name)
                                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        Spacer()
                                        Text(preset.groove.style.displayName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(preset.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("\(preset.groove.keyName) · \(preset.groove.bpm) BPM · solo with \(preset.groove.scaleName)")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 2)
                            }
                            .foregroundStyle(.primary)
                        }
                    } header: {
                        Text(group.rawValue)
                    } footer: {
                        if group == .blues {
                            Text("The minor pentatonic over dominant 7th chords is the classic blues sound.")
                        }
                    }
                }
            }
            .navigationTitle("Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    NavigationStack { SoloBuddyView() }
}
