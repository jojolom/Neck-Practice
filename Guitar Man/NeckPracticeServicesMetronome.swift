//
//  Metronome.swift
//  Neck Practice
//
//  Simple metronome with synthesized click sounds and configurable BPM.
//

import AVFoundation
import Observation

@Observable
final class Metronome {

    // MARK: - Settings

    var bpm: Int = 120 {
        didSet {
            let clamped = max(30, min(300, bpm))
            if bpm != clamped {
                bpm = clamped
            } else if oldValue != bpm && isPlaying {
                restartTimer()
            }
        }
    }

    /// Beats per measure for visual accent. Default 4 (common time).
    var beatsPerMeasure: Int = 4

    // MARK: - State

    private(set) var isPlaying: Bool = false

    /// Toggles on each beat for visual pulse animation.
    private(set) var beatPulse: Bool = false

    /// The current beat within the measure (0-based).
    private(set) var currentBeat: Int = 0

    // MARK: - Audio

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var clickBuffer: AVAudioPCMBuffer?
    private var accentBuffer: AVAudioPCMBuffer?
    private var timer: Timer?

    init() {
        setupEngine()
    }

    // MARK: - Setup

    private func setupEngine() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        clickBuffer = generateClick(frequency: 800, duration: 0.03, sampleRate: 44100)
        accentBuffer = generateClick(frequency: 1200, duration: 0.04, sampleRate: 44100)
    }

    /// Generates a short sine-wave click with fast exponential decay.
    private func generateClick(frequency: Double, duration: Double,
                                sampleRate: Double) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let envelope = Float(exp(-t * 80))
            data[i] = envelope * sin(Float(2.0 * .pi * frequency * t))
        }
        return buffer
    }

    // MARK: - Start / Stop

    func start() {
        guard !isPlaying else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            try engine.start()
            playerNode.play()
            isPlaying = true
            currentBeat = 0
            tick()
            restartTimer()
        } catch {
            print("Metronome: start failed: \(error)")
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        playerNode.stop()
        engine.stop()
        isPlaying = false
        currentBeat = 0
        beatPulse = false
    }

    func toggle() {
        isPlaying ? stop() : start()
    }

    // MARK: - Timer

    private func restartTimer() {
        timer?.invalidate()
        let interval = 60.0 / Double(bpm)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        let isAccent = currentBeat == 0
        if let buffer = isAccent ? accentBuffer : clickBuffer {
            playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        }
        beatPulse.toggle()
        currentBeat = (currentBeat + 1) % beatsPerMeasure
    }
}
