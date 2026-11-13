//
//  CompositionScribe.swift
//  Guitar Man
//
//  Writing a composition by playing it (Compose's Listen input). Listens through ChordListener
//  and, with ComposeHearing, works out each chord strummed or note plucked.
//
//  Step by step, it hands each one to `onChord` / `onNote` as it's played, and the editor writes
//  it at the cursor with the length chosen: there's no time to keep.
//
//  In time, `beginTake` counts in a measure of clicks, then notes when each chord or note was
//  played against the beat, until `endTake` hands the take back for the editor to write on the
//  nearest beats (see `Composition.write(chords:fromMeasure:)`). The click carries on through
//  the take only on headphones: from the speaker the mic would hear each click as a strum. Off
//  headphones the beat is shown instead (`takeClock`). A chord or note is timed from the strum
//  or pluck that started it, less what the audio hardware says its delay is, not from when it
//  was recognized a moment later.
//

import AVFoundation
import Foundation
import Observation

@Observable
final class CompositionScribe {

    enum Part { case chords, melody }

    /// When a take's first beat falls, and how long a beat is.
    struct TakeClock: Equatable {
        let start: Date
        let secondsPerBeat: Double
        let beatsPerMeasure: Int

        /// Beats since the take's first barline (negative during the count-in).
        func beat(at date: Date) -> Double { date.timeIntervalSince(start) / secondsPerBeat }
    }

    // MARK: Published

    private(set) var isListening = false
    private(set) var permissionDenied = false
    /// The name of what was heard last ("Am", "F♯"), to show, and when.
    private(set) var heard: String? = nil
    private(set) var heardAt = Date.distantPast
    /// A strum that wasn't made out, more recent than anything heard.
    private(set) var missedAt = Date.distantPast
    /// While a take is being played (count-in included).
    private(set) var takeClock: TakeClock? = nil
    /// Chords or notes in the take so far.
    private(set) var takeCount = 0
    /// Whether the click plays through the take (headphones) or only counts it in.
    private(set) var clicksThroughTake = false

    /// Microphone level, 0–1.
    var level: Float { listener.signalLevel }
    var isRecording: Bool { takeClock != nil }

    // MARK: Step by step

    var onChord: ((ChordSymbol) -> Void)? = nil
    var onNote: ((SpelledPitch) -> Void)? = nil
    /// The take ran to its last measure: the editor should end it.
    var onTakeFull: (() -> Void)? = nil

    // MARK: Private

    private let listener = ChordListener()
    private var part = Part.chords
    private var key = KeySignature.cMajor
    private var candidates: [CompositionChord] = []
    private var noteTracker = NoteTracker()
    private var chordTracker = ChordTracker()
    private var lastStrum = Date.distantPast
    private var strumPending = false
    private var chordTake: [Composition.Heard<ChordSymbol>] = []
    private var noteTake: [Composition.Heard<SpelledPitch>] = []
    private var takeTask: Task<Void, Never>? = nil
    /// Nothing heard before this counts: the app's own last sound is still in the air.
    private var deafUntil = Date.distantPast

    /// How long after a strum with nothing recognized it counts as missed (seconds).
    private static let missAfter: TimeInterval = 1.2
    /// From a pluck to its sound reaching the analysis, beyond what the hardware reports.
    private static let bufferDelay: TimeInterval = 0.03
    /// Below this microphone level (0–1) nothing is taken for playing: a guitar by the phone is
    /// well above it, the room mostly isn't.
    private static let quietLevel: Float = 0.15

    /// Starts listening for `part` in `composition`'s key. Call again when either changes.
    func listen(for part: Part, in composition: Composition) async {
        self.part = part
        key = composition.keySignature
        candidates = ComposeHearing.candidates(for: composition)
        noteTracker = NoteTracker()
        chordTracker = ChordTracker()
        guard !listener.isListening else { return }
        // A note the app just sounded would be heard and written.
        AudioPlayer.shared.stopAll()
        deafUntil = Date.now.addingTimeInterval(0.8)
        listener.tracksPitch = true
        listener.onStrum = { [weak self] in self?.strum() }
        listener.onAnalysis = { [weak self] chroma, frequency in self?.analyze(chroma, frequency) }
        await listener.start()
        isListening = listener.isListening
        permissionDenied = listener.permissionDenied
    }

    func stop() {
        cancelTake()
        listener.stop()
        listener.onStrum = nil
        listener.onAnalysis = nil
        isListening = false
        heard = nil
    }

    // MARK: Hearing

    private func strum() {
        guard Date.now >= deafUntil, listener.signalLevel >= Self.quietLevel else { return }
        lastStrum = .now
        strumPending = true
        noteTracker.attack()
        chordTracker.attack()
    }

    private func analyze(_ chroma: [Double], _ frequency: Double?) {
        guard Date.now >= deafUntil else { return }
        // Nothing counts during the count-in.
        if let takeClock, takeClock.beat(at: .now) < -0.4 { return }
        switch part {
        case .chords:
            let symbol = ComposeHearing.chord(in: chroma, candidates: candidates)?.symbol
            if let played = chordTracker.hear(symbol) {
                note(heard: candidates.first { $0.symbol == played }?.name ?? "")
                if isRecording {
                    chordTake.append(.init(beat: beatOfAttack, value: played))
                    takeCount = chordTake.count
                } else {
                    onChord?(played)
                }
            }
        case .melody:
            if let midi = noteTracker.hear(ComposeHearing.midi(frequency: frequency, chroma: chroma)) {
                let pitch = ComposeHearing.spell(midi: midi, in: key)
                note(heard: pitch.name)
                if isRecording {
                    noteTake.append(.init(beat: beatOfAttack, value: pitch))
                    takeCount = noteTake.count
                } else {
                    onNote?(pitch)
                }
            }
        }
        if strumPending && Date.now.timeIntervalSince(lastStrum) > Self.missAfter {
            strumPending = false
            missedAt = .now
        }
    }

    private func note(heard name: String) {
        heard = name
        heardAt = .now
        strumPending = false
    }

    /// Where in the take what was just recognized was played, in beats: when it was strummed
    /// or plucked, not when it was made out a moment later.
    private var beatOfAttack: Double {
        guard let takeClock else { return 0 }
        let session = AVAudioSession.sharedInstance()
        // The player hears the click late by the output's delay and plays to that; the mic
        // then adds its own.
        let delay = session.outputLatency + session.inputLatency + Self.bufferDelay
        return takeClock.beat(at: lastStrum.addingTimeInterval(-delay))
    }

    // MARK: Takes

    /// Counts in one measure, then times what's played until `endTake`, for at most `measures`.
    func beginTake(bpm: Int, beatsPerMeasure: Int, measures: Int) {
        cancelTake()
        let beat = 60 / Double(min(max(bpm, CompositionPlayer.tempoRange.lowerBound), CompositionPlayer.tempoRange.upperBound))
        clicksThroughTake = Self.onHeadphones
        let clicked = clicksThroughTake ? (measures + 1) * beatsPerMeasure : beatsPerMeasure
        AudioPlayer.shared.play((0..<clicked).map {
            .init(midi: 0, delay: beat * Double($0), sound: $0 % beatsPerMeasure == 0 ? .accentClick : .click)
        })
        let countIn = beat * Double(beatsPerMeasure)
        chordTake = []
        noteTake = []
        takeCount = 0
        noteTracker = NoteTracker()
        chordTracker = ChordTracker()
        strumPending = false
        takeClock = TakeClock(start: Date.now.addingTimeInterval(countIn), secondsPerBeat: beat, beatsPerMeasure: beatsPerMeasure)
        takeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(countIn + beat * Double(measures * beatsPerMeasure)))
            guard !Task.isCancelled else { return }
            self?.onTakeFull?()
        }
    }

    /// Ends the take and hands back what was played.
    func endTake() -> (chords: [Composition.Heard<ChordSymbol>], notes: [Composition.Heard<SpelledPitch>]) {
        let take = (chordTake, noteTake)
        cancelTake()
        return take
    }

    private func cancelTake() {
        guard takeClock != nil else { return }
        takeTask?.cancel()
        takeTask = nil
        takeClock = nil
        AudioPlayer.shared.stopAll()
        chordTake = []
        noteTake = []
    }

    /// Whether sound is going to headphones (wired or Bluetooth) rather than the speaker.
    static var onHeadphones: Bool {
        let ports: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .usbAudio]
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { ports.contains($0.portType) }
    }
}
