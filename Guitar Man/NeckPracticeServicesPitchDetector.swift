//
//  PitchDetector.swift
//  Neck Practice
//
//  Listens to the microphone and detects the fundamental frequency of the input
//  signal (see PitchAnalyzer: YIN plus a subharmonic check — well suited for
//  monophonic guitar signals).  Auto-detects the nearest string in standard tuning,
//  or measures against a string the user has locked.
//
//  The tap delivers buffers of whatever size iOS chooses; they're accumulated in a
//  ring buffer and the most recent 4096 samples are analyzed every ~1024 new samples,
//  so low strings (82 Hz ≈ 580 samples per period) always get several periods.
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

    /// The string the user tapped to lock the tuner to, or nil for auto-detect.
    private(set) var lockedString: GuitarString? = nil

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

    // MARK: - Analysis tuning

    private let analysisHop = 1024               // new samples between analyses
    private let medianCount = 5                  // frequency estimates in the median filter
    private let switchConfirmations = 4          // consecutive analyses before auto-switching strings
    private let attackSkipSeconds = 0.05         // ignore the noisy pick transient
    private let onsetMinRMS: Float = 0.01
    private let smoothingAlpha: Double = 0.25
    private let inTuneFramesRequired: Int = 10   // ~0.2 s at the analysis rate
    private let noPitchHoldFrames: Int = 14      // hold display ~0.3 s after signal drops

    // MARK: - Tracking state (audio-thread only)

    private var ring: [Float] = []
    private var samplesSinceAnalysis = 0
    private var previousBufferRMS: Float = 0
    private var attackSkipRemaining = 0
    private var recentFrequencies: [Double] = []
    private var currentStringId: Int? = nil      // auto-detected string, nil until a pluck is heard
    private var candidateStringId: Int = 0
    private var candidateCount = 0
    private var smoothedCents: Double = 0
    private var inTuneFrameCount: Int = 0
    private var lastStringId: Int = -1
    private var noPitchFrameCount: Int = 0
    private var chimePlayer: AVAudioPlayer?

    // The lock is set from the main thread and read on the audio thread.
    private let lockStateLock = NSLock()
    private var lockedStringId: Int? = nil

    // MARK: - Public methods

    func start() async {
        guard !isListening else { return }

        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            permissionDenied = true
            return
        }

        do {
            try AudioSessionSetup.activateRecording()
        } catch {
            print("PitchDetector: session setup failed: \(error)")
            return
        }

        guard AVAudioSession.sharedInstance().isInputAvailable else {
            print("PitchDetector: no audio input available")
            return
        }

        resetTracking()

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

    /// Locks the tuner to `string` (cents measured against it, auto-detect off), or returns
    /// to auto-detect when `string` is nil.
    func lockString(_ string: GuitarString?) {
        lockStateLock.withLock { lockedStringId = string?.id }
        lockedString = string
        if let string { targetString = string }
    }

    private func resetTracking() {
        ring.removeAll(keepingCapacity: true)
        ring.reserveCapacity(PitchAnalyzer.windowSize * 2)
        samplesSinceAnalysis = 0
        previousBufferRMS = 0
        attackSkipRemaining = 0
        recentFrequencies.removeAll()
        currentStringId = nil
        candidateCount = 0
        smoothedCents = 0
        inTuneFrameCount = 0
        lastStringId = -1
        noPitchFrameCount = 0
    }

    // MARK: - Chime

    /// Plays a short synthesized chime to confirm a string was tuned.
    private func playTuneChime() {
        // E6 — bright, guitar-friendly
        chimePlayer = SynthTone.player(frequency: 1318.5, duration: 0.18, amplitude: 0.25, volume: 0.6)
        chimePlayer?.play()
    }

    // MARK: - Buffer processing

    private func processBuffer(_ buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var bufferRMS: Float = 0
        vDSP_rmsqv(channelData, 1, &bufferRMS, vDSP_Length(frameCount))
        let level = min(1.0, bufferRMS * 10)

        // A sudden jump in loudness is a pick attack: skip analysis while the transient settles
        // and drop estimates that belong to the previous note.
        if bufferRMS > onsetMinRMS && bufferRMS > previousBufferRMS * 2 {
            attackSkipRemaining = Int(attackSkipSeconds * sampleRate)
            recentFrequencies.removeAll()
        }
        previousBufferRMS = bufferRMS

        ring.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frameCount))
        if ring.count > PitchAnalyzer.windowSize * 2 {
            ring.removeFirst(ring.count - PitchAnalyzer.windowSize)
        }
        samplesSinceAnalysis += frameCount

        let skippingAttack = attackSkipRemaining > 0
        if skippingAttack { attackSkipRemaining -= frameCount }

        guard !skippingAttack,
              samplesSinceAnalysis >= analysisHop,
              ring.count >= PitchAnalyzer.windowSize else {
            publishLevel(level)
            return
        }
        samplesSinceAnalysis = 0

        let window = Array(ring.suffix(PitchAnalyzer.windowSize))
        var windowRMS: Float = 0
        vDSP_rmsqv(window, 1, &windowRMS, vDSP_Length(window.count))

        guard windowRMS > 0.002,
              let rawFrequency = PitchAnalyzer.detectFrequency(in: window, sampleRate: sampleRate) else {
            // No pitch detected — hold the last reading briefly to avoid flickering
            noPitchFrameCount += 1
            inTuneFrameCount = 0
            if noPitchFrameCount >= noPitchHoldFrames {
                // Signal is gone: the next pluck starts fresh.
                recentFrequencies.removeAll()
                currentStringId = nil
                candidateCount = 0
                lastStringId = -1
                DispatchQueue.main.async { [weak self] in
                    self?.signalLevel = level
                    self?.detectedFrequency = nil
                    self?.centsOffset = 0
                }
            } else {
                publishLevel(level)
            }
            return
        }

        noPitchFrameCount = 0

        // Median of the last few estimates rejects the occasional outlier.
        recentFrequencies.append(rawFrequency)
        if recentFrequencies.count > medianCount { recentFrequencies.removeFirst() }
        let frequency = recentFrequencies.sorted()[recentFrequencies.count / 2]

        let (target, isLocked) = selectTargetString(for: frequency)
        let measured = isLocked ? foldToOctave(of: target, frequency: frequency) : frequency
        let rawCents = 1200.0 * log2(measured / target.frequency)

        // Reset smoothing only when the target string actually changes
        if target.id != lastStringId {
            smoothedCents = rawCents
            inTuneFrameCount = 0
            lastStringId = target.id
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
        let smoothed = smoothedCents

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // The user may have locked/unlocked since this analysis ran.
            let shown = self.lockedString ?? target
            self.signalLevel = level
            self.detectedFrequency = frequency
            self.targetString = shown
            self.centsOffset = smoothed
            if shouldMarkTuned && shown.id == target.id && !self.tunedStrings.contains(target.id) {
                self.tunedStrings.insert(target.id)
                self.playTuneChime()
            }
        }
    }

    private func publishLevel(_ level: Float) {
        DispatchQueue.main.async { [weak self] in
            self?.signalLevel = level
        }
    }

    // MARK: - String selection

    /// Locked string if the user picked one; otherwise the nearest string, with hysteresis:
    /// a different string must win several analyses in a row before the target switches.
    private func selectTargetString(for frequency: Double) -> (string: GuitarString, isLocked: Bool) {
        if let id = lockStateLock.withLock({ lockedStringId }),
           let locked = GuitarString.standard.first(where: { $0.id == id }) {
            currentStringId = nil   // back to a fresh auto-detect when unlocked
            return (locked, true)
        }

        let nearest = findNearestString(for: frequency)
        guard let current = currentStringId else {
            currentStringId = nearest.id
            candidateCount = 0
            return (nearest, false)
        }

        if nearest.id != current {
            if nearest.id == candidateStringId {
                candidateCount += 1
            } else {
                candidateStringId = nearest.id
                candidateCount = 1
            }
            if candidateCount >= switchConfirmations {
                currentStringId = nearest.id
                candidateCount = 0
                return (nearest, false)
            }
        } else {
            candidateCount = 0
        }
        return (GuitarString.standard.first { $0.id == currentStringId } ?? nearest, false)
    }

    private func findNearestString(for frequency: Double) -> GuitarString {
        GuitarString.standard.min(by: {
            abs(1200.0 * log2(frequency / $0.frequency)) <
            abs(1200.0 * log2(frequency / $1.frequency))
        }) ?? GuitarString.standard[5]
    }

    /// When locked, an octave error (e.g. 165 Hz heard while locked to E2) is folded
    /// onto the locked string's octave so the needle still reads sensibly.
    private func foldToOctave(of target: GuitarString, frequency: Double) -> Double {
        frequency * pow(2.0, log2(target.frequency / frequency).rounded())
    }
}
