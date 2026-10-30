//
//  CompositionPlayer.swift
//  Guitar Man
//
//  Plays a composition aloud. Compose is meant to be played by the student, so it's off until
//  Hear Compositions is turned on in Compose Settings (the editor's ⋯ menu); then a speaker
//  button next to Play Along plays it.
//
//  Each chord sounds once, on its beat, and rings for its length (rests are silent): its notes
//  either all at once or as an arpeggio (low to high, an eighth note apart, each left ringing).
//  A melody plays over it, a little louder than the chords. Everything goes to AudioPlayer as
//  one timeline, so it keeps exact time; the staff highlight follows along on the main thread,
//  and `clock` lets the staff draw a playhead sweeping through the beats.
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

    /// UserDefaults keys for Hear Compositions in Compose Settings.
    static let enabledKey = "compose.hearPlayback"
    static let styleKey = "compose.playbackStyle"
    static let tempoKey = "compose.playbackBPM"

    static let defaultTempo = 90
    static let tempoRange = 40...200

    /// Start beat of the chord being heard, or nil (stopped, or in a rest).
    private(set) var playingChord: Int?
    /// Start eighth of the melody note being heard, or nil.
    private(set) var playingNote: Int?
    /// The measure being played (rests included), or nil.
    private(set) var playingMeasure: Int?
    /// When the first beat sounded and how long a beat is, while playing: where the playhead is.
    private(set) var clock: Playhead?
    private(set) var isPlaying = false

    /// The beat sounding at a moment (fractional, from 0), for drawing a playhead.
    struct Playhead: Equatable {
        let start: Date
        let secondsPerBeat: Double

        func beat(at date: Date) -> Double { max(0, date.timeIntervalSince(start) / secondsPerBeat) }
    }

    private var task: Task<Void, Never>?
    private var interruptionObserver: (any NSObjectProtocol)?

    func play(_ composition: Composition, style: CompositionPlaybackStyle, bpm: Int) {
        stop()
        // Rests are silent, but playback ends with the last chord or note rather than empty measures.
        guard !composition.isEmpty else { return }
        let beat = 60 / Double(min(max(bpm, Self.tempoRange.lowerBound), Self.tempoRange.upperBound))
        AudioPlayer.shared.play(Self.notes(for: composition, style: style, beat: beat))

        // Highlight each chord and note while it sounds, and nothing in the rests between:
        // (time in eighths, which line, start or nil to clear).
        // (A measure event sets `playingMeasure` and nothing else.)
        var events: [(tick: Int, isChord: Bool, start: Int?, measure: Int?)] = []
        for chord in composition.chords {
            events.append((chord.start * 2, true, chord.start, nil))
            if !composition.chords.contains(where: { $0.start == chord.end }) { events.append((chord.end * 2, true, nil, nil)) }
        }
        for note in composition.melody {
            events.append((note.start, false, note.start, nil))
            if !composition.melody.contains(where: { $0.start == note.end }) { events.append((note.end, false, nil, nil)) }
        }
        let end = events.map(\.tick).max() ?? 0
        // Each measure as it's reached, through to the one the piece ends in.
        let eighthsPerMeasure = composition.eighthsPerMeasure
        for measure in 0..<max((end + eighthsPerMeasure - 1) / eighthsPerMeasure, 1) {
            events.append((measure * eighthsPerMeasure, false, nil, measure))
        }
        // Clearing first, so a chord ending where another starts doesn't blank the new one.
        events.sort { $0.tick != $1.tick ? $0.tick < $1.tick : ($0.start == nil && $1.start != nil) }

        isPlaying = true
        clock = Playhead(start: .now, secondsPerBeat: beat)
        playingMeasure = 0
        interruptionObserver = AudioSessionSetup.observe(AVAudioSession.interruptionNotification) { [weak self] _ in
            self?.stop()
        }
        task = Task { [weak self] in
            let clock = ContinuousClock()
            let start = clock.now
            let eighth = beat / 2
            do {
                for event in events {
                    try await clock.sleep(until: start.advanced(by: .seconds(eighth * Double(event.tick))))
                    if let measure = event.measure {
                        self?.playingMeasure = measure
                    } else if event.isChord {
                        self?.playingChord = event.start
                    } else {
                        self?.playingNote = event.start
                    }
                }
                try await clock.sleep(until: start.advanced(by: .seconds(eighth * Double(end))))
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
        playingNote = nil
        playingMeasure = nil
        clock = nil
    }

    /// Every note of the progression on one timeline (seconds from the start).
    static func notes(for composition: Composition, style: CompositionPlaybackStyle,
                      beat: Double) -> [AudioPlayer.ScheduledNote] {
        var notes: [AudioPlayer.ScheduledNote] = []
        // Under a melody, the chords step back a little.
        let chordGain: Float = composition.hasMelody ? 0.6 : 1
        for chord in composition.chords {
            let start = beat * Double(chord.start)
            let chordLength = beat * Double(chord.beats)
            let midis = composition.chord(chord.symbol).pitches.map(\.midi)
            switch style {
            case .together:
                // Ring to the next chord; its fade overlaps the next chord's start, so no gap.
                let gain = chordGain / Float(midis.count).squareRoot()
                notes += midis.map { .init(midi: $0, delay: start, duration: chordLength, gain: gain) }
            case .arpeggio:
                // An eighth note apart (closer if the chord is too short), each left ringing.
                let gap = min(beat / 2, chordLength / Double(midis.count))
                notes += midis.enumerated().map { i, midi in
                    let delay = start + Double(i) * gap
                    return .init(midi: midi, delay: delay, duration: start + chordLength - delay, gain: 0.8 * chordGain)
                }
            }
        }
        for note in composition.melody {
            notes.append(.init(midi: note.pitch.midi, delay: beat / 2 * Double(note.start),
                               duration: beat / 2 * Double(note.length), gain: 0.9))
        }
        return notes
    }
}
