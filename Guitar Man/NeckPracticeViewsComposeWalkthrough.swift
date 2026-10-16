//
//  ComposeWalkthrough.swift
//  Guitar Man
//
//  The Compose tour, and Compose Settings.
//
//  The tour dims the editor and lights up one part at a time (the settings card, the chord
//  palette, the staff, the length picker, the Chords | Melody switch, Play Along) with a card
//  saying what it does, scrolling each into view. It opens the first time you open a
//  composition each time the app is launched, until you turn it off: its last step asks.
//  Compose Settings (in the editor's ⋯ menu) can turn it back on or show it right away, and
//  holds Hear Compositions: the speaker button that plays a composition aloud.
//
//  Parts of the editor mark themselves with `composeTourTarget(_:)`; the overlay reads their
//  frames through ComposeTourAnchors.
//

import SwiftUI

// MARK: - Targets

enum ComposeTourTarget: Hashable {
    case settings, palette, staff, length, mode, playAlong
}

struct ComposeTourAnchors: PreferenceKey {
    static let defaultValue: [ComposeTourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [ComposeTourTarget: Anchor<CGRect>],
                       nextValue: () -> [ComposeTourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Marks this view as a part the Compose tour can light up.
    func composeTourTarget(_ target: ComposeTourTarget) -> some View {
        anchorPreference(key: ComposeTourAnchors.self, value: .bounds) { [target: $0] }
    }
}

// MARK: - Tour

enum ComposeTour {

    /// Whether the tour opens with Compose (once per launch of the app).
    static let enabledKey = "compose.walkthroughEnabled"

    /// Set once the tour has opened since the app launched.
    static var shownThisLaunch = false

    struct Step {
        let target: ComposeTourTarget?
        let symbol: String
        let title: String
        let text: String
    }

    static func steps(hearPlayback: Bool) -> [Step] {
        [
            Step(target: nil, symbol: "music.note.house.fill", title: "Welcome to Compose",
                 text: "Write your own chord progressions, and a melody if you like, then play them on your guitar while the app listens. Here's a quick tour."),
            Step(target: .settings, symbol: "slider.horizontal.3", title: "Key, time and length",
                 text: "Pick the key (major or minor), 4/4 or 3/4, and how many measures. Change the key any time: everything you've written moves with it."),
            Step(target: .palette, symbol: "textformat", title: "Your chords",
                 text: "These are the chords in your key, as Roman numerals. Tap one to write it on the staff; its 7th and other versions then show underneath. Swipe them for borrowed chords like ♭VII and V/V."),
            Step(target: .staff, symbol: "hand.tap", title: "Put them on the staff",
                 text: "Chords go at the blue mark, one after another, like typing. Tap a beat to move the mark; an empty beat also shows the chords to pick from. Long-press a chord to change its length or inversion, see where to play it, or copy its measure."),
            Step(target: .length, symbol: "metronome", title: "How long each chord lasts",
                 text: "Pick the length before you write a chord: a quarter, half, dotted half or whole note. Gaps become rests."),
            Step(target: .mode, symbol: "music.quarternote.3", title: "Add a melody",
                 text: "Switch to Melody to put single notes over your chords, from eighth notes to whole notes, sharps and flats included. Your chords stay on the staff, faded behind the melody; turn that off in Compose Settings."),
            Step(target: .playAlong, symbol: "music.mic", title: "Play it",
                 text: hearPlayback
                    ? "Tap Play Along and play it on your guitar: the app listens and marks each chord green. The speaker button plays it for you first."
                    : "Tap Play Along and play it on your guitar: the app listens and marks each chord green. To hear it played first, turn on Hear Compositions in Compose Settings."),
            Step(target: nil, symbol: "checkmark.circle.fill", title: "You're ready",
                 text: "How to Compose (the full guide), Compose Settings and Undo are in the ⋯ menu. Should this tour open again next time you open the app?"),
        ]
    }
}

// MARK: - Overlay

/// The tour over the editor: a dimmed screen with a hole around the step's part, and a card.
struct ComposeWalkthroughOverlay: View {

    let steps: [ComposeTour.Step]
    @Binding var step: Int?
    let anchors: [ComposeTourTarget: Anchor<CGRect>]
    /// The tour's done: `keepShowing` is false if they turned it off.
    let onFinish: (_ keepShowing: Bool) -> Void

    var body: some View {
        GeometryReader { proxy in
            if let index = step, steps.indices.contains(index) {
                let current = steps[index]
                let hole = current.target.flatMap { anchors[$0] }.map { proxy[$0].insetBy(dx: -6, dy: -6) }
                ZStack(alignment: .top) {
                    dimming(around: hole, in: proxy.size)
                    card(current, index: index, hole: hole, in: proxy.size)
                }
                .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    private func dimming(around hole: CGRect?, in size: CGSize) -> some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            if let hole { path.addRoundedRect(in: hole, cornerSize: CGSize(width: 14, height: 14)) }
        }
        .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
        .overlay {
            if let hole {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.9), lineWidth: 2)
                    .frame(width: hole.width, height: hole.height)
                    .position(x: hole.midX, y: hole.midY)
            }
        }
        // Taps on the dimmed editor don't reach it while the tour is up.
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityHidden(true)
    }

    /// The step's card: under its part if that's in the top half of the screen, over it if not,
    /// in the middle if it has none.
    private func card(_ current: ComposeTour.Step, index: Int, hole: CGRect?, in size: CGSize) -> some View {
        let isLast = index == steps.count - 1
        let content = VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: current.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(current.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer(minLength: 8)
                if !isLast {
                    Button("Skip") { onFinish(true) }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .accessibilityHint("Closes the tour. It opens again next time you open the app.")
                }
            }
            Text(current.text)
                .font(.system(size: 15, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)

            if isLast {
                VStack(spacing: 8) {
                    Button {
                        onFinish(false)
                    } label: {
                        Text("Got It, Turn Off the Tour")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                    }
                    Button {
                        onFinish(true)
                    } label: {
                        Text("Show It Next Time")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Text("You can turn it back on, or see it again, in Compose Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            } else {
                HStack {
                    Text("\(index + 1) of \(steps.count)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Spacer()
                    if index > 0 {
                        Button("Back") { step = index - 1 }
                            .buttonStyle(.bordered)
                    }
                    Button(index == 0 ? "Start" : "Next") { step = index + 1 }
                        .buttonStyle(.borderedProminent)
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            }
        }
        .padding(18)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        .padding(.horizontal, 16)
        .frame(maxWidth: 520)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)

        return Group {
            if let hole, hole.midY < size.height / 2 {
                content
                    .padding(.top, min(hole.maxY + 12, size.height - 260))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else if let hole {
                content
                    .padding(.bottom, min(max(size.height - hole.minY + 12, 0), size.height - 260))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            } else {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

// MARK: - Compose Settings

struct ComposeSettingsView: View {

    /// Faded chord notes behind the melody, on the staff.
    static let chordsUnderMelodyKey = "compose.chordsUnderMelody"

    /// Close the settings and start the tour.
    let onShowTour: () -> Void

    @AppStorage(Self.chordsUnderMelodyKey) private var chordsUnderMelody = true
    @AppStorage(ComposeTour.enabledKey) private var tourEnabled = true
    @AppStorage(CompositionPlayer.enabledKey) private var hearPlayback = false
    @AppStorage(CompositionPlayer.styleKey) private var playbackStyle: CompositionPlaybackStyle = .together
    @AppStorage(CompositionPlayer.tempoKey) private var playbackTempo = CompositionPlayer.defaultTempo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $hearPlayback) {
                        Label("Hear Compositions", systemImage: "speaker.wave.2")
                    }
                    if hearPlayback {
                        Picker("Chords", selection: $playbackStyle) {
                            ForEach(CompositionPlaybackStyle.allCases) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        Stepper(value: $playbackTempo, in: CompositionPlayer.tempoRange, step: 5) {
                            HStack {
                                Text("Tempo")
                                Spacer()
                                Text("\(playbackTempo) BPM")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .accessibilityValue("\(playbackTempo) beats per minute")
                    }
                } footer: {
                    Text("Adds a speaker button next to Play Along that plays your composition on the guitar, its chords all at once or as arpeggios, with the melody on top.")
                }

                Section {
                    Toggle(isOn: $chordsUnderMelody) {
                        Label("Chords Under the Melody", systemImage: "music.note.list")
                    }
                } footer: {
                    Text("With a melody, the staff shows the melody's notes with each chord named above. This also draws the chord's notes, faded, behind the melody.")
                }

                Section {
                    Toggle(isOn: $tourEnabled) {
                        Label("Show the Tour", systemImage: "sparkles.rectangle.stack")
                    }
                    Button {
                        onShowTour()
                    } label: {
                        Label("Take the Tour Now", systemImage: "play.circle")
                    }
                } header: {
                    Text("Walkthrough")
                } footer: {
                    Text("The tour opens the first time you open a composition each time you start the app, until you turn it off.")
                }
            }
            .navigationTitle("Compose Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
