//
//  CompositionPlayer.swift
//  Guitar Man
//
//  Plays a composition aloud, from the Play button in the editor's bottom bar: all of it, or
//  the measures selected, once or in a loop, optionally after a measure of clicks. `audition`
//  sounds one chord or note as it's written or picked.
//
//  Each chord sounds once, on its beat, and rings for its length (rests are silent): its notes
//  either all at once, as an arpeggio (low to high, an eighth note apart, each left ringing), or
//  strummed or fingerpicked in a pattern for as long as it lasts.
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
    /// Strummed, or fingerpicked, in a pattern on the chord's guitar shape for as long as the
    /// chord lasts: Solo Buddy's patterns (see `SoloGroove.hits(for:style:)`).
    case strummed, fingerpicked

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .together:     return "Together"
        case .arpeggio:     return "Arpeggio"
        case .strummed:     return "Strummed"
        case .fingerpicked: return "Fingerpicked"
        }
    }

    /// The Solo Buddy pattern it plays, if it's one of those.
    var backing: BackingStyle? {
        switch self {
        case .strummed:     return .strummed
        case .fingerpicked: return .fingerpicked
        default:            return nil
        }
    }
}

@Observable
final class CompositionPlayer {

    /// UserDefaults keys for Hear Compositions in Compose Settings.
    /// Chords and notes sound as they're written or picked on the staff.
    static let tapSoundsKey = "compose.tapSounds"
    static let loopKey = "compose.loop"
    static let countInKey = "compose.countIn"
    static let styleKey = "compose.playbackStyle"
    static let tempoKey = "compose.playbackBPM"

    static let defaultTempo = 90
    static let tempoRange = 40...200

    /// Start beat of the chord being heard, or nil (stopped, or in a rest).
    private(set) var playingChord: Int?
    /// Start tick of the melody note being heard, or nil.
    private(set) var playingNote: Int?
    /// The measure being played (rests included), or nil.
    private(set) var playingMeasure: Int?
    /// When the first beat sounded and how long a beat is, while playing: where the playhead is.
    private(set) var clock: Playhead?
    private(set) var isPlaying = false
    /// In the measure of clicks before it starts.
    private(set) var isCountingIn = false

    /// The beat sounding at a moment (fractional, from 0), for drawing a playhead.
    struct Playhead: Equatable {
        let start: Date
        let secondsPerBeat: Double

        func beat(at date: Date) -> Double { max(0, date.timeIntervalSince(start) / secondsPerBeat) }
    }

    private var task: Task<Void, Never>?
    private var interruptionObserver: (any NSObjectProtocol)?
    /// What's playing, to carry on with after a change or at the end of a loop.
    private var current: (composition: Composition, style: CompositionPlaybackStyle, bpm: Int,
                          measures: Range<Int>?, loops: Bool)?

    /// Something changed while it's playing: plays on from the first beat of the measure you're
    /// in, with the change.
    func restartMeasure(_ composition: Composition, style: CompositionPlaybackStyle, bpm: Int) {
        guard isPlaying, let current else { return }
        let measures = current.measures.map { $0.clamped(to: 0..<composition.measureCount) }
        let from = playingMeasure ?? 0
        start(composition, style: style, bpm: bpm, measures: measures?.isEmpty == true ? nil : measures,
              loops: current.loops, countIn: false, fromMeasure: from)
    }

    /// Looping turned on or off while it plays: takes effect at the end of this pass.
    func setLoops(_ loops: Bool) { current?.loops = loops }

    /// Plays `composition`, or just `measures` of it; with `loops`, round and round until
    /// stopped; with `countIn`, after a measure of clicks.
    func play(_ composition: Composition, style: CompositionPlaybackStyle, bpm: Int,
              measures: Range<Int>? = nil, loops: Bool = false, countIn: Bool = false) {
        start(composition, style: style, bpm: bpm, measures: measures, loops: loops, countIn: countIn,
              fromMeasure: measures?.lowerBound ?? 0)
    }

    private func start(_ composition: Composition, style: CompositionPlaybackStyle, bpm: Int,
                       measures: Range<Int>?, loops: Bool, countIn: Bool, fromMeasure: Int) {
        stop()
        guard !composition.isEmpty else { return }
        let beat = 60 / Double(min(max(bpm, Self.tempoRange.lowerBound), Self.tempoRange.upperBound))
        let tick = beat / Double(Composition.ticksPerBeat)
        let perBeat = Composition.ticksPerBeat
        let ticksPerMeasure = composition.ticksPerMeasure
        let range = measures ?? 0..<composition.measureCount
        let rangeStart = range.lowerBound * ticksPerMeasure, rangeEnd = range.upperBound * ticksPerMeasure
        let firstMeasure = range.contains(fromMeasure) ? fromMeasure : range.lowerBound
        let firstTick = firstMeasure * ticksPerMeasure

        // Highlight each chord and note while it sounds, and nothing in the rests between:
        // (time in ticks, which line, start or nil to clear).
        // (A measure event sets `playingMeasure` and nothing else.)
        var events: [(tick: Int, isChord: Bool, start: Int?, measure: Int?)] = []
        for chord in composition.chords where (rangeStart..<rangeEnd).contains(chord.start * perBeat) {
            events.append((chord.start * perBeat, true, chord.start, nil))
            if !composition.chords.contains(where: { $0.start == chord.end }) { events.append((chord.end * perBeat, true, nil, nil)) }
        }
        for note in composition.melody where (rangeStart..<rangeEnd).contains(note.start) {
            events.append((note.start, false, note.start, nil))
            if !composition.melody.contains(where: { $0.start == note.end }) { events.append((note.end, false, nil, nil)) }
        }
        // Nothing to hear in these measures.
        guard let lastSound = events.map(\.tick).max() else { return }
        // Rests are silent, and a piece played once ends with its last chord or note rather than
        // empty measures; a loop, or chosen measures, plays through to the barline to keep time.
        let end = measures != nil ? rangeEnd
            : loops ? (lastSound + ticksPerMeasure - 1) / ticksPerMeasure * ticksPerMeasure : lastSound
        // The measure it was in is gone (or everything after it is): nothing left to play.
        guard end > firstTick else { return }

        let lead = countIn ? beat * Double(composition.beatsPerMeasure) : 0
        let skipped = tick * Double(firstTick), stopAt = tick * Double(end)
        var scheduled: [AudioPlayer.ScheduledNote] = Self.notes(for: composition, style: style, beat: beat).compactMap { note in
            // What's still sounding where it starts (a chord or note tied from before) comes in
            // there, and nothing rings past where it stops.
            let ends = note.delay + (note.duration ?? 0)
            guard note.delay < stopAt - 0.001, note.delay >= skipped - 0.001 || ends > skipped + 0.05 else { return nil }
            var note = note
            if note.duration != nil { note.duration = min(ends, stopAt) - max(note.delay, skipped) }
            note.delay = max(note.delay - skipped, 0) + lead
            return note
        }
        if countIn {
            scheduled += (0..<composition.beatsPerMeasure).map {
                .init(midi: 0, delay: beat * Double($0), sound: $0 == 0 ? .accentClick : .click)
            }
        }
        AudioPlayer.shared.play(scheduled)

        // Each measure as it's reached, through to the one the piece ends in.
        for measure in firstMeasure..<max((end + ticksPerMeasure - 1) / ticksPerMeasure, firstMeasure + 1) {
            events.append((measure * ticksPerMeasure, false, nil, measure))
        }
        // Clearing first, so a chord ending where another starts doesn't blank the new one.
        events.sort { $0.tick != $1.tick ? $0.tick < $1.tick : ($0.start == nil && $1.start != nil) }
        events.removeAll { $0.tick < firstTick || $0.tick > end }

        current = (composition, style, bpm, measures, loops)
        isPlaying = true
        isCountingIn = countIn
        clock = Playhead(start: Date.now.addingTimeInterval(lead - skipped), secondsPerBeat: beat)
        playingMeasure = countIn ? nil : firstMeasure
        interruptionObserver = AudioSessionSetup.observe(AVAudioSession.interruptionNotification) { [weak self] _ in
            self?.stop()
        }
        task = Task { [weak self] in
            let clock = ContinuousClock()
            let start = clock.now.advanced(by: .seconds(lead))
            do {
                for event in events {
                    try await clock.sleep(until: start.advanced(by: .seconds(tick * Double(event.tick - firstTick))))
                    self?.isCountingIn = false
                    if let measure = event.measure {
                        self?.playingMeasure = measure
                    } else if event.isChord {
                        self?.playingChord = event.start
                    } else {
                        self?.playingNote = event.start
                    }
                }
                try await clock.sleep(until: start.advanced(by: .seconds(tick * Double(end - firstTick))))
            } catch {
                return  // stopped
            }
            guard let self else { return }
            if let current = self.current, current.loops {
                self.start(current.composition, style: current.style, bpm: current.bpm, measures: current.measures,
                           loops: true, countIn: false, fromMeasure: range.lowerBound)
            } else {
                self.finish()
            }
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
        isCountingIn = false
        current = nil
        playingChord = nil
        playingNote = nil
        playingMeasure = nil
        clock = nil
    }

    /// Sounds one chord, as it's written or picked on the staff.
    static func audition(_ chord: CompositionChord, style: CompositionPlaybackStyle) {
        let midis = chord.pitches.map(\.midi)
        switch style {
        case .together:
            let gain = 1 / Float(midis.count).squareRoot()
            AudioPlayer.shared.play(midis.map { .init(midi: $0, duration: 1.2, gain: gain) })
        case .arpeggio:
            AudioPlayer.shared.play(midis.enumerated().map { .init(midi: $1, delay: Double($0) * 0.12, duration: 1.2, gain: 0.8) })
        case .strummed, .fingerpicked:
            // On the guitar shape: one strum, or picked up through the strings.
            let shape = SoloGroove.shape(for: chord)
            let roll = style == .strummed ? 0.014 : 0.11
            let gain = style == .strummed ? 1 / Float(max(shape.count, 1)).squareRoot() : 0.75
            AudioPlayer.shared.play(shape.enumerated().map { .init(midi: $1, delay: Double($0) * roll, duration: 1.4, gain: gain) })
        }
    }

    /// Sounds one melody note.
    static func audition(_ pitch: SpelledPitch) {
        AudioPlayer.shared.play([.init(midi: pitch.midi, duration: 0.8, gain: 0.9)])
    }

    /// Every note of the piece on one timeline (seconds from the start). A chord or note tied
    /// to the next sounds once, for the length of both.
    static func notes(for composition: Composition, style: CompositionPlaybackStyle,
                      beat: Double) -> [AudioPlayer.ScheduledNote] {
        var notes: [AudioPlayer.ScheduledNote] = []
        // Under a melody, the chords step back a little.
        let chordGain: Float = composition.hasMelody ? 0.6 : 1
        if let backing = style.backing {
            // The pattern from the top for each chord, for as long as it lasts; through a tie it
            // just carries on.
            var patterns: [ChordSymbol: [SoloGroove.Hit]] = [:]
            for chord in composition.chords {
                let start = beat * Double(chord.start), length = Double(chord.beats)
                let hits = patterns[chord.symbol] ?? SoloGroove.hits(for: composition.chord(chord.symbol), style: backing)
                patterns[chord.symbol] = hits
                for hit in hits where hit.beat < length - 0.01 {
                    notes.append(.init(midi: hit.midi, delay: start + hit.beat * beat + hit.roll,
                                       duration: min(hit.beats, length - hit.beat) * beat, gain: hit.gain * chordGain))
                }
            }
        } else {
            for chord in composition.struckChords {
                let start = beat * Double(chord.start)
                let chordLength = beat * Double(composition.soundingBeats(of: chord))
                let midis = composition.chord(chord.symbol).pitches.map(\.midi)
                if style == .arpeggio {
                    // An eighth note apart (closer if the chord is too short), each left ringing.
                    let gap = min(beat / 2, chordLength / Double(midis.count))
                    notes += midis.enumerated().map { i, midi in
                        let delay = start + Double(i) * gap
                        return .init(midi: midi, delay: delay, duration: start + chordLength - delay, gain: 0.8 * chordGain)
                    }
                } else {
                    // Ring to the next chord; its fade overlaps the next chord's start, so no gap.
                    let gain = chordGain / Float(midis.count).squareRoot()
                    notes += midis.map { .init(midi: $0, delay: start, duration: chordLength, gain: gain) }
                }
            }
        }
        let tick = beat / Double(Composition.ticksPerBeat)
        for note in composition.struckMelody {
            notes.append(.init(midi: note.pitch.midi, delay: tick * Double(note.start),
                               duration: tick * Double(composition.soundingTicks(of: note)), gain: 0.9))
        }
        return notes
    }
}

// MARK: - Solo Buddy

extension Composition {

    /// The composition's chords as a Solo Buddy groove to solo over: the chord each measure
    /// starts on (a measure with none carries on the one before), each lasting one bar, or two
    /// if they all come in pairs. Solo Buddy loops four chords at most, so `isWhole` says
    /// whether that's the whole progression, with every measure on a single chord.
    var soloGroove: (groove: SoloGroove, isWhole: Bool)? {
        var bars: [ChordSymbol] = []
        var simple = true
        let lastUsed = (chords.last.map { ($0.end - 1) / beatsPerMeasure }) ?? -1
        for measure in 0..<(lastUsed + 1) {
            let first = measure * beatsPerMeasure
            let inMeasure = chords.filter { $0.start >= first && $0.start < first + beatsPerMeasure }
            if inMeasure.count > 1 || (inMeasure.first.map { $0.start != first } ?? false) { simple = false }
            if let symbol = (chord(covering: first) ?? inMeasure.first)?.symbol ?? bars.last {
                bars.append(symbol.rootPosition)
            }
        }
        guard !bars.isEmpty else { return nil }
        var barsPerChord = 1
        if bars.count % 2 == 0, stride(from: 0, to: bars.count, by: 2).allSatisfy({ bars[$0] == bars[$0 + 1] }) {
            bars = stride(from: 0, to: bars.count, by: 2).map { bars[$0] }
            barsPerChord = 2
        }
        let limit = SoloGroove.chordRange.upperBound
        var groove = SoloGroove()
        groove.keyRoot = keyRoot
        groove.isMinor = isMinor
        groove.chords = Array(bars.prefix(limit))
        groove.form = .loop
        groove.style = beatsPerMeasure == 3 ? .waltz : .strummed
        groove.bpm = min(max(tempo ?? groove.style.defaultBPM, SoloGroove.tempoRange.lowerBound), SoloGroove.tempoRange.upperBound)
        groove.barsPerChord = barsPerChord
        groove.scale = isMinor ? .minor : .major
        groove.presetID = nil
        groove.savedID = nil
        return (groove, simple && bars.count <= limit)
    }
}
