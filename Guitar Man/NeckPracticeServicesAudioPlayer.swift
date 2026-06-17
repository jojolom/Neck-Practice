//
//  AudioPlayer.swift
//  Neck Practice
//
//  Plays guitar notes and chords using Karplus-Strong plucked-string synthesis.
//  Runs entirely in software — no soundbank files required, works on device and simulator.
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

    // MARK: - Engine
    private let engine = AVAudioEngine()
    private var isReady = false

    // Serialise access to active voices from the render thread and main thread.
    private let voiceLock = NSLock()
    private var voices: [KarplusVoice] = []

    // MARK: - Guitar tuning

    /// MIDI note numbers for open strings, index 0 = high e (string 1), index 5 = low E (string 6).
    /// Standard tuning: E4=64, B3=59, G3=55, D3=50, A2=45, E2=40
    private let openStringMidi: [UInt8] = [64, 59, 55, 50, 45, 40]

    private let noteDuration: TimeInterval = 1.0

    private init() {
        // Audio session must be configured before AVAudioEngine is created.
        AudioPlayer.configureAudioSession()
        setup()
    }

    // MARK: - Setup

    private static func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
        } catch {
            print("AudioPlayer: AVAudioSession setup failed: \(error)")
        }
    }

    private func setup() {

        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let monoFormat = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        let sourceNode = AVAudioSourceNode(format: monoFormat) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frameCount = Int(frameCount)

            self.voiceLock.lock()
            let activeVoices = self.voices
            self.voiceLock.unlock()

            for frame in 0..<frameCount {
                var sample: Float = 0
                for voice in activeVoices {
                    sample += voice.nextSample()
                }
                // Clamp to prevent clipping when many voices play simultaneously
                sample = max(-1, min(1, sample))
                for buffer in ablPointer {
                    let buf = buffer.mData!.assumingMemoryBound(to: Float.self)
                    buf[frame] = sample
                }
            }
            return noErr
        }

        engine.attach(sourceNode)

        // Connect using the same mono format the source node was created with.
        // AVAudioEngine will handle upmixing to stereo at the output stage.
        engine.connect(sourceNode, to: engine.mainMixerNode, format: monoFormat)

        do {
            try engine.start()
            isReady = true
        } catch {
            print("AudioPlayer: engine start failed: \(error)")
        }
    }

    // MARK: - Public API

    /// Play a single note at a comfortable mid-guitar octave (used when no position is available).
    func playNote(_ note: Note) {
        guard isReady else { return }
        let midi = midiNote(note, octave: 3)
        scheduleNote(midi: midi)
    }

    /// Play a single note at a specific octave.
    func playNote(_ note: Note, octave: Int) {
        guard isReady else { return }
        let midi = midiNote(note, octave: octave)
        scheduleNote(midi: midi)
    }

    /// Play a single note at its exact guitar pitch given a fretboard position.
    func playNote(at position: FretboardPosition) {
        guard isReady else { return }
        let midi = midiForPosition(position)
        scheduleNote(midi: midi)
    }

    /// Play a chord (multiple notes simultaneously), voiced at their actual guitar pitches.
    func playNotes(_ positions: [FretboardPosition]) {
        guard isReady else { return }
        for position in positions {
            let midi = midiForPosition(position)
            scheduleNote(midi: midi)
        }
    }

    /// Play positions as an arpeggio from low string to high, at actual guitar pitches.
    func playArpeggio(_ positions: [FretboardPosition]) {
        guard isReady else { return }
        let ordered = positions.sorted { $0.stringIndex > $1.stringIndex }
        for (i, position) in ordered.enumerated() {
            let midi = midiForPosition(position)
            let delay = Double(i) * 0.08
            if delay == 0 {
                scheduleNote(midi: midi)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.scheduleNote(midi: midi)
                }
            }
        }
    }

    /// Play a major or minor triad (root, 3rd, 5th) simultaneously.
    func playTriad(root: Note, isMajor: Bool, octave: Int = 3) {
        guard isReady else { return }
        let rootMidi = midiNote(root, octave: octave)
        let thirdOffset: UInt8 = isMajor ? 4 : 3  // major 3rd = 4, minor 3rd = 3
        let fifthOffset: UInt8 = 7                  // perfect 5th = 7
        scheduleNote(midi: rootMidi)
        scheduleNote(midi: rootMidi + thirdOffset)
        scheduleNote(midi: rootMidi + fifthOffset)
    }

    /// Stop all currently ringing voices so the next note plays cleanly.
    func stopAll() {
        voiceLock.lock()
        voices.removeAll()
        voiceLock.unlock()
    }

    // MARK: - Private helpers

    private func scheduleNote(midi: UInt8) {
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let voice = KarplusVoice(midi: midi, sampleRate: sampleRate)

        voiceLock.lock()
        voices.append(voice)
        voiceLock.unlock()

        DispatchQueue.main.asyncAfter(deadline: .now() + noteDuration) { [weak self] in
            guard let self else { return }
            self.voiceLock.lock()
            // Remove by object identity
            self.voices.removeAll { $0 === voice }
            self.voiceLock.unlock()
        }
    }

    private func midiForPosition(_ position: FretboardPosition) -> UInt8 {
        let stringIdx = min(position.stringIndex, openStringMidi.count - 1)
        let open = Int(openStringMidi[stringIdx])
        return UInt8(clamping: open + position.fret)
    }

    private func midiNote(_ note: Note, octave: Int) -> UInt8 {
        let raw = 12 * (octave + 1) + note.rawValue
        return UInt8(clamping: raw)
    }
}

// MARK: - KarplusVoice

/// Karplus-Strong plucked-string synthesis.
/// Fills a delay line with noise, then repeatedly averages adjacent samples
/// with a slight low-pass filter — this produces a realistic decaying string tone.
final class KarplusVoice {

    private var delayLine: [Float]
    private var writeIndex: Int = 0
    private let delayLength: Int
    private var amplitude: Float = 0.5
    // Decay factor: slightly less than 1.0 to fade out over ~1-2 seconds
    private let decay: Float = 0.996

    init(midi: UInt8, sampleRate: Double) {
        // Delay line length = sample rate / frequency
        let freq = 440.0 * pow(2.0, (Double(midi) - 69.0) / 12.0)
        delayLength = max(2, Int(sampleRate / freq))

        // Initialise delay line with white noise burst (the "pluck")
        delayLine = (0..<delayLength).map { _ in Float.random(in: -1...1) }
        writeIndex = 0
    }

    /// Returns the next output sample and advances the delay line.
    func nextSample() -> Float {
        let readIndex = writeIndex
        let nextIndex = (writeIndex + 1) % delayLength

        // Low-pass average of current and next sample (Karplus-Strong filter)
        let newSample = decay * 0.5 * (delayLine[readIndex] + delayLine[nextIndex])
        delayLine[writeIndex] = newSample
        writeIndex = nextIndex

        return newSample * amplitude
    }
}
