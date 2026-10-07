//
//  CompositionPlayer.swift
//  Guitar Man
//
//  Plays a composition aloud. Compose is meant to be played by the student, so this is a
//  hidden option: in the Compose editor, tap "Key" five times quickly to show the Playback
//  settings, whose "Hear Compositions" toggle adds a speaker button next to Play Along.
//
//  Each chord sounds once, on its beat, and rings for its length (rests are silent): its three
//  notes either all at once or as an arpeggio (low to high, an eighth note apart, each left
//  ringing). The whole progression goes to AudioPlayer as one timeline, so it keeps
//  exact time; the staff highlight follows along on the main thread.
//

import AVFoundation
import Foundation
import Observation

/// How each chord is sounded.
enum CompositionPlaybackStyle: String, CaseIterable, Identifiable {
    /// Every note at the same instant, like a block triad.
    case together
    /// One note after another, low to high, once.
    case arpeggio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .together: return "Together"
        case .arpeggio: return "Arpeggio"
        }
    }
}

@Observable
final class CompositionPlayer {

    /// UserDefaults keys for the hidden Playback settings in the Compose editor.
    static let unlockedKey = "compose.playbackSettingsUnlocked"
    static let enabledKey = "compose.hearPlayback"
    static let styleKey = "compose.playbackStyle"
    static let tempoKey = "compose.playbackBPM"

    static let defaultTempo = 90
    static let tempoRange = 40...200

    /// Start beat of the chord being heard, or nil (stopped, or in a rest).
    private(set) var playingChord: Int?
    private(set) var isPlaying = false

    private var task: Task<Void, Never>?
    private var interruptionObserver: (any NSObjectProtocol)?

    func play(_ composition: Composition, style: CompositionPlaybackStyle, bpm: Int) {
        stop()
        // Rests are silent, but playback ends with the last chord rather than empty measures.
        let chords = composition.chords
        guard let last = chords.last else { return }

        let beat = 60 / Double(min(max(bpm, Self.tempoRange.lowerBound), Self.tempoRange.upperBound))
        AudioPlayer.shared.play(Self.notes(for: composition, style: style, beat: beat))

        isPlaying = true
        playingChord = chords.first?.start == 0 ? 0 : nil
        interruptionObserver = AudioSessionSetup.observe(AVAudioSession.interruptionNotification) { [weak self] _ in
            self?.stop()
        }
        task = Task { [weak self] in
            let clock = ContinuousClock()
            let start = clock.now
            do {
                // Highlight each chord while it sounds, and nothing in the rests between.
                for chord in chords {
                    try await clock.sleep(until: start.advanced(by: .seconds(beat * Double(chord.start))))
                    self?.playingChord = chord.start
                    let next = chords.first { $0.start > chord.start }?.start
                    if next != chord.end {
                        try await clock.sleep(until: start.advanced(by: .seconds(beat * Double(chord.end))))
                        self?.playingChord = nil
                    }
                }
                try await clock.sleep(until: start.advanced(by: .seconds(beat * Double(last.end))))
            } catch {
                return  // stopped
            }
            self?.finish()
        }
    }

    func stop() {
        guard isPlaying else { return }
        task?.cancel()
        AudioPlayer.shared.stopAll()
        finish()
    }

    private func finish() {
        task = nil
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        isPlaying = false
        playingChord = nil
    }

    /// Every note of the progression on one timeline (seconds from the start).
    static func notes(for composition: Composition, style: CompositionPlaybackStyle,
                      beat: Double) -> [AudioPlayer.ScheduledNote] {
        var notes: [AudioPlayer.ScheduledNote] = []
        for chord in composition.chords {
            let start = beat * Double(chord.start)
            let chordLength = beat * Double(chord.beats)
            let midis = composition.chord(degree: chord.degree).pitches.map(\.midi)
            switch style {
            case .together:
                // Ring to the next chord; its fade overlaps the next chord's start, so no gap.
                let gain = 1 / Float(midis.count).squareRoot()
                notes += midis.map { .init(midi: $0, delay: start, duration: chordLength, gain: gain) }
            case .arpeggio:
                // An eighth note apart (closer if the chord is too short), each left ringing.
                let gap = min(beat / 2, chordLength / Double(midis.count))
                notes += midis.enumerated().map { i, midi in
                    let delay = start + Double(i) * gap
                    return .init(midi: midi, delay: delay, duration: start + chordLength - delay, gain: 0.8)
                }
            }
        }
        return notes
    }
}
