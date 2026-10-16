//
//  SoloBuddyView.swift
//  Guitar Man
//
//  Solo Buddy: pick a key, one to four chords (or the 12-bar blues), a style and a tempo, or
//  start from a preset, and it plays a backing to solo over on the nylon guitar. The card at the
//  top shows the chord you're on and the next one; the fretboard under it shows the pentatonic
//  box to solo with, any of its five positions; chords and settings come after. Chords are Roman numerals (as in
//  Compose), so a preset or your own progression plays in any key. Presets are cards to swipe
//  through at the top (Grooves), a group at a time, after Your Groove: the one you made (or
//  Make Your Own, which starts from the key's one chord and asks for the next). Changing a
//  preset's chords makes it your groove. Both the groove playing and yours are remembered.
//

import SwiftUI

struct SoloBuddyView: View {

    private static let storageKey = "soloBuddy.groove"
    private static let myGrooveKey = "soloBuddy.myGroove"
    private static let chordsID = "soloBuddy.chords"
    private static let myGrooveCardID = "soloBuddy.mine"

    @State private var track = BackingTrack()
    @State private var groove: SoloGroove = SoloBuddyView.loadGroove()
    /// The groove you made, kept while you try presets.
    @State private var myGroove: SoloGroove? = SoloBuddyView.loadMyGroove()
    @AppStorage("soloBuddy.countIn") private var countsIn = true
    @AppStorage("soloBuddy.click") private var clicks = false
    @AppStorage("soloBuddy.position") private var position = 1
    /// Which presets the Grooves row shows.
    @State private var presetGroup: SoloPreset.Group = .minor
    /// The chord being picked: one to change, or new ones to add.
    @State private var picking: ChordPick? = nil
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationContainer {
            ScrollViewReader { page in
                ScrollView {
                    VStack(spacing: 16) {
                        presetPicker(page)
                        // What you need while soloing: the chord you're on and the box.
                        nowPlaying
                        scaleCard
                        chordRow
                            .id(Self.chordsID)
                        settingsCard
                    }
                    .padding(.vertical, 12)
                }
            }
            .safeAreaInset(edge: .bottom) { playBar }
            .navigationTitle("Solo Buddy")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $picking) { pick in
                SoloChordPicker(groove: groove, slot: pick.slot) { symbol in
                    setChord(symbol, for: pick)
                } onRemove: {
                    if let slot = pick.slot { removeChord(at: slot) }
                }
                .presentationDetents([.medium, .large])
            }
            .onAppear {
                presetGroup = SoloPreset.preset(groove.presetID)?.group ?? presetGroup
                track.groove = groove
                track.countsIn = countsIn
                track.clicks = clicks
            }
            .onDisappear { track.stop() }
            .onChange(of: groove) { _, updated in
                track.groove = updated
                Self.save(updated, forKey: Self.storageKey)
                // A groove that isn't a preset (any more) is yours.
                if updated.presetID == nil {
                    myGroove = updated
                    Self.save(updated, forKey: Self.myGrooveKey)
                }
            }
            .onChange(of: countsIn) { track.countsIn = countsIn }
            .onChange(of: clicks) { track.clicks = clicks }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { track.stop() }
            }
        }
    }

    private static func load(forKey key: String) -> SoloGroove? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(SoloGroove.self, from: $0) }
    }

    private static func save(_ groove: SoloGroove, forKey key: String) {
        if let data = try? JSONEncoder().encode(groove) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func loadGroove() -> SoloGroove {
        load(forKey: storageKey) ?? SoloPreset.all[0].groove
    }

    /// Yours, or (from before Your Groove had its own place) the groove playing if it isn't a preset.
    private static func loadMyGroove() -> SoloGroove? {
        if let mine = load(forKey: myGrooveKey) { return mine }
        let current = loadGroove()
        return current.presetID == nil ? current : nil
    }

    /// The chord picker: changing the chord in a slot, or adding chords to the end.
    private enum ChordPick: Identifiable {
        case change(Int)
        case add

        var id: String {
            switch self {
            case .change(let slot): return "change\(slot)"
            case .add: return "add"
            }
        }

        var slot: Int? {
            if case .change(let slot) = self { return slot }
            return nil
        }
    }

    // MARK: - Grooves

    /// Your groove, then the presets, as cards to swipe through a group at a time; the one
    /// playing is outlined. Picking one while it plays changes the backing at the next bar.
    private func presetPicker(_ page: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Grooves")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Spacer()
                Picker("Group", selection: $presetGroup.animation(.easeInOut(duration: 0.2))) {
                    ForEach(SoloPreset.Group.allCases, id: \.self) { group in
                        Text(group.shortName).tag(group)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            }
            .padding(.horizontal, 20)

            ScrollViewReader { scroller in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        myGrooveCard(page)
                            .id(Self.myGrooveCardID)
                        ForEach(SoloPreset.all.filter { $0.group == presetGroup }) { preset in
                            presetCard(preset)
                                .id(preset.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 16)
                }
                .scrollTargetBehavior(.viewAligned)
                .onAppear {
                    if let id = groove.presetID { scroller.scrollTo(id, anchor: .leading) }
                }
            }
        }
    }

    private func presetCard(_ preset: SoloPreset) -> some View {
        let isOn = groove.presetID == preset.id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { groove = preset.groove }
        } label: {
            grooveCard(label: preset.groove.style.displayName, title: preset.name, detail: preset.detail,
                       footer: "\(preset.groove.keyName) · \(preset.groove.bpm) BPM", isOn: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.name), \(preset.groove.style.displayName). \(preset.detail) \(preset.groove.keyName), \(preset.groove.bpm) beats per minute. Solo with \(preset.groove.scaleName).")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// The groove you made (its chords, style and key), or Make Your Own when there isn't one.
    private func myGrooveCard(_ page: ScrollViewProxy) -> some View {
        let isOn = groove.presetID == nil
        let mine = isOn ? groove : myGroove
        return Button {
            if let mine, !isOn {
                withAnimation(.easeInOut(duration: 0.2)) { groove = mine }
            } else if mine == nil {
                startFromScratch(page)
            } else {
                withAnimation(.easeInOut(duration: 0.3)) { page.scrollTo(Self.chordsID, anchor: .top) }
            }
        } label: {
            if let mine {
                grooveCard(label: mine.style.displayName, title: "Your Groove", detail: chordList(mine),
                           footer: "\(mine.keyName) · \(mine.bpm) BPM", isOn: isOn)
            } else {
                grooveCard(label: "Start From Scratch", title: "Make Your Own",
                           detail: "Pick your chords, a style and a tempo.", footer: "Any key", isOn: false,
                           icon: "plus.circle.fill")
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if mine != nil {
                Button {
                    startFromScratch(page)
                } label: {
                    Label("Start From Scratch", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .accessibilityLabel(mine.map { "Your Groove, \($0.style.displayName). \(chordList($0)). \($0.keyName), \($0.bpm) beats per minute." }
                            ?? "Make your own groove")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    /// "Am – G – F – E", or the 12-bar blues.
    private func chordList(_ groove: SoloGroove) -> String {
        groove.form == .twelveBar
            ? "The 12-bar blues."
            : groove.chords.map { groove.chord($0).name }.joined(separator: " – ")
    }

    private func grooveCard(label: String, title: String, detail: String, footer: String, isOn: Bool,
                            icon: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(isOn || icon != nil ? Color.accentColor : .secondary)
                    .lineLimit(1)
                Spacer()
                if isOn {
                    Image(systemName: track.isPlaying ? "speaker.wave.2.fill" : "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(detail)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
            Spacer(minLength: 0)
            Text(footer)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(width: 210, height: 128, alignment: .topLeading)
        .background(isOn ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(isOn ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .overlay {
            // Make Your Own: a dashed outline, an empty slot to fill.
            if icon != nil {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
        }
    }

    /// A groove of just the key's one chord, in the key and style playing now; then the chord
    /// picker opens to add the next.
    private func startFromScratch(_ page: ScrollViewProxy) {
        let style: BackingStyle = groove.style == .shuffle || groove.style == .waltz ? .strummed : groove.style
        withAnimation(.easeInOut(duration: 0.2)) {
            groove = SoloGroove(keyRoot: groove.keyRoot, isMinor: groove.isMinor, chords: [ChordSymbol(degree: 1)],
                                form: .loop, style: style, bpm: style.defaultBPM, barsPerChord: 1,
                                scale: groove.isMinor ? .minor : .major, presetID: nil)
        }
        withAnimation(.easeInOut(duration: 0.3)) { page.scrollTo(Self.chordsID, anchor: .top) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { picking = .add }
    }

    // MARK: - Now playing

    private var nowPlaying: some View {
        let bars = groove.bars
        let barIndex = track.bar ?? 0
        let current = groove.chord(groove.symbol(forBar: barIndex))
        let next = groove.chord(groove.symbol(forBar: barIndex + 1))
        let grooveName = SoloPreset.preset(groove.presetID)?.name ?? "Your Groove"
        return VStack(spacing: 8) {
            Text("\(grooveName) · \(groove.keyName)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
                Text(bars.count > 1 ? "Next: \(next.name)" : "One chord: make it sing")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .opacity(track.isPlaying || bars.count <= 1 ? 1 : 0.6)
            }
            beatDots
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
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
                            picking = .change(index)
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
                            picking = .add
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
                HStack(alignment: .firstTextBaseline) {
                    Text("Tap a chord to change it. Long-press to remove it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if groove.chords.count > 1 {
                        Button("Start Over") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                groove.chords = [ChordSymbol(degree: 1)]
                                groove.presetID = nil
                            }
                            picking = .add
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .accessibilityHint("Keeps just the key's one chord, then lets you add the next")
                    }
                }
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

    /// A changed chord closes the picker; an added one leaves it open for the next, until there are four.
    private func setChord(_ symbol: ChordSymbol, for pick: ChordPick) {
        switch pick {
        case .change(let index):
            guard groove.chords.indices.contains(index) else { break }
            groove.chords[index] = symbol
            picking = nil
        case .add:
            if groove.chords.count < SoloGroove.chordRange.upperBound { groove.chords.append(symbol) }
            if groove.chords.count >= SoloGroove.chordRange.upperBound { picking = nil }
        }
        groove.presetID = nil
    }

    private func removeChord(at index: Int) {
        guard groove.chords.count > 1, groove.chords.indices.contains(index) else { return }
        groove.chords.remove(at: index)
        groove.presetID = nil
        picking = nil
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

    /// The neck is drawn to the highest fret any box in this key reaches, so it keeps one
    /// width: changing position then scrolls the new box fully into view (a neck that grew
    /// with the box cut the scroll short).
    private var neckFrets: Int {
        let highest = allPentatonicShapes.map {
            PentatonicQuestion(shape: $0, quality: groove.scale, key: groove.keyRoot).maxFret
        }.max() ?? 12
        return max(highest, 12)
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
                // The frets here too: the numbers under the neck can be out of sight.
                VStack(alignment: .leading, spacing: 1) {
                    Text("Position")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("Frets \(box.minFret)–\(box.maxFret)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2), value: box.minFret)
                }
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
                maxFret: neckFrets,
                showHighlightedLabels: true,
                keyContext: FretboardView.KeyContext(root: box.effectiveRootNote, isMinor: groove.scale.isMinor)
            )
            .frame(height: 280)
            .padding(.horizontal, 8)
            .animation(.easeInOut(duration: 0.3), value: position)

            Text("Orange dots are the root, \(groove.tonicName).")
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

/// Pick a chord for a slot (`slot`), or add chords one after another (`slot` nil: it stays open,
/// showing the chords so far, until Done or there are four): the key's chords, their 7ths, and
/// borrowed and secondary chords.
private struct SoloChordPicker: View {

    let groove: SoloGroove
    let slot: Int?
    let onPick: (ChordSymbol) -> Void
    let onRemove: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var current: ChordSymbol? {
        slot.flatMap { groove.chords.indices.contains($0) ? groove.chords[$0] : nil }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if slot == nil { progressionSoFar }
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
            .navigationTitle(slot.map { "Change Chord \($0 + 1)" } ?? "Add Chords")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if slot == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                } else {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    /// The chords so far and a slot for each still to come, so you can see the progression grow.
    private var progressionSoFar: some View {
        let limit = SoloGroove.chordRange.upperBound
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<limit, id: \.self) { index in
                    let chord = groove.chords.indices.contains(index) ? groove.chord(groove.chords[index]) : nil
                    VStack(spacing: 1) {
                        Text(chord?.name ?? " ")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(chord?.romanNumeral ?? " ")
                            .font(.system(size: 11, weight: .semibold, design: .serif))
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(chord == nil ? Color.clear : Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        if chord == nil {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color(.systemGray3), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                    }
                }
            }
            .animation(.easeOut(duration: 0.15), value: groove.chords)
            Text(groove.chords.count >= limit
                 ? "That's four. Tap Done to play it."
                 : "Pick chord \(groove.chords.count + 1), or tap Done to play these.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
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

#Preview {
    NavigationStack { SoloBuddyView() }
}
