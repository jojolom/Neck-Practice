//
//  CompositionPlayAlongView.swift
//  Guitar Man
//
//  Play Along: you play your composition and the app listens. It waits on each chord until it
//  hears it (strum it again if you miss), marks it green, and moves on — so timing and a little
//  out-of-tune don't matter. Skip moves past a chord you can't get; it's marked orange. The
//  card shows where to play the chord it's waiting for. With a melody, a switch picks which
//  part you play: the chords, or the melody one note at a time.
//

import SwiftUI

struct CompositionPlayAlongView: View {

    private enum Part: String, CaseIterable {
        case chords = "Chords"
        case melody = "Melody"
    }

    let composition: Composition

    @Environment(\.dismiss) private var dismiss
    @State private var listener = ChordListener()
    @State private var part: Part = .chords
    /// Index into the part's chords or notes of the one being listened for.
    @State private var current = 0
    /// Chord (by start beat) or note (by start eighth) → heard (true) or skipped (false).
    @State private var results: [Int: Bool] = [:]
    /// Strum count when the current chord or note came up: it needs a fresh strum.
    @State private var strumsAtStart = 0
    /// Consecutive analyses that matched, so one lucky frame doesn't count.
    @State private var matchStreak = 0

    /// The chords in order (rests in between are skipped: you play at your own pace).
    private var chords: [Composition.PlacedChord] { composition.chords }
    private var notes: [Composition.MelodyNote] { composition.melody }

    private var count: Int { part == .chords ? chords.count : notes.count }
    private var isFinished: Bool { current >= count }

    private var currentChord: CompositionChord? {
        guard part == .chords, !isFinished else { return nil }
        return composition.chord(chords[current].symbol)
    }

    private var currentNote: Composition.MelodyNote? {
        guard part == .melody, !isFinished else { return nil }
        return notes[current]
    }

    /// Key of the current item in `results`.
    private var currentStart: Int? {
        guard !isFinished else { return nil }
        return part == .chords ? chords[current].start : notes[current].start
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if composition.hasMelody && !composition.chords.isEmpty {
                        Picker("Part", selection: $part) {
                            ForEach(Part.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 240)
                    }

                    statusCard

                    CompositionStaffView(composition: composition,
                                         chordColors: part == .chords ? colors : [:],
                                         noteColors: part == .melody ? colors : [:])
                        .padding(.horizontal, 12)

                    if listener.isListening && !isFinished {
                        chromaBars
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.vertical, 12)
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button {
                        restart()
                    } label: {
                        Label("Start Over", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    Button {
                        advance(heard: false)
                    } label: {
                        Label("Skip", systemImage: "forward.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(isFinished ? Color.gray.opacity(0.3) : Color.orange.opacity(0.85))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isFinished)
                }
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .navigationTitle("Play Along")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                // A melody with no chords: there's only the melody to play.
                if composition.chords.isEmpty && composition.hasMelody { part = .melody }
                await listener.start()
            }
            .onDisappear { listener.stop() }
            .onChange(of: listener.chroma) { _, chroma in
                listen(to: chroma)
            }
            .onChange(of: part) { restart() }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var statusCard: some View {
        VStack(spacing: 6) {
            if listener.permissionDenied {
                Label("Microphone access is off", systemImage: "mic.slash")
                    .font(.headline)
                Text("Turn it on in Settings ▸ Privacy & Security ▸ Microphone to play along. You can still play from the staff without it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if isFinished {
                let heard = results.values.filter { $0 }.count
                let allHeard = heard == count
                let noun = part == .chords ? "chords" : "notes"
                Image(systemName: allHeard ? "checkmark.seal.fill" : "forward.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(allHeard ? .green : .orange)
                Text("\(heard) of \(count) \(noun)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(allHeard ? "Every one, clean. Nice." : "Orange ones were skipped. Try them again?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let chord = currentChord {
                HStack(alignment: .center, spacing: 16) {
                    VStack(spacing: 6) {
                        Text("Chord \(current + 1) of \(count)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(chord.romanNumeral)
                            .font(.system(size: 22, weight: .bold, design: .serif))
                        Text("Play \(chord.name)")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                        Text(chord.pitches.map(\.name).joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    ChordShapesView(chord: chord, width: 92)
                }
                if !listener.isListening {
                    ProgressView()
                        .padding(.top, 4)
                }
            } else if let note = currentNote {
                Text("Note \(current + 1) of \(count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Play \(note.pitch.name)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(note.value.displayName + " note")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if !listener.isListening {
                    ProgressView()
                        .padding(.top, 4)
                }
            }
        }
        .multilineTextAlignment(.center)
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    /// The notes to listen for now, as pitch classes.
    private var listeningFor: Set<Int> {
        if let chord = currentChord { return chord.pitchClasses }
        if let note = currentNote { return [note.pitch.note.rawValue] }
        return []
    }

    /// What the mic hears, by note: the chord's (or melody note's) notes in the accent color.
    /// Heights follow the listener's smoothed display levels, so the bars stay low when it's
    /// quiet and glide.
    private var chromaBars: some View {
        let tones = listeningFor
        let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        let maxBarHeight: CGFloat = 44
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<12, id: \.self) { pc in
                let level = min(max(listener.displayLevels[pc], 0), 1)
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tones.contains(pc) ? Color.accentColor : Color(.systemGray3))
                        .frame(height: max(3, maxBarHeight * level))
                        .frame(height: maxBarHeight, alignment: .bottom)
                    Text(names[pc])
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(tones.contains(pc) ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: maxBarHeight + 16, alignment: .bottom)
        .clipped()
        .animation(.easeOut(duration: 0.15), value: listener.displayLevels)
        .accessibilityHidden(true)
    }

    private var colors: [Int: Color] {
        var colors: [Int: Color] = [:]
        for (start, heard) in results { colors[start] = heard ? .green : .orange }
        if let currentStart { colors[currentStart] = .accentColor }
        return colors
    }

    // MARK: - Listening

    /// Whether the current chord or note needs a fresh strum or pluck: always for a chord (the
    /// same chord twice needs two strums), and for a note only when it repeats the last one —
    /// moving to a new note is enough, so a slur or a hammer-on still counts.
    private var needsFreshAttack: Bool {
        guard part == .melody, current > 0, current < notes.count else { return true }
        return notes[current - 1].pitch.note == notes[current].pitch.note
    }

    private func listen(to chroma: [Double]) {
        guard !isFinished, !needsFreshAttack || listener.strumCount > strumsAtStart else { return }
        let matched: Bool
        if let chord = currentChord {
            let required = chord.requiredPitchClasses
            matched = ChordAnalyzer.matches(chroma: chroma, pitchClasses: required,
                                            optional: chord.pitchClasses.subtracting(required))
        } else if let note = currentNote {
            matched = ChordAnalyzer.matchesNote(chroma: chroma, pitchClass: note.pitch.note.rawValue)
        } else {
            matched = false
        }
        if matched {
            matchStreak += 1
            if matchStreak >= 2 { advance(heard: true) }
        } else {
            matchStreak = 0
        }
    }

    private func advance(heard: Bool) {
        guard let start = currentStart else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            results[start] = heard
            current += 1
        }
        strumsAtStart = listener.strumCount
        matchStreak = 0
    }

    private func restart() {
        withAnimation {
            results = [:]
            current = 0
        }
        strumsAtStart = listener.strumCount
        matchStreak = 0
    }
}
