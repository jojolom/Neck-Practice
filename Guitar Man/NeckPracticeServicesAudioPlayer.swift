//
//  AudioPlayer.swift
//  Neck Practice
//
//  Plays guitar notes and chords: a recorded nylon-string guitar (GuitarSamples), loaded in the
//  background at launch; until it's ready, or if it can't load, a synthesized plucked string
//  (PluckedString). Both play exactly in tune — checked offline by scripts/sampler-check.swift
//  and scripts/synth-check.swift.
//
//  Every note is placed on the audio timeline to the sample, so chords start together and
//  sequences (`play(_:)`) keep exact time however busy the main thread is. Notes ring for a
//  set time and then fade out over a few milliseconds instead of being cut (which clicks).
//

import AVFoundation
import Observation

// MARK: - AudioSettings

/// Global toggle shared across all modules.
@Observable
final class AudioSettings {
    var isEnabled: Bool = true
}

// MARK: - AudioPlayer

final class AudioPlayer {

    static let shared = AudioPlayer()

    /// A note for `play(_:)`: its MIDI number, when it starts (seconds after the call), how long
    /// it rings before fading out (nil for the default), and its loudness (1 = a single note).
    struct ScheduledNote {
        var midi: Int
        var delay: TimeInterval = 0
        var duration: TimeInterval? = nil
        var gain: Float = 1
    }

    // MARK: - Engine
    private let engine = AVAudioEngine()
    /// True once the node graph is built (the engine itself is started on demand).
    private var isReady = false
    /// Rate the voices are synthesized at: the source node's format, fixed when the graph is
    /// built. (The output's rate can change later, e.g. with Bluetooth; the mixer converts.)
    private var sampleRate: Double = 48000

    /// Guards `voices` and `renderedFrames`, shared by the render thread and the main thread.
    private let voiceLock = NSLock()
    private var voices: [any NoteVoice] = []
    /// Loudness (RMS) of a single recorded note's attack at gain 1.
    private let sampleLevel = 0.12
    /// Timeline position (in frames) of the next buffer to render.
    private var renderedFrames: Int64 = 0

    /// How long a note rings, when not given, before it fades out.
    private let defaultDuration: TimeInterval = 1.6
    /// Fade at the end of a note, and when notes are stopped.
    private let releaseTime: TimeInterval = 0.08
    private let stopFadeTime: TimeInterval = 0.025
    /// Voices beyond this (counting only ones sounding) fade out oldest first.
    private let maxSounding = 24

    // MARK: - Guitar tuning

    /// MIDI note numbers for open strings, index 0 = high e (string 1), index 5 = low E (string 6).
    /// Standard tuning: E4=64, B3=59, G3=55, D3=50, A2=45, E2=40
    private let openStringMidi: [Int] = [64, 59, 55, 50, 45, 40]

    private init() {
        // Audio session must be configured before AVAudioEngine is created.
        AudioPlayer.configureAudioSession()
        setup()
    }

    // MARK: - Setup

    private static func configureAudioSession() {
        do {
            try AudioSessionSetup.activatePlayback()
        } catch {
            print("AudioPlayer: AVAudioSession setup failed: \(error)")
        }
    }

    private func setup() {

        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        if outputRate > 0 { sampleRate = outputRate }
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        let sourceNode = AVAudioSourceNode(format: monoFormat) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let count = Int(frameCount)
            guard let out = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            out.update(repeating: 0, count: count)

            self.voiceLock.lock()
            let bufferStart = self.renderedFrames
            for voice in self.voices {
                voice.render(into: out, count: count, bufferStart: bufferStart)
            }
            self.voices.removeAll { $0.isFinished }
            self.renderedFrames += Int64(count)
            self.voiceLock.unlock()

            // Gentle saturation instead of a hard clip when many notes sound together.
            for i in 0..<count { out[i] = Self.softClip(out[i]) }
            for buffer in buffers.dropFirst() {
                buffer.mData?.assumingMemoryBound(to: Float.self).update(from: out, count: count)
            }
            return noErr
        }

        engine.attach(sourceNode)

        // Connect using the same mono format the source node was created with.
        // AVAudioEngine will handle upmixing to stereo at the output stage.
        engine.connect(sourceNode, to: engine.mainMixerNode, format: monoFormat)
        isReady = true
        startEngineIfNeeded()
        // Normally already started at launch; the synth plays until the recordings are ready.
        GuitarSampleBank.preload()
    }

    /// iOS stops the engine for calls, Siri, alarms and route changes (and when the tuner or
    /// looper switch the session to recording), so start it again before playing. False if it
    /// can't run right now, e.g. during a call.
    @discardableResult
    private func startEngineIfNeeded() -> Bool {
        guard !engine.isRunning else { return true }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            return true
        } catch {
            print("AudioPlayer: engine start failed: \(error)")
            return false
        }
    }

    /// Linear up to ±0.5, then rounds off smoothly toward ±1.
    nonisolated private static func softClip(_ x: Float) -> Float {
        let a = abs(x)
        guard a > 0.5 else { return x }
        let over = a - 0.5
        let shaped = 0.5 + over / (1 + over * 2)  // approaches 1 as `over` grows
        return x < 0 ? -shaped : shaped
    }

    // MARK: - Public API

    /// Play a single note at a comfortable mid-guitar octave (used when no position is available).
    func playNote(_ note: Note) {
        playNote(note, octave: 3)
    }

    /// Play a single note at a specific octave.
    func playNote(_ note: Note, octave: Int) {
        play([ScheduledNote(midi: Self.midi(note, octave: octave))])
    }

    /// Play a single note at its exact guitar pitch given a fretboard position.
    func playNote(at position: FretboardPosition) {
        play([ScheduledNote(midi: midiForPosition(position))])
    }

    /// Play a chord (multiple notes simultaneously), voiced at their actual guitar pitches.
    func playNotes(_ positions: [FretboardPosition]) {
        play(chord: positions.map(midiForPosition))
    }

    /// Play positions as an arpeggio from low string to high, at actual guitar pitches.
    func playArpeggio(_ positions: [FretboardPosition]) {
        let ordered = positions.sorted { $0.stringIndex > $1.stringIndex }
        play(ordered.enumerated().map { i, position in
            ScheduledNote(midi: midiForPosition(position), delay: Double(i) * 0.08)
        })
    }

    /// Play a major or minor triad (root, 3rd, 5th) simultaneously.
    func playTriad(root: Note, isMajor: Bool, octave: Int = 3) {
        let rootMidi = Self.midi(root, octave: octave)
        play(chord: [rootMidi, rootMidi + (isMajor ? 4 : 3), rootMidi + 7])
    }

    /// Play notes at the same instant, like a block chord.
    func playChord(_ notes: [(note: Note, octave: Int)]) {
        play(chord: notes.map { Self.midi($0.note, octave: $0.octave) })
    }

    /// Play notes on one timeline: each starts `delay` after this call, to the sample, so
    /// rhythms stay exact. Notes that start together are a chord.
    func play(_ notes: [ScheduledNote]) {
        guard isReady, !notes.isEmpty, startEngineIfNeeded() else { return }
        voiceLock.lock()
        defer { voiceLock.unlock() }
        let now = renderedFrames
        let releaseFrames = Int(releaseTime * sampleRate)
        let sampleBank = GuitarSampleBank.shared
        for note in notes {
            let start = now + Int64((max(note.delay, 0) * sampleRate).rounded())
            let ring = Int64(((note.duration ?? defaultDuration) * sampleRate).rounded())
            if let sampleBank {
                voices.append(SampledNote(midi: note.midi, recording: sampleBank.recording(for: note.midi),
                                          outputRate: sampleRate, startFrame: start, releaseFrame: start + max(ring, 1),
                                          releaseFrames: releaseFrames,
                                          gain: Float(sampleLevel / sampleBank.attackRMS) * note.gain))
            } else {
                voices.append(PluckedString(midi: note.midi, sampleRate: sampleRate, startFrame: start,
                                            releaseFrame: start + max(ring, 1), releaseFrames: releaseFrames,
                                            gain: 0.5 * note.gain))
            }
        }
        limitPolyphony(now: now)
    }

    /// Fade out everything that's ringing and cancel notes that haven't started yet.
    func stopAll() {
        voiceLock.lock()
        let now = renderedFrames
        let fade = Int(stopFadeTime * sampleRate)
        for voice in voices { voice.release(at: now, fadeFrames: fade) }
        voiceLock.unlock()
    }

    /// MIDI number of `note` in `octave` (middle C is C4 = 60).
    static func midi(_ note: Note, octave: Int) -> Int {
        12 * (octave + 1) + note.rawValue
    }

    // MARK: - Private helpers

    /// Equal loudness for chords: each note a little quieter the more there are.
    private func play(chord midis: [Int]) {
        let gain = 1 / Float(max(midis.count, 1)).squareRoot()
        play(midis.map { ScheduledNote(midi: $0, gain: gain) })
    }

    /// Fades out the oldest sounding voices when too many ring at once. Call with the lock held.
    private func limitPolyphony(now: Int64) {
        let sounding = voices.filter { $0.isSounding(at: now) }
        guard sounding.count > maxSounding else { return }
        let fade = Int(stopFadeTime * sampleRate)
        for voice in sounding.prefix(sounding.count - maxSounding) {
            voice.release(at: now, fadeFrames: fade)
        }
    }

    private func midiForPosition(_ position: FretboardPosition) -> Int {
        let stringIdx = min(position.stringIndex, openStringMidi.count - 1)
        return openStringMidi[stringIdx] + position.fret
    }
}
