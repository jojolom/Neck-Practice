//
//  ChordListener.swift
//  Guitar Man
//
//  Listens to the microphone for Composition play-along: publishes the chroma of what's
//  ringing (see ChordAnalyzer) about ten times a second, and counts strums (sudden jumps in
//  loudness) so the same chord twice in a row needs two strums. Engine handling follows
//  PitchDetector: let go of the mic on a call, a route change, or in the background.
//

import Accelerate
import AVFoundation
import Observation
import UIKit

@Observable
final class ChordListener {

    // MARK: - Published state

    /// Share of the sound on each pitch class (C = 0 … B = 11), or all zeros when quiet.
    private(set) var chroma: [Double] = Array(repeating: 0, count: 12)
    /// What the level bars show (0–1 per pitch class): the chroma scaled by how loud it is and
    /// smoothed, so the bars rise with a strum and settle as it rings instead of jumping with
    /// every analysis. Only for display; matching uses `chroma`.
    private(set) var displayLevels: [Double] = Array(repeating: 0, count: 12)
    /// Microphone input level (0–1).
    private(set) var signalLevel: Float = 0
    /// Goes up by one on every strum.
    private(set) var strumCount: Int = 0
    private(set) var isListening = false
    private(set) var permissionDenied = false

    // MARK: - Audio

    private let engine = AVAudioEngine()
    private let bufferSize: AVAudioFrameCount = 2048
    /// Raw samples between analyses (~85 ms at 48 kHz).
    private let analysisHop = 4096
    /// Below this the input counts as silence (no chroma, no strum).
    private let minRMS: Float = 0.004

    // Audio-thread state.
    private var ring: [Float] = []
    private var samplesSinceAnalysis = 0
    private var previousRMS: Float = 0

    private var isTapInstalled = false
    private var observers: [any NSObjectProtocol] = []

    // MARK: - Public

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
            print("ChordListener: session setup failed: \(error)")
            return
        }
        guard startEngine() else { return }
        isListening = true
        observeAudioChanges()
    }

    func stop() {
        guard isListening else { return }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        stopEngine()
        isListening = false
    }

    // MARK: - Engine

    private func startEngine() -> Bool {
        guard AVAudioSession.sharedInstance().isInputAvailable else {
            print("ChordListener: no audio input available")
            return false
        }
        ring.removeAll(keepingCapacity: true)
        samplesSinceAnalysis = 0
        previousRMS = 0

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            print("ChordListener: invalid input format: \(format)")
            return false
        }
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer, sampleRate: buffer.format.sampleRate)
        }
        isTapInstalled = true

        do {
            try engine.start()
            return true
        } catch {
            stopEngine()
            print("ChordListener: engine start failed: \(error)")
            return false
        }
    }

    private func stopEngine() {
        if isTapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            isTapInstalled = false
        }
        engine.stop()
        chroma = Array(repeating: 0, count: 12)
        displayLevels = Array(repeating: 0, count: 12)
        signalLevel = 0
    }

    private func restartEngine() {
        guard isListening, UIApplication.shared.applicationState != .background else { return }
        stopEngine()
        try? AVAudioSession.sharedInstance().setActive(true)
        _ = startEngine()
    }

    private func observeAudioChanges() {
        observers = [
            AudioSessionSetup.observe(AVAudioSession.interruptionNotification) { [weak self] notification in
                if AudioInterruption(notification).began {
                    self?.stopEngine()
                } else {
                    self?.restartEngine()
                }
            },
            AudioSessionSetup.observe(.AVAudioEngineConfigurationChange, object: engine) { [weak self] _ in
                self?.restartEngine()
            },
            AudioSessionSetup.observe(UIApplication.didEnterBackgroundNotification) { [weak self] _ in
                self?.stopEngine()
            },
            AudioSessionSetup.observe(UIApplication.willEnterForegroundNotification) { [weak self] _ in
                self?.restartEngine()
            },
        ]
    }

    // MARK: - Buffer processing (audio thread)

    private func processBuffer(_ buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        var rms: Float = 0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameCount))
        let level = min(1.0, rms * 10)
        // A sudden jump in loudness is a strum.
        let isStrum = rms > minRMS * 2 && rms > previousRMS * 2
        previousRMS = rms

        let needed = ChordAnalyzer.windowSize * ChordAnalyzer.decimation
        ring.append(contentsOf: UnsafeBufferPointer(start: channelData, count: frameCount))
        if ring.count > needed * 2 {
            ring.removeFirst(ring.count - needed)
        }
        samplesSinceAnalysis += frameCount

        var newChroma: [Double]? = nil
        var windowRMS: Float = 0
        if samplesSinceAnalysis >= analysisHop && ring.count >= needed {
            samplesSinceAnalysis = 0
            let window = Array(ring.suffix(needed))
            vDSP_rmsqv(window, 1, &windowRMS, vDSP_Length(window.count))
            newChroma = windowRMS > minRMS
                ? ChordAnalyzer.chroma(samples: window, sampleRate: sampleRate)
                : Array(repeating: 0, count: 12)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.signalLevel = level
            if isStrum { self.strumCount += 1 }
            if let newChroma {
                self.chroma = newChroma
                self.displayLevels = ChordAnalyzer.displayLevels(previous: self.displayLevels,
                                                                    chroma: newChroma, rms: windowRMS)
            }
        }
    }
}
