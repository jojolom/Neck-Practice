//
//  PitchDetector.swift
//  Neck Practice
//
//  Listens to the microphone and detects the fundamental frequency of the input
//  signal using the YIN autocorrelation algorithm — well suited for monophonic
//  guitar signals.  Auto-detects the nearest string in standard tuning.
//

import Accelerate
import AVFoundation
import Observation

// MARK: - GuitarString

/// Represents one of the six guitar strings in standard tuning.
struct GuitarString: Identifiable, Hashable {
    let id: Int          // 1 = high e, 6 = low E (conventional numbering)
    let note: Note
    let octave: Int
    let frequency: Double

    var label: String {
        let name = note.description
        return "\(name)\(octave)"
    }

    static let standard: [GuitarString] = [
        GuitarString(id: 1, note: .e, octave: 4, frequency: 329.63),
        GuitarString(id: 2, note: .b, octave: 3, frequency: 246.94),
        GuitarString(id: 3, note: .g, octave: 3, frequency: 196.00),
        GuitarString(id: 4, note: .d, octave: 3, frequency: 146.83),
        GuitarString(id: 5, note: .a, octave: 2, frequency: 110.00),
        GuitarString(id: 6, note: .e, octave: 2, frequency: 82.41),
    ]
}

// MARK: - PitchDetector

@Observable
final class PitchDetector {

    // MARK: - Published state

    /// The detected fundamental frequency in Hz, or nil if no pitch detected.
    private(set) var detectedFrequency: Double? = nil

    /// Cents deviation from the target string's frequency.
    /// Negative = flat, positive = sharp.
    private(set) var centsOffset: Double = 0

    /// Current microphone input level (0–1).
    private(set) var signalLevel: Float = 0

    /// The auto-detected nearest string.
    private(set) var targetString: GuitarString = GuitarString.standard[5]

    /// Whether the detector is actively listening.
    private(set) var isListening: Bool = false

    /// Strings that have been held in-tune long enough to be considered "tuned".
    private(set) var tunedStrings: Set<Int> = []

    /// True when the detected pitch is within the "in-tune" threshold.
    var isInTune: Bool {
        guard detectedFrequency != nil else { return false }
        return abs(centsOffset) < 3.0
    }

    /// True if mic permission was denied.
    private(set) var permissionDenied: Bool = false

    // MARK: - Audio engine

    private let engine = AVAudioEngine()
    private let bufferSize: AVAudioFrameCount = 2048

    // MARK: - Smoothing & tracking (audio-thread only)

    private var smoothedCents: Double = 0
    private let smoothingAlpha: Double = 0.3
    private var inTuneFrameCount: Int = 0
    private let inTuneFramesRequired: Int = 6    // ~0.2 s at typical callback rate
    private var lastStringId: Int = 6
    private var noPitchFrameCount: Int = 0
    private let noPitchHoldFrames: Int = 10   // hold display ~0.3 s after signal drops
    private var chimePlayer: AVAudioPlayer?

    // MARK: - Public methods

    func start() async {
        guard !isListening else { return }

        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            permissionDenied = true
            return
        }

        let session = AVAudioSession.sharedInstance()

        do {
            try session.setCategory(.playAndRecord, mode: .default,
                                     options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("PitchDetector: session setup failed: \(error)")
            return
        }

        guard session.isInputAvailable else {
            print("PitchDetector: no audio input available")
            return
        }

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            print("PitchDetector: invalid input format: \(recordingFormat)")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) {
            [weak self] buffer, _ in
            self?.processBuffer(buffer, sampleRate: buffer.format.sampleRate)
        }

        do {
            try engine.start()
            isListening = true
        } catch {
            inputNode.removeTap(onBus: 0)
            print("PitchDetector: engine start failed: \(error)")
        }
    }

    func stop() {
        guard isListening else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isListening = false
        detectedFrequency = nil
        centsOffset = 0
        signalLevel = 0
    }

    func resetTunedStrings() {
        tunedStrings.removeAll()
    }

    // MARK: - Chime

    /// Plays a short synthesized chime to confirm a string was tuned.
    private func playTuneChime() {
        let sampleRate = 44100
        let duration = 0.18
        let freq = 1318.5  // E6 — bright, guitar-friendly
        let count = Int(Double(sampleRate) * duration)

        // Generate 16-bit PCM samples
        var pcm = Data(count: count * 2)
        pcm.withUnsafeMutableBytes { raw in
            let buf = raw.bindMemory(to: Int16.self)
            for i in 0..<count {
                let t = Double(i) / Double(sampleRate)
                let envelope = 1.0 - t / duration
                buf[i] = Int16(sin(2.0 * .pi * freq * t) * envelope * 0.25 * Double(Int16.max))
            }
        }

        // Build a minimal WAV in memory
        var wav = Data()
        let dataSize = pcm.count
        func le<T: FixedWidthInteger>(_ v: T) { var x = v.littleEndian; wav.append(Data(bytes: &x, count: MemoryLayout<T>.size)) }

        wav.append("RIFF".data(using: .ascii)!)
        le(UInt32(36 + dataSize))
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        le(UInt32(16));   le(UInt16(1));   le(UInt16(1))            // PCM, mono
        le(UInt32(sampleRate)); le(UInt32(sampleRate * 2))          // sample rate, byte rate
        le(UInt16(2));   le(UInt16(16))                              // block align, bits
        wav.append("data".data(using: .ascii)!)
        le(UInt32(dataSize))
        wav.append(pcm)

        chimePlayer = try? AVAudioPlayer(data: wav)
        chimePlayer?.volume = 0.6
        chimePlayer?.play()
    }

    // MARK: - Buffer processing

    private func processBuffer(_ buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let samples = Array(UnsafeBufferPointer(start: channelData, count: frameCount))

        // Compute RMS for signal level display and silence gating
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(frameCount))
        let level = min(1.0, rms * 10)

        guard rms > 0.002,
              let frequency = yinPitchDetection(samples: samples, sampleRate: sampleRate) else {
            // No pitch detected — hold the last reading briefly to avoid flickering
            noPitchFrameCount += 1
            inTuneFrameCount = 0
            if noPitchFrameCount >= noPitchHoldFrames {
                DispatchQueue.main.async { [weak self] in
                    self?.signalLevel = level
                    self?.detectedFrequency = nil
                    self?.centsOffset = 0
                }
            } else {
                DispatchQueue.main.async { [weak self] in
                    self?.signalLevel = level
                }
            }
            return
        }

        noPitchFrameCount = 0

        // Auto-detect nearest string
        let nearest = findNearestString(for: frequency)
        let rawCents = 1200.0 * log2(frequency / nearest.frequency)

        // Reset smoothing when the detected string changes
        if nearest.id != lastStringId {
            smoothedCents = rawCents
            inTuneFrameCount = 0
            lastStringId = nearest.id
        } else {
            smoothedCents = smoothingAlpha * rawCents + (1.0 - smoothingAlpha) * smoothedCents
        }

        // Track in-tune state for marking strings as "tuned"
        if abs(smoothedCents) < 3.0 {
            inTuneFrameCount += 1
        } else {
            inTuneFrameCount = 0
        }

        let shouldMarkTuned = inTuneFrameCount >= inTuneFramesRequired
        let stringId = nearest.id
        let smoothed = smoothedCents

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.signalLevel = level
            self.detectedFrequency = frequency
            self.targetString = nearest
            self.centsOffset = smoothed
            if shouldMarkTuned && !self.tunedStrings.contains(stringId) {
                self.tunedStrings.insert(stringId)
                self.playTuneChime()
            }
        }
    }

    // MARK: - Auto-detection

    private func findNearestString(for frequency: Double) -> GuitarString {
        GuitarString.standard.min(by: {
            abs(1200.0 * log2(frequency / $0.frequency)) <
            abs(1200.0 * log2(frequency / $1.frequency))
        }) ?? GuitarString.standard[5]
    }

    // MARK: - YIN Algorithm (Accelerate-optimised)

    private func yinPitchDetection(samples: [Float], sampleRate: Double) -> Double? {
        let threshold: Float = 0.20
        let halfLength = samples.count / 2
        let minTau = max(2, Int(sampleRate / 600))
        let maxTau = min(Int(sampleRate / 60), halfLength - 1)
        guard maxTau > minTau else { return nil }

        let windowSize = vDSP_Length(halfLength)
        var diff   = [Float](repeating: 0, count: maxTau + 1)
        var cmndf  = [Float](repeating: 0, count: maxTau + 1)
        var temp   = [Float](repeating: 0, count: halfLength)
        cmndf[0] = 1.0

        var runningSum: Float = 0

        samples.withUnsafeBufferPointer { ptr in
            let base = ptr.baseAddress!

            for tau in 1...maxTau {
                vDSP_vsub(base + tau, 1, base, 1, &temp, 1, windowSize)
                var sum: Float = 0
                vDSP_svesq(temp, 1, &sum, windowSize)

                diff[tau] = sum
                runningSum += sum
                cmndf[tau] = sum / (runningSum / Float(tau))
            }
        }

        var bestTau = -1
        for tau in minTau...maxTau {
            if cmndf[tau] < threshold {
                var localMin = tau
                while localMin + 1 <= maxTau && cmndf[localMin + 1] < cmndf[localMin] {
                    localMin += 1
                }
                bestTau = localMin
                break
            }
        }

        guard bestTau > 0 else { return nil }

        // Parabolic interpolation for sub-sample accuracy
        let refinedTau: Double
        if bestTau > 1 && bestTau < maxTau {
            let s0 = Double(cmndf[bestTau - 1])
            let s1 = Double(cmndf[bestTau])
            let s2 = Double(cmndf[bestTau + 1])
            let denom = s0 - 2.0 * s1 + s2
            if abs(denom) > 1e-10 {
                refinedTau = Double(bestTau) + (s0 - s2) / (2.0 * denom)
            } else {
                refinedTau = Double(bestTau)
            }
        } else {
            refinedTau = Double(bestTau)
        }

        let frequency = sampleRate / refinedTau

        // Sanity check: guitar fundamental range (generous bounds)
        guard frequency >= 60 && frequency <= 500 else { return nil }

        return frequency
    }
}
