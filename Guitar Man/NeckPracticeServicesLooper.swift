//
//  Looper.swift
//  Neck Practice
//
//  Audio looper that records from the microphone, plays back in a loop,
//  and supports overdubbing multiple layers — like a guitar looper pedal.
//

import Accelerate
import AVFoundation
import Observation

// MARK: - LooperState

enum LooperState {
    case empty        // Nothing recorded yet
    case recording    // Capturing the base loop
    case playing      // Loop is playing back
    case overdubbing  // Playing + recording a new layer simultaneously
    case stopped      // Loop exists but playback is paused
}

// MARK: - Looper

@Observable
final class Looper {

    // MARK: - Published state

    private(set) var state: LooperState = .empty
    private(set) var layerCount: Int = 0
    private(set) var loopDuration: TimeInterval = 0
    private(set) var currentTime: TimeInterval = 0
    private(set) var inputLevel: Float = 0
    private(set) var permissionDenied: Bool = false
    /// Index of the currently soloed layer, or nil when playing all.
    private(set) var soloIndex: Int? = nil

    /// Progress through the loop: 0.0 to 1.0
    var progress: Double {
        guard loopDuration > 0 else { return 0 }
        return currentTime / loopDuration
    }

    // MARK: - Audio engine

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var recordingFormat: AVAudioFormat?

    // MARK: - Layer storage

    /// Each layer is a flat array of Float samples (mono).
    private var layers: [[Float]] = []
    /// The mixed buffer scheduled for looping playback.
    private var mixedBuffer: AVAudioPCMBuffer?
    /// Fragments collected during the current recording / overdub.
    private var currentRecordingFragments: [AVAudioPCMBuffer] = []
    /// Total frames in the canonical loop (set from first recording).
    private var loopFrameCount: AVAudioFrameCount = 0

    // MARK: - Progress tracking

    private var progressTimer: Timer?
    private var recordingStartTime: Date?

    // MARK: - Flags

    private var isStarted = false
    private var isTapInstalled = false
    /// When set, the current overdub replaces this layer instead of adding a new one.
    private var replacingLayerIndex: Int? = nil

    // MARK: - Constants

    private let minimumLoopDuration: TimeInterval = 0.5
    private let maximumLoopDuration: TimeInterval = 300
    private let maxLayers: Int = 8

    // MARK: - Public API

    func start() async {
        guard !isStarted else { return }

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
            print("Looper: session setup failed: \(error)")
            return
        }

        guard session.isInputAvailable else {
            print("Looper: no audio input available")
            return
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        guard format.sampleRate > 0, format.channelCount > 0 else {
            print("Looper: invalid input format: \(format)")
            return
        }

        recordingFormat = format

        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
            isStarted = true
        } catch {
            print("Looper: engine start failed: \(error)")
        }
    }

    func stop() {
        progressTimer?.invalidate()
        progressTimer = nil
        removeInputTap()
        playerNode.stop()
        engine.stop()
        isStarted = false
        state = .empty
        layers.removeAll()
        mixedBuffer = nil
        currentRecordingFragments.removeAll()
        loopFrameCount = 0
        layerCount = 0
        loopDuration = 0
        currentTime = 0
        inputLevel = 0
        soloIndex = nil
        replacingLayerIndex = nil
    }

    /// The main "footswitch" — context-sensitive based on current state.
    func mainAction() {
        switch state {
        case .empty:
            beginRecording()
        case .recording:
            stopRecording()
        case .playing:
            beginOverdub()
        case .overdubbing:
            stopOverdub()
        case .stopped:
            resumePlayback()
        }
    }

    func stopPlayback() {
        guard state == .playing || state == .overdubbing else { return }
        if state == .overdubbing {
            stopOverdub()
        }
        playerNode.stop()
        progressTimer?.invalidate()
        progressTimer = nil
        state = .stopped
        inputLevel = 0
    }

    func undo() {
        // If overdubbing, cancel the current overdub first
        if state == .overdubbing {
            removeInputTap()
            currentRecordingFragments.removeAll()
            state = .playing
        }

        guard layers.count > 1 else { return }
        layers.removeLast()
        layerCount = layers.count
        rebuildAndReschedule()
    }

    func removeLayer(at index: Int) {
        guard index >= 0, index < layers.count else { return }

        // If overdubbing, cancel the overdub first
        if state == .overdubbing {
            removeInputTap()
            currentRecordingFragments.removeAll()
            replacingLayerIndex = nil
        }

        layers.remove(at: index)
        layerCount = layers.count
        soloIndex = nil

        if layers.isEmpty {
            clearAll()
        } else {
            buildMixedBuffer()
            if state == .playing || state == .overdubbing {
                guard let buffer = mixedBuffer else { return }
                playerNode.stop()
                playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
                playerNode.play()
                state = .playing
            }
        }
    }

    /// Solo a single layer — only that layer's audio plays.
    func solo(layerAt index: Int) {
        guard index >= 0, index < layers.count else { return }
        soloIndex = index
        buildMixedBuffer()
        if state == .playing || state == .overdubbing {
            guard let buffer = mixedBuffer else { return }
            playerNode.stop()
            playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
            playerNode.play()
        }
    }

    /// Stop soloing — play all layers together.
    func unsolo() {
        soloIndex = nil
        buildMixedBuffer()
        if state == .playing || state == .overdubbing {
            guard let buffer = mixedBuffer else { return }
            playerNode.stop()
            playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
            playerNode.play()
        }
    }

    /// Start recording to replace a specific layer slot.
    func replaceOverdub(at index: Int) {
        guard isStarted, index >= 0, index < layers.count else { return }
        replacingLayerIndex = index
        soloIndex = nil
        currentRecordingFragments.removeAll()
        installInputTap()
        // Rebuild with all layers so the user hears everything while re-recording
        buildMixedBuffer()
        if state == .playing {
            guard let buffer = mixedBuffer else { return }
            playerNode.stop()
            playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
            playerNode.play()
        }
        state = .overdubbing
    }

    func clearAll() {
        removeInputTap()
        playerNode.stop()
        progressTimer?.invalidate()
        progressTimer = nil
        layers.removeAll()
        mixedBuffer = nil
        currentRecordingFragments.removeAll()
        loopFrameCount = 0
        layerCount = 0
        loopDuration = 0
        currentTime = 0
        inputLevel = 0
        soloIndex = nil
        replacingLayerIndex = nil
        state = .empty
    }

    // MARK: - Recording

    private func beginRecording() {
        guard isStarted else { return }
        currentRecordingFragments.removeAll()
        installInputTap()
        recordingStartTime = Date()
        state = .recording
        startProgressTimer()
    }

    private func stopRecording() {
        removeInputTap()
        recordingStartTime = nil

        guard let format = recordingFormat else {
            state = .empty
            return
        }

        let samples = consolidateFragments(currentRecordingFragments)
        currentRecordingFragments.removeAll()

        let sampleRate = format.sampleRate
        let duration = Double(samples.count) / sampleRate

        guard duration >= minimumLoopDuration else {
            // Too short — discard
            state = .empty
            progressTimer?.invalidate()
            progressTimer = nil
            currentTime = 0
            return
        }

        let frameCount: Int
        if duration > maximumLoopDuration {
            frameCount = Int(sampleRate * maximumLoopDuration)
        } else {
            frameCount = samples.count
        }

        let trimmed = Array(samples.prefix(frameCount))
        loopFrameCount = AVAudioFrameCount(frameCount)
        loopDuration = Double(frameCount) / sampleRate

        layers.append(trimmed)
        layerCount = layers.count

        buildMixedBuffer()
        scheduleLoop()
        state = .playing
    }

    // MARK: - Overdubbing

    private func beginOverdub() {
        guard isStarted, layerCount < maxLayers else { return }
        currentRecordingFragments.removeAll()
        installInputTap()
        state = .overdubbing
    }

    private func stopOverdub() {
        removeInputTap()

        let samples = consolidateFragments(currentRecordingFragments)
        currentRecordingFragments.removeAll()

        guard !samples.isEmpty, loopFrameCount > 0 else {
            state = .playing
            replacingLayerIndex = nil
            return
        }

        // Pad or trim to match loop length
        let targetCount = Int(loopFrameCount)
        let aligned: [Float]
        if samples.count >= targetCount {
            aligned = Array(samples.prefix(targetCount))
        } else {
            aligned = samples + [Float](repeating: 0, count: targetCount - samples.count)
        }

        if let replaceIndex = replacingLayerIndex, replaceIndex < layers.count {
            // Replace existing layer
            layers[replaceIndex] = aligned
            replacingLayerIndex = nil
        } else {
            // Add as new layer
            layers.append(aligned)
            layerCount = layers.count
            replacingLayerIndex = nil
        }

        soloIndex = nil
        rebuildAndReschedule()
        state = .playing
    }

    // MARK: - Playback

    private func resumePlayback() {
        guard mixedBuffer != nil else { return }
        scheduleLoop()
        state = .playing
        startProgressTimer()
    }

    private func scheduleLoop() {
        guard let buffer = mixedBuffer else { return }
        playerNode.stop()
        playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
        playerNode.play()
    }

    private func rebuildAndReschedule() {
        buildMixedBuffer()
        guard let buffer = mixedBuffer else { return }
        playerNode.stop()
        playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
        playerNode.play()
    }

    // MARK: - Mixing

    private func buildMixedBuffer() {
        guard !layers.isEmpty, let format = recordingFormat else {
            mixedBuffer = nil
            return
        }

        let frameCount = Int(loopFrameCount)

        // Create mono format at the recording sample rate
        guard let monoFormat = AVAudioFormat(
            standardFormatWithSampleRate: format.sampleRate,
            channels: 1
        ) else { return }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: monoFormat,
            frameCapacity: loopFrameCount
        ) else { return }

        buffer.frameLength = loopFrameCount

        guard let channelData = buffer.floatChannelData?[0] else { return }

        // Sum layers (or just the soloed layer)
        let layersToMix: [[Float]]
        if let solo = soloIndex, solo < layers.count {
            layersToMix = [layers[solo]]
        } else {
            layersToMix = layers
        }

        for i in 0..<frameCount {
            var sum: Float = 0
            for layer in layersToMix {
                if i < layer.count {
                    sum += layer[i]
                }
            }
            channelData[i] = sum
        }

        // Peak normalize to prevent clipping
        var maxAbs: Float = 0
        vDSP_maxmgv(channelData, 1, &maxAbs, vDSP_Length(frameCount))
        if maxAbs > 1.0 {
            var scale = 1.0 / maxAbs
            vDSP_vsmul(channelData, 1, &scale, channelData, 1, vDSP_Length(frameCount))
        }

        mixedBuffer = buffer
    }

    // MARK: - Input tap management

    private func installInputTap() {
        guard !isTapInstalled, isStarted else { return }
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) {
            [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }
        isTapInstalled = true
    }

    private func removeInputTap() {
        guard isTapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        isTapInstalled = false
    }

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        // Store for recording
        currentRecordingFragments.append(buffer)

        // Compute input level for metering
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = vDSP_Length(buffer.frameLength)
        var rms: Float = 0
        vDSP_measqv(channelData, 1, &rms, frameCount)
        rms = sqrt(rms)
        let level = min(1.0, rms * 8)

        DispatchQueue.main.async { [weak self] in
            self?.inputLevel = level
        }

        // Auto-stop long recordings
        if state == .recording, let format = recordingFormat {
            let totalFrames = currentRecordingFragments.reduce(0) {
                $0 + Int($1.frameLength)
            }
            let duration = Double(totalFrames) / format.sampleRate
            if duration >= maximumLoopDuration {
                DispatchQueue.main.async { [weak self] in
                    self?.stopRecording()
                }
            }
        }
    }

    // MARK: - Fragment consolidation

    private func consolidateFragments(_ fragments: [AVAudioPCMBuffer]) -> [Float] {
        var result: [Float] = []
        for fragment in fragments {
            guard let data = fragment.floatChannelData?[0] else { continue }
            let count = Int(fragment.frameLength)
            result.append(contentsOf: UnsafeBufferPointer(start: data, count: count))
        }
        return result
    }

    // MARK: - Progress timer

    private func startProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) {
            [weak self] _ in
            self?.updateProgress()
        }
    }

    private func updateProgress() {
        if state == .recording {
            // During initial recording, show elapsed time
            if let start = recordingStartTime {
                currentTime = min(Date().timeIntervalSince(start), maximumLoopDuration)
            }
        } else if state == .playing || state == .overdubbing {
            // During playback, compute position from player node
            guard let nodeTime = playerNode.lastRenderTime,
                  let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
                  let format = recordingFormat else { return }
            let sampleTime = Double(playerTime.sampleTime)
            let sampleRate = format.sampleRate
            let totalSamples = Double(loopFrameCount)
            guard totalSamples > 0 else { return }
            let positionInLoop = sampleTime.truncatingRemainder(dividingBy: totalSamples)
            currentTime = max(0, positionInLoop / sampleRate)
        }
    }
}
