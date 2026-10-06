//
//  ModeReferenceView.swift
//  Guitar Man
//
//  Reference for the seven diatonic modes: what a mode is, each mode's formula compared
//  with major or natural minor, its notes on the staff, and a three-notes-per-string
//  fingering labeled with scale degrees.
//

import SwiftUI

struct ModeReferenceView: View {

    @State private var mode: Mode = .dorian
    @State private var root: Note = .d
    @State private var showDegrees = true
    @State private var showIntro = true
    @State private var playingIndex: Int? = nil
    @State private var isPlaying = false
    @Environment(AudioSettings.self) private var audioSettings

    private var scale: ModeScale { ModeScale(mode: mode, root: root) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    introCard
                    modePicker
                    rootPicker
                    summaryCard
                    staffCard
                    fretboardSection
                }
                .padding(.vertical, 12)
            }

            Divider()

            Button {
                playScale()
            } label: {
                Label(isPlaying ? "Playing..." : "Play \(scale.name)",
                      systemImage: isPlaying ? "speaker.wave.2.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(audioSettings.isEnabled && !isPlaying ? Color.accentColor : Color.gray.opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!audioSettings.isEnabled || isPlaying)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("Modes")
    }

    // MARK: - Sections

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { showIntro.toggle() }
            } label: {
                HStack {
                    Label("What's a mode?", systemImage: "lightbulb")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showIntro ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if showIntro {
                Text("Play the C major scale, but start and end on D instead of C. Same seven notes, new home base. That's D Dorian.")
                Text("Moving the home note moves where the half steps fall, which gives each mode its own color. Every major key holds seven modes, one starting on each of its notes:")
                Text(modesOfC)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text("To hear what makes a mode different, compare it with the major or natural minor scale on the same root. Usually just one or two notes change.")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    private var modesOfC: String {
        Mode.allCases.map { mode in
            let root = Note.c.advanced(by: Mode.majorScale[mode.rawValue])
            return "\(mode.degree). \(ModeScale(mode: mode, root: root).name)"
        }.joined(separator: "\n")
    }

    private var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Mode.allCases) { m in
                    chip(m.name, selected: mode == m, color: .indigo) { mode = m }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var rootPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Note.allCases) { note in
                    chip(ModeScale(mode: mode, root: note).rootName, selected: root == note, color: .orange) {
                        root = note
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var summaryCard: some View {
        let s = scale
        let characteristic = Set(mode.characteristicDegrees)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(s.name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("\(mode.ordinalName) of \(s.parentKeyName) · \(mode.tonicChord.lowercased()) chord on the root")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Formula: degrees, with the ones that differ from major / minor highlighted.
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let isCharacteristic = characteristic.contains(i)
                    VStack(spacing: 2) {
                        Text(mode.degreeLabels[i])
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Text(s.pitches()[i].name)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(isCharacteristic ? Color.orange.opacity(0.25) : Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Compared with \(mode.comparisonName.lowercased())")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(comparisonText)
            }

            Text(mode.sound)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    /// "Same as D natural minor except the 6th: B instead of B♭."
    private var comparisonText: String {
        let s = scale
        let degrees = mode.characteristicDegrees
        guard !degrees.isEmpty else {
            return "This is the \(mode.comparisonName.lowercased()) scale. The other modes are measured against it."
        }
        let pitches = s.pitches()
        let changes = degrees.map { i -> String in
            let theirs = s.comparisonPitch(degree: i)?.name ?? "?"
            return "\(mode.characteristicLabels[degrees.firstIndex(of: i) ?? 0]) (\(pitches[i].name) instead of \(theirs))"
        }
        return "Same as \(s.rootName) \(mode.comparisonName.lowercased()) except the "
            + changes.joined(separator: " and the ")
            + ". That's the sound of \(mode.name)."
    }

    private var staffCard: some View {
        let pitches = scale.pitches()
        let characteristic = Set(mode.characteristicDegrees)
        let columns: [StaffColumn] = pitches.enumerated().map { (i, pitch) -> StaffColumn in
            let color: Color? = playingIndex == i ? Color.accentColor
                : (characteristic.contains(i % 7) ? Color.orange : nil)
            return StaffColumn(id: i, pitches: [pitch], below: pitch.name, color: color)
        }
        return StaffView(columns: columns, lineSpacing: 9)
            .frame(height: 130)
            .padding(.horizontal, 16)
    }

    private var fretboardSection: some View {
        let fingering = scale.threeNotesPerString
        let positions = Set(fingering.map { $0.position })
        let roots = Set(fingering.filter { $0.degree == 0 }.map { $0.position })
        var labels: [FretboardPosition: String] = [:]
        let pitches = scale.pitches()
        for item in fingering {
            labels[item.position] = showDegrees ? mode.degreeLabels[item.degree] : pitches[item.degree].name
        }
        let maxFret = max(5, (fingering.map { $0.position.fret }.max() ?? 5) + 1)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Three notes per string")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Picker("Labels", selection: $showDegrees) {
                    Text("Degrees").tag(true)
                    Text("Notes").tag(false)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
            .padding(.horizontal, 16)

            FretboardView(
                highlightedPositions: positions,
                rootPositions: roots,
                maxFret: maxFret,
                showHighlightedLabels: true,
                customLabels: labels
            )
            .frame(height: 260)
            .padding(.horizontal, 8)
        }
    }

    private func chip(_ title: String, selected: Bool, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? color : Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Playback

    /// Plays the scale up an octave, highlighting each note on the staff.
    private func playScale() {
        guard audioSettings.isEnabled, !isPlaying else { return }
        AudioPlayer.shared.stopAll()
        isPlaying = true
        let pitches = scale.pitches()
        let step = 0.3
        for (i, pitch) in pitches.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * step) {
                playingIndex = i
                AudioPlayer.shared.playNote(pitch.note, octave: pitch.soundingOctave)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(pitches.count) * step + 0.4) {
            playingIndex = nil
            isPlaying = false
        }
    }
}

#Preview {
    NavigationStack {
        ModeReferenceView()
            .environment(AudioSettings())
    }
}
