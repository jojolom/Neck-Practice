//
//  Looper.swift
//  Neck Practice
//
//  Audio looper that records from the microphone, plays back in a loop,
//  and supports overdubbing multiple layers — like a guitar looper pedal.
//
//  Every recording (base loop, overdub, re-record) starts with a 3-2-1 count-in.
//  Playback runs on one player-node timeline: overdubs are placed at the loop position
//  where they started (minus device latency), and a new mix is swapped in at the next
//  loop boundary so the loop never restarts when an overdub finishes.
//

import Accelerate
import AVFoundation
import Observation

// MARK: - LooperState

enum LooperState {
    case empty        // Nothing recorded yet
    case countingIn   // 3-2-1 before a recording starts (loop keeps playing if one exists)
    case recording    // Capturing the base loop
    case playing      // Loop is playing back
    case overdubbing  // Playing + recording a new layer simultaneously
    case stopped      // Loop exists but playback is paused
}

/// What a count-in leads to.
private enum PendingRecording: Equatable {
    case base
    case overdub
    case replace(Int)
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
    /// The count-in number currently showing (3, 2, 1), or nil outside a count-in.
    private(set) var countdown: Int? = nil
    /// Index of the currently soloed layer, or nil when playing all.
    private(set) var soloIndex: Int? = nil

    /// Sample rate of the loop's audio (the input format's rate), or 0 before the looper starts.
    var sampleRate: Double { recordingFormat?.sampleRate ?? 0 }

    /// How many more layers fit (the looper holds up to 8).
    var freeLayerSlots: Int { max(0, maxLayers - layers.count) }

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
    /// Samples collected during the current recording / overdub. Appended on the audio
    /// thread and read on main, so always go through `recordLock`.
    private var recordedChunks: [[Float]] = []
    private var recordedFrameCount = 0
    private let recordLock = NSLock()
    /// Total frames in the canonical loop (set from first recording).
    private var loopFrameCount: AVAudioFrameCount = 0

    // MARK: - Progress tracking

    private var progressTimer: Timer?
    private var recordingStartTime: Date?

    // MARK: - Count-in

    private var countInTask: Task<Void, Never>?
    private var pendingRecording: PendingRecording?
    private var tickPlayer: AVAudioPlayer?
    private var lastTickPlayer: AVAudioPlayer?

    // MARK: - Loop position

    /// Loop frame that sample 0 of the currently scheduled buffer corresponds to. The mix is
    /// built rotated by this amount so a rebuild can resume mid-loop (the player node's
    /// sample time restarts at 0 whenever it is stopped).
    private var playbackOffsetFrames = 0
    /// Loop frame at which the current overdub started capturing.
    private var overdubStartPosition = 0

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

        // The loop is mono. Connecting with the input's channel count would make every mono
        // buffer mismatch the player (an exception) on a multi-channel audio interface.
        guard let loopFormat = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1) else {
            print("Looper: no mono format at \(format.sampleRate) Hz")
            return
        }
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: loopFormat)

        do {
            try engine.start()
            isStarted = true
        } catch {
            print("Looper: engine start failed: \(error)")
        }
    }

    func stop() {
        cancelCountIn()
        progressTimer?.invalidate()
        progressTimer = nil
        removeInputTap()
        playerNode.stop()
        engine.stop()
        isStarted = false
        state = .empty
        layers.removeAll()
        mixedBuffer = nil
        discardRecordedSamples()
        loopFrameCount = 0
        playbackOffsetFrames = 0
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
            beginCountIn(.base)
        case .countingIn:
            cancelCountIn()
        case .recording:
            stopRecording()
        case .playing:
            beginCountIn(.overdub)
        case .overdubbing:
            stopOverdub()
        case .stopped:
            resumePlayback()
        }
    }

    func stopPlayback() {
        if state == .countingIn { cancelCountIn() }
        guard state == .playing || state == .overdubbing else { return }
        if state == .overdubbing {
            stopOverdub()
        }
        playerNode.stop()
        showStopped()
    }

    func undo() {
        cancelCountIn()

        // If overdubbing, cancel the current overdub first
        if state == .overdubbing {
            removeInputTap()
            discardRecordedSamples()
            replacingLayerIndex = nil
            state = .playing
        }

        guard layers.count > 1 else { return }
        layers.removeLast()
        layerCount = layers.count
        soloIndex = nil
        rebuildPreservingPosition()
    }

    func removeLayer(at index: Int) {
        guard index >= 0, index < layers.count else { return }
        cancelCountIn()

        // If overdubbing, cancel the overdub first
        let wasOverdubbing = state == .overdubbing
        if wasOverdubbing {
            removeInputTap()
            discardRecordedSamples()
            replacingLayerIndex = nil
        }

        layers.remove(at: index)
        layerCount = layers.count
        soloIndex = nil

        if layers.isEmpty {
            clearAll()
        } else {
            rebuildPreservingPosition()
            if wasOverdubbing { state = .playing }
        }
    }

    /// Solo a single layer — only that layer's audio plays.
    func solo(layerAt index: Int) {
        guard index >= 0, index < layers.count else { return }
        cancelCountIn()
        soloIndex = index
        rebuildPreservingPosition()
    }

    /// Stop soloing — play all layers together.
    func unsolo() {
        soloIndex = nil
        rebuildPreservingPosition()
    }

    /// A copy of one layer's mono samples (e.g. to save it), or nil if there's no such layer.
    func layerSamples(at index: Int) -> [Float]? {
        layers.indices.contains(index) ? layers[index] : nil
    }

    /// Drops saved layers into the next free banks (extras beyond the free slots are ignored).
    /// Samples at `sampleRate` are converted to the looper's rate. When the looper is empty the
    /// first layer sets the loop length and playback starts; otherwise every layer is padded or
    /// trimmed to the existing loop length, like an overdub.
    func importLayers(_ imported: [[Float]], sampleRate importedRate: Double) {
        guard isStarted, let format = recordingFormat else { return }
        if state == .countingIn { cancelCountIn() }
        guard state == .empty || state == .playing || state == .stopped else { return }

        let incoming = imported.prefix(freeLayerSlots).filter { !$0.isEmpty }
        guard !incoming.isEmpty else { return }
        let rate = format.sampleRate
        let converted = incoming.map { LoopLibrary.resample($0, from: importedRate, to: rate) }

        if layers.isEmpty {
            let frames = min(max(converted[0].count, Int(minimumLoopDuration * rate)),
                             Int(maximumLoopDuration * rate))
            loopFrameCount = AVAudioFrameCount(frames)
            loopDuration = Double(frames) / rate
            layers = converted.map { Looper.fitted($0, to: frames) }
            layerCount = layers.count
            soloIndex = nil
            if scheduleLoop() {
                state = .playing
                startProgressTimer()
            } else {
                showStopped()
            }
        } else {
            let frames = Int(loopFrameCount)
            layers.append(contentsOf: converted.map { Looper.fitted($0, to: frames) })
            layerCount = layers.count
            soloIndex = nil
            rebuildPreservingPosition()
        }
    }

    /// `samples` padded with silence or trimmed to exactly `frames` frames.
    static func fitted(_ samples: [Float], to frames: Int) -> [Float] {
        if samples.count >= frames { return Array(samples.prefix(frames)) }
        return samples + [Float](repeating: 0, count: frames - samples.count)
    }

    /// Re-record a specific layer slot (after the count-in).
    func replaceOverdub(at index: Int) {
        guard isStarted, state == .playing, index >= 0, index < layers.count else { return }
        beginCountIn(.replace(index))
    }

    func clearAll() {
        cancelCountIn()
        removeInputTap()
        playerNode.stop()
        progressTimer?.invalidate()
        progressTimer = nil
        layers.removeAll()
        mixedBuffer = nil
        discardRecordedSamples()
        loopFrameCount = 0
        playbackOffsetFrames = 0
        layerCount = 0
        loopDuration = 0
        currentTime = 0
        inputLevel = 0
        soloIndex = nil
        replacingLayerIndex = nil
        state = .empty
    }

    // MARK: - Count-in

    /// Starts the 3-2-1 count-in; when it finishes, the matching recording begins.
    /// The loop (if any) keeps playing underneath.
    private func beginCountIn(_ kind: PendingRecording) {
        guard isStarted else { return }
        if kind == .overdub, layerCount >= maxLayers { return }

        countInTask?.cancel()
        pendingRecording = kind
        countdown = 3
        state = .countingIn
        prepareTickPlayers()

        countInTask = Task { [weak self] in
            for n in [3, 2, 1] {
                guard let self, !Task.isCancelled else { return }
                self.countdown = n
                self.playTick(isLast: n == 1)
                try? await Task.sleep(for: .seconds(1))
            }
            guard let self, !Task.isCancelled else { return }
            self.finishCountIn()
        }
    }

    /// Abort a count-in: back to the empty looper, or back to playing if a loop exists.
    private func cancelCountIn() {
        countInTask?.cancel()
        countInTask = nil
        pendingRecording = nil
        countdown = nil
        if state == .countingIn {
            state = loopFrameCount > 0 ? .playing : .empty
        }
    }

    private func finishCountIn() {
        let kind = pendingRecording
        countInTask = nil
        pendingRecording = nil
        countdown = nil

        switch kind {
        case .base:
            beginRecording()
        case .overdub:
            beginOverdub()
        case .replace(let index):
            beginReplace(at: index)
        case nil:
            state = loopFrameCount > 0 ? .playing : .empty
        }
    }

    private func prepareTickPlayers() {
        if tickPlayer == nil {
            tickPlayer = SynthTone.player(frequency: 880, duration: 0.07, amplitude: 0.6)
        }
        if lastTickPlayer == nil {
            lastTickPlayer = SynthTone.player(frequency: 1320, duration: 0.12, amplitude: 0.6)
        }
    }

    /// A click on each count; higher on the last so you can count in with hands on the guitar.
    private func playTick(isLast: Bool) {
        let player = isLast ? lastTickPlayer : tickPlayer
        player?.currentTime = 0
        player?.play()
    }

    // MARK: - Recording

    private func beginRecording() {
        guard isStarted, ensureEngineRunning() else { state = .empty; return }
        discardRecordedSamples()
        installInputTap()
        recordingStartTime = Date()
        state = .recording
        startProgressTimer()
    }

    private func stopRecording() {
        // The 5-minute auto-stop can queue this more than once.
        guard state == .recording else { return }
        removeInputTap()
        recordingStartTime = nil

        guard let format = recordingFormat else {
            state = .empty
            return
        }

        let samples = takeRecordedSamples()

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

        if scheduleLoop() {
            state = .playing
        } else {
            showStopped()
        }
    }

    // MARK: - Overdubbing

    private func beginOverdub() {
        guard isStarted, layerCount < maxLayers, ensureEngineRunning() else { state = .playing; return }
        replacingLayerIndex = nil
        startCapturingOverdub()
    }

    private func beginReplace(at index: Int) {
        guard isStarted, index >= 0, index < layers.count else { state = .playing; return }
        replacingLayerIndex = index
        soloIndex = nil
        // Hear every layer while re-recording (resumes from the current position).
        rebuildPreservingPosition()
        startCapturingOverdub()
    }

    private func startCapturingOverdub() {
        discardRecordedSamples()
        overdubStartPosition = currentLoopPosition() ?? 0
        installInputTap()
        state = .overdubbing
    }

    private func stopOverdub() {
        removeInputTap()

        let samples = takeRecordedSamples()

        guard !samples.isEmpty, loopFrameCount > 0, let format = recordingFormat else {
            state = .playing
            replacingLayerIndex = nil
            return
        }

        // What the player heard and played along to is output-latency old, and what the mic
        // captured is input-latency old, so shift the placement back by both.
        let session = AVAudioSession.sharedInstance()
        let latencyFrames = Int(((session.inputLatency + session.outputLatency) * format.sampleRate).rounded())

        let aligned = Looper.alignedLayer(
            samples: samples,
            startFrame: overdubStartPosition - latencyFrames,
            loopLength: Int(loopFrameCount)
        )

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
        swapMixAtLoopBoundary()
        state = .playing
    }

    /// Places `samples` into a zeroed buffer of `loopLength` frames starting at `startFrame`
    /// (which may be negative or past the end), wrapping around the loop. Capped at one full loop.
    static func alignedLayer(samples: [Float], startFrame: Int, loopLength: Int) -> [Float] {
        guard loopLength > 0 else { return [] }
        var aligned = [Float](repeating: 0, count: loopLength)
        let start = ((startFrame % loopLength) + loopLength) % loopLength
        let count = min(samples.count, loopLength)
        let firstChunk = min(count, loopLength - start)
        if firstChunk > 0 {
            aligned.replaceSubrange(start..<(start + firstChunk), with: samples[0..<firstChunk])
        }
        if count > firstChunk {
            aligned.replaceSubrange(0..<(count - firstChunk), with: samples[firstChunk..<count])
        }
        return aligned
    }

    // MARK: - Playback

    private func resumePlayback() {
        guard mixedBuffer != nil, scheduleLoop() else { return }
        state = .playing
        startProgressTimer()
    }

    /// Shows the loop as stopped (after the player node has been stopped).
    private func showStopped() {
        progressTimer?.invalidate()
        progressTimer = nil
        state = .stopped
        inputLevel = 0
    }

    /// Plays the loop from its very beginning. False if the audio engine can't run right now.
    @discardableResult
    private func scheduleLoop() -> Bool {
        playbackOffsetFrames = 0
        buildMixedBuffer()
        playerNode.stop()
        guard let buffer = mixedBuffer, ensureEngineRunning() else { return false }
        playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
        playerNode.play()
        return true
    }

    /// iOS stops the engine for calls, Siri, alarms and route changes, and playing a node on a
    /// stopped engine throws. Starts it again if needed; false if it can't run right now.
    private func ensureEngineRunning() -> Bool {
        guard !engine.isRunning else { return true }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            return true
        } catch {
            print("Looper: engine restart failed: \(error)")
            return false
        }
    }

    /// Where playback currently is within the loop, in frames, or nil if not playing.
    private func currentLoopPosition() -> Int? {
        guard loopFrameCount > 0, playerNode.isPlaying,
              let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return nil }
        // The player's sample time can be slightly negative just after play(); keep this in
        // 0..<length, since the mix is rotated by it.
        let length = Int(loopFrameCount)
        return ((Int(playerTime.sampleTime) + playbackOffsetFrames) % length + length) % length
    }

    /// Rebuilds the mix and swaps it in immediately, resuming from the current loop position
    /// (used for solo / unsolo / undo / remove, which should take effect right away).
    private func rebuildPreservingPosition() {
        playbackOffsetFrames = currentLoopPosition() ?? 0
        buildMixedBuffer()
        guard playerNode.isPlaying, let buffer = mixedBuffer, ensureEngineRunning() else { return }
        playerNode.stop()
        playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
        playerNode.play()
    }

    /// Rebuilds the mix and lets it take over at the end of the current pass through the loop,
    /// so playback never restarts or jumps (used when an overdub finishes).
    private func swapMixAtLoopBoundary() {
        buildMixedBuffer()
        guard let buffer = mixedBuffer else { return }
        if playerNode.isPlaying {
            playerNode.scheduleBuffer(buffer, at: nil, options: [.loops, .interruptsAtLoop])
        } else {
            scheduleLoop()
        }
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

        // Sum layers (or just the soloed layer), rotated so frame 0 of the buffer is
        // loop frame `playbackOffsetFrames`.
        let layersToMix: [[Float]]
        if let solo = soloIndex, solo < layers.count {
            layersToMix = [layers[solo]]
        } else {
            layersToMix = layers
        }

        vDSP_vclr(channelData, 1, vDSP_Length(frameCount))
        let offset = frameCount > 0 ? playbackOffsetFrames % frameCount : 0
        let head = vDSP_Length(frameCount - offset)
        for layer in layersToMix where layer.count == frameCount {
            layer.withUnsafeBufferPointer { src in
                guard let base = src.baseAddress else { return }
                vDSP_vadd(channelData, 1, base + offset, 1, channelData, 1, head)
                if offset > 0 {
                    vDSP_vadd(channelData + Int(head), 1, base, 1, channelData + Int(head), 1, vDSP_Length(offset))
                }
            }
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
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)

        // Store for recording (copied: the engine may reuse the buffer)
        let total = appendRecorded(Array(UnsafeBufferPointer(start: channelData, count: frames)))

        // Compute input level for metering
        var rms: Float = 0
        vDSP_measqv(channelData, 1, &rms, vDSP_Length(frames))
        rms = sqrt(rms)
        let level = min(1.0, rms * 8)

        DispatchQueue.main.async { [weak self] in
            self?.inputLevel = level
        }

        // Auto-stop long recordings
        if state == .recording, let format = recordingFormat {
            let duration = Double(total) / format.sampleRate
            if duration >= maximumLoopDuration {
                DispatchQueue.main.async { [weak self] in
                    self?.stopRecording()
                }
            }
        }
    }

    // MARK: - Recorded samples (thread-safe)

    /// Appends a chunk from the audio thread; returns the total frames recorded so far.
    private func appendRecorded(_ chunk: [Float]) -> Int {
        recordLock.lock()
        defer { recordLock.unlock() }
        recordedChunks.append(chunk)
        recordedFrameCount += chunk.count
        return recordedFrameCount
    }

    /// Returns everything recorded so far, and clears the store.
    private func takeRecordedSamples() -> [Float] {
        recordLock.lock()
        let chunks = recordedChunks
        recordedChunks.removeAll()
        recordedFrameCount = 0
        recordLock.unlock()
        return Array(chunks.joined())
    }

    private func discardRecordedSamples() {
        recordLock.lock()
        recordedChunks.removeAll()
        recordedFrameCount = 0
        recordLock.unlock()
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
        } else if state == .playing || state == .overdubbing || (state == .countingIn && loopFrameCount > 0) {
            // During playback, compute position from the player node
            guard let format = recordingFormat, let position = currentLoopPosition() else { return }
            currentTime = Double(position) / format.sampleRate
        }
    }
}
