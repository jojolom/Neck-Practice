//
//  CompositionPlayAlongView.swift
//  Guitar Man
//
//  Play Along: you play your composition and the app listens. It waits on each chord until it
//  hears it (strum it again if you miss), marks it green, and moves on — so timing and a little
//  out-of-tune don't matter. Skip moves past a chord you can't get; it's marked orange.
//

import SwiftUI

struct CompositionPlayAlongView: View {

    let composition: Composition

    @Environment(\.dismiss) private var dismiss
    @State private var listener = ChordListener()
    /// Index into `chordSlots` of the chord being listened for.
    @State private var current = 0
    /// Slot → heard (true) or skipped (false).
    @State private var results: [Int: Bool] = [:]
    /// Strum count when the current chord came up: it needs a fresh strum.
    @State private var strumsAtStart = 0
    /// Consecutive analyses that matched, so one lucky frame doesn't count.
    @State private var matchStreak = 0

    /// Slots that hold a chord, in order (empty beats are skipped).
    private var chordSlots: [Int] {
        composition.slots.indices.filter { composition.slots[$0] != nil }
    }

    private var isFinished: Bool { current >= chordSlots.count }

    private var currentChord: CompositionChord? {
        guard !isFinished, let degree = composition.slots[chordSlots[current]] else { return nil }
        return composition.chord(degree: degree)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    statusCard

                    CompositionStaffView(composition: composition, slotColors: slotColors)
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
            .task { await listener.start() }
            .onDisappear { listener.stop() }
            .onChange(of: listener.chroma) { _, chroma in
                listen(to: chroma)
            }
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
                let allHeard = heard == chordSlots.count
                Image(systemName: allHeard ? "checkmark.seal.fill" : "forward.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(allHeard ? .green : .orange)
                Text("\(heard) of \(chordSlots.count) chords")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(allHeard ? "Every chord, clean. Nice." : "Orange ones were skipped. Try them again?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let chord = currentChord {
                Text("Chord \(current + 1) of \(chordSlots.count)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(chord.romanNumeral)
                    .font(.system(size: 22, weight: .bold, design: .serif))
                Text("Play \(chord.longName)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(chord.pitches.map(\.name).joined(separator: " · "))
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

    /// What the mic hears, by note: the chord's notes in the accent color.
    private var chromaBars: some View {
        let tones = currentChord?.pitchClasses ?? []
        let names = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
        let peak = max(listener.chroma.max() ?? 0, 0.0001)
        return HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<12, id: \.self) { pc in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(tones.contains(pc) ? Color.accentColor : Color(.systemGray3))
                        .frame(height: max(3, 60 * listener.chroma[pc] / peak))
                    Text(names[pc])
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(tones.contains(pc) ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 80, alignment: .bottom)
        .animation(.linear(duration: 0.08), value: listener.chroma)
        .accessibilityHidden(true)
    }

    private var slotColors: [Int: Color] {
        var colors: [Int: Color] = [:]
        for (slot, heard) in results { colors[slot] = heard ? .green : .orange }
        if !isFinished { colors[chordSlots[current]] = .accentColor }
        return colors
    }

    // MARK: - Listening

    private func listen(to chroma: [Double]) {
        guard let chord = currentChord, listener.strumCount > strumsAtStart else { return }
        if ChordAnalyzer.matches(chroma: chroma, pitchClasses: chord.pitchClasses) {
            matchStreak += 1
            if matchStreak >= 2 { advance(heard: true) }
        } else {
            matchStreak = 0
        }
    }

    private func advance(heard: Bool) {
        guard !isFinished else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            results[chordSlots[current]] = heard
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
