//
//  ClickSound.swift
//  Guitar Man
//
//  The metronome click, shared: the Metronome plays it from buffers on its own engine, and
//  AudioPlayer plays it as a voice (ClickVoice) on the same timeline as guitar notes, for Solo
//  Buddy's count-in and click. No UI here.
//

import Foundation

nonisolated enum ClickSound {

    /// A beat's click and the first beat's (accented) click: pitch and length.
    static let beat = (frequency: 800.0, duration: 0.06)
    static let accent = (frequency: 1200.0, duration: 0.07)
    static let subdivision = (frequency: 1000.0, duration: 0.04)

    /// A short click: a tone with its 2nd and 3rd harmonics, decaying fast, driven into soft
    /// saturation. It peaks just under full scale like a plain sine click would, but carries
    /// about 9 dB more sound (a plain sine is all peak and little body, and phone speakers favour
    /// the brighter harmonics), so it cuts through a strummed guitar. A 4 ms fade ends it cleanly.
    static func samples(frequency: Double, duration: Double, sampleRate: Double, gain: Float = 1) -> [Float] {
        let count = Int(sampleRate * duration)
        let drive = 6.0
        let fadeFrames = Int(sampleRate * 0.004)
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            let phase = 2.0 * .pi * frequency * t
            let tone = (sin(phase) + 0.5 * sin(2 * phase) + 0.25 * sin(3 * phase)) / 1.4
            let saturated = tanh(drive * exp(-t * 40) * tone) / tanh(drive)
            let fade = min(1, Double(count - i) / Double(fadeFrames))
            return gain * Float(0.97 * saturated * fade)
        }
    }
}

/// A click on AudioPlayer's timeline.
nonisolated final class ClickVoice: NoteVoice {

    private let samples: [Float]
    private var envelope: NoteEnvelope
    private var position = 0

    var isFinished: Bool { envelope.isFinished }

    init(accent: Bool, sampleRate: Double, startFrame: Int64, releaseFrames: Int, gain: Float) {
        let sound = accent ? ClickSound.accent : ClickSound.beat
        samples = ClickSound.samples(frequency: sound.frequency, duration: sound.duration,
                                     sampleRate: sampleRate, gain: gain)
        envelope = NoteEnvelope(startFrame: startFrame, releaseFrame: startFrame + Int64(samples.count),
                                releaseFrames: releaseFrames)
    }

    func isSounding(at frame: Int64) -> Bool { envelope.isSounding(at: frame) }

    func release(at frame: Int64, fadeFrames: Int) { envelope.release(at: frame, fadeFrames: fadeFrames) }

    func render(into out: UnsafeMutablePointer<Float>, count: Int, bufferStart: Int64) {
        guard let first = envelope.firstFrame(bufferStart: bufferStart, count: count) else { return }
        for i in first..<count {
            guard position < samples.count, let level = envelope.level(at: bufferStart + Int64(i)) else {
                envelope.finish()
                return
            }
            out[i] += samples[position] * level
            position += 1
        }
    }
}
