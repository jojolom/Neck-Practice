//
//  PluckedString.swift
//  Guitar Man
//
//  The voices behind AudioPlayer: what every note has in common (NoteVoice, NoteEnvelope) and
//  the synthesized string, used until the recorded guitar (GuitarSamples) has loaded, or if it
//  can't. Pure Swift (no AVFoundation) so it can be checked offline — see scripts/synth-check.swift.
//

import Foundation

// MARK: - NoteVoice

/// One sounding note on AudioPlayer's timeline. All state is touched only with AudioPlayer's
/// lock held (on the render thread, or the main thread when scheduling and stopping).
nonisolated protocol NoteVoice: AnyObject {
    var isFinished: Bool { get }
    /// Whether the note is ringing (started, not yet fading) at timeline frame `frame`.
    func isSounding(at frame: Int64) -> Bool
    /// Start fading out at `frame` (or sooner, if a fade is already due), over `fadeFrames`.
    func release(at frame: Int64, fadeFrames: Int)
    /// Adds this note's samples for timeline frames bufferStart..<bufferStart+count into `out`.
    func render(into out: UnsafeMutablePointer<Float>, count: Int, bufferStart: Int64)
}

// MARK: - NoteEnvelope

/// When a note starts, and its fade-out: linear over `releaseFrames` from `releaseFrame`.
nonisolated struct NoteEnvelope {
    let startFrame: Int64
    private(set) var releaseFrame: Int64
    private var releaseFrames: Int
    private var releaseProgress = 0
    private(set) var isFinished = false

    init(startFrame: Int64, releaseFrame: Int64, releaseFrames: Int) {
        self.startFrame = startFrame
        self.releaseFrame = releaseFrame
        self.releaseFrames = max(releaseFrames, 1)
    }

    func isSounding(at frame: Int64) -> Bool {
        !isFinished && frame >= startFrame && frame < releaseFrame
    }

    mutating func release(at frame: Int64, fadeFrames: Int) {
        if frame <= startFrame {
            isFinished = true  // never started: just drop it
            return
        }
        if frame < releaseFrame {
            releaseFrame = frame
            releaseFrames = max(fadeFrames, 1)
        } else if releaseFrames - releaseProgress > fadeFrames {
            // Already fading (or about to): finish within `fadeFrames` at most.
            releaseFrames = releaseProgress + max(fadeFrames, 1)
        }
    }

    /// Index in a buffer starting at `bufferStart` of the note's first frame, or nil if it
    /// doesn't start within `count` frames (or is finished).
    func firstFrame(bufferStart: Int64, count: Int) -> Int? {
        guard !isFinished, bufferStart + Int64(count) > startFrame else { return nil }
        return Int(max(0, startFrame - bufferStart))
    }

    /// The level (0–1) for timeline frame `frame`, advancing the fade; nil once it has faded out.
    mutating func level(at frame: Int64) -> Float? {
        guard frame >= releaseFrame else { return 1 }
        let level = 1 - Float(releaseProgress) / Float(releaseFrames)
        releaseProgress += 1
        if releaseProgress >= releaseFrames {
            isFinished = true
            return nil
        }
        return level
    }

    mutating func finish() { isFinished = true }
}

// MARK: - PluckedString

/// One plucked note: Karplus-Strong synthesis. A delay line one period long is filled with a
/// noise burst (the pluck), then fed back through a gentle low-pass, so the tone decays and
/// mellows like a string. Tuned exactly: the loop's delay is the delay line plus half a sample
/// (the low-pass) plus a fractional all-pass, adding up to one period. Each pitch gets its own
/// loop gain so notes ring for a natural time (longer low, shorter high).
nonisolated final class PluckedString: NoteVoice {

    private var envelope: NoteEnvelope
    /// When the note has decayed to silence on its own.
    private let endFrame: Int64

    private var delayLine: [Float]
    private var index = 0
    private var previous: Float = 0   // last delayed sample, for the low-pass
    private var allpassIn: Float = 0
    private var allpassOut: Float = 0
    private let allpassCoefficient: Float
    private let loopGain: Float
    private let gain: Float

    var isFinished: Bool { envelope.isFinished }

    /// Seconds for the note's fundamental to fade by 60 dB on its own, like a real string: about
    /// 10 s for low E, 5 s for the open high e, shorter up the neck. (Its brighter overtones fade
    /// sooner, so it still sounds plucked.) Most notes are faded out well before this.
    static func ringTime(midi: Int) -> Double {
        10 * pow(2, -Double(midi - 40) / 24)
    }

    init(midi: Int, sampleRate: Double, startFrame: Int64, releaseFrame: Int64,
         releaseFrames: Int, gain: Float) {
        envelope = NoteEnvelope(startFrame: startFrame, releaseFrame: releaseFrame, releaseFrames: releaseFrames)
        self.gain = gain

        let frequency = 440 * pow(2, Double(midi - 69) / 12)
        let period = sampleRate / frequency
        // Delay line N + low-pass 0.5 + all-pass Δ = period, with Δ kept in 0.1..<1.1 for a
        // well-behaved all-pass.
        let length = max(2, Int((period - 0.6).rounded(.down)))
        let fraction = period - 0.5 - Double(length)
        allpassCoefficient = Float((1 - fraction) / (1 + fraction))

        let ringTime = Self.ringTime(midi: midi)
        // Per period the loop scales the fundamental by loopGain × cos(π f / sr) (the low-pass);
        // pick loopGain so that reaches -60 dB after `ringTime`.
        let perPeriod = pow(10, -3 / (frequency * ringTime))
        loopGain = Float(min(perPeriod / cos(Double.pi * frequency / sampleRate), 0.99995))
        endFrame = startFrame + Int64(ringTime * sampleRate)

        // The pluck: white noise with its average removed, so the string has no DC offset.
        var noise = (0..<length).map { _ in Float.random(in: -1...1) }
        let mean = noise.reduce(0, +) / Float(length)
        for i in noise.indices { noise[i] -= mean }
        delayLine = noise
    }

    func isSounding(at frame: Int64) -> Bool { envelope.isSounding(at: frame) }

    func release(at frame: Int64, fadeFrames: Int) { envelope.release(at: frame, fadeFrames: fadeFrames) }

    func render(into out: UnsafeMutablePointer<Float>, count: Int, bufferStart: Int64) {
        guard let first = envelope.firstFrame(bufferStart: bufferStart, count: count) else { return }
        let length = delayLine.count
        for i in first..<count {
            // Low-pass: average this delayed sample with the one before (half a sample of delay).
            let delayed = delayLine[index]
            let lowPassed = 0.5 * (delayed + previous)
            previous = delayed
            // Fractional delay: first-order all-pass.
            let shifted = allpassCoefficient * lowPassed + allpassIn - allpassCoefficient * allpassOut
            allpassIn = lowPassed
            allpassOut = shifted
            let sample = loopGain * shifted
            delayLine[index] = sample
            index += 1
            if index == length { index = 0 }

            guard let level = envelope.level(at: bufferStart + Int64(i)) else { return }
            out[i] += sample * gain * level
        }
        if bufferStart + Int64(count) >= endFrame { envelope.finish() }
    }
}
