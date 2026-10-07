//
//  Metronome.swift
//  Neck Practice
//
//  Simple metronome with synthesized click sounds and configurable BPM.
//
//  Clicks are queued on the player node at exact sample times (see BeatSchedule), a fraction of
//  a second ahead, so the beat stays steady when the main thread is busy and never drifts.
//  A display timer only tops up the queue and lights the beat you're hearing.
//

import AVFoundation
import Observation
import UIKit

@Observable
final class Metronome {

    // MARK: - Settings

    var bpm: Int = 120 {
        didSet {
            let clamped = max(30, min(300, bpm))
            if bpm != clamped {
                bpm = clamped
            } else if oldValue != bpm && isPlaying {
                changeTempo()
            }
        }
    }

    /// Beats per measure for visual accent. Default 4 (common time).
    var beatsPerMeasure: Int = 4

    /// Clicks per beat: 1 for beats only; 2, 3 or 4 adds a quiet click on each eighth, triplet
    /// or sixteenth. Takes effect the next time the metronome starts.
    var subdivisions: Int = 1

    // MARK: - State

    private(set) var isPlaying: Bool = false

    /// Toggles on each beat for visual pulse animation.
    private(set) var beatPulse: Bool = false

    /// The beat you're hearing within the measure (0-based; 0 is the accent).
    private(set) var currentBeat: Int = 0

    // MARK: - Audio

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private let sampleRate: Double = 44100
    private var clickBuffer: AVAudioPCMBuffer?
    private var accentBuffer: AVAudioPCMBuffer?
    private var subdivisionBuffer: AVAudioPCMBuffer?

    // MARK: - Scheduling

    /// How far ahead clicks are queued; a main-thread stall shorter than this can't move a beat.
    private let lookahead: TimeInterval = 0.2
    /// Delay before the first click, and the soonest a tempo change can land.
    private let lead: TimeInterval = 0.05
    private var schedule: BeatSchedule?
    /// Queued clicks that haven't been heard yet, oldest first.
    private var pendingBeats: [BeatSchedule.Beat] = []
    /// How long the output takes to reach your ears, in samples (more on Bluetooth).
    private var outputLatencyFrames: Int64 = 0
    private var displayTimer: Timer?

    // MARK: - Interruptions

    /// Interruption, route-change and background observers, while the metronome is in use.
    private var observers: [any NSObjectProtocol] = []
    /// Set when iOS paused the metronome (a call, leaving the app); it starts again afterwards.
    private var resumesAfterSystemPause = false

    init() {
        setupEngine()
    }

    // MARK: - Setup

    private func setupEngine() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)

        clickBuffer = generateClick(frequency: 800, duration: 0.03, sampleRate: sampleRate)
        accentBuffer = generateClick(frequency: 1200, duration: 0.04, sampleRate: sampleRate)
        subdivisionBuffer = generateClick(frequency: 1000, duration: 0.02, sampleRate: sampleRate, gain: 0.3)
    }

    /// Generates a short sine-wave click with fast exponential decay.
    private func generateClick(frequency: Double, duration: Double,
                                sampleRate: Double, gain: Float = 1) -> AVAudioPCMBuffer? {
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
            data[i] = gain * envelope * sin(Float(2.0 * .pi * frequency * t))
        }
        return buffer
    }

    // MARK: - Start / Stop

    func start() {
        guard !isPlaying else { return }
        resumesAfterSystemPause = false

        do {
            try AudioSessionSetup.activatePlayback()
            try engine.start()
        } catch {
            print("Metronome: start failed: \(error)")
            return
        }

        outputLatencyFrames = Int64(AVAudioSession.sharedInstance().outputLatency * sampleRate)
        schedule = BeatSchedule(bpm: bpm, beatsPerMeasure: beatsPerMeasure, subdivisions: subdivisions,
                                sampleRate: sampleRate, firstBeatAt: lead * sampleRate)
        pendingBeats = []
        currentBeat = 0
        isPlaying = true

        // The player's timeline starts at 0 when it starts playing; queue the first clicks first.
        queueClicks(from: 0)
        playerNode.play()
        startDisplayTimer()
        if observers.isEmpty { observeAudioChanges() }
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        resumesAfterSystemPause = false
        halt()
    }

    func toggle() {
        isPlaying ? stop() : start()
    }

    /// Silences the metronome and resets the beat (the observers stay).
    private func halt() {
        displayTimer?.invalidate()
        displayTimer = nil
        playerNode.stop()
        engine.stop()
        schedule = nil
        pendingBeats = []
        isPlaying = false
        currentBeat = 0
        beatPulse = false
    }

    // MARK: - Scheduling

    /// Queues every click due within `lookahead` of player sample time `now`.
    private func queueClicks(from now: Int64) {
        guard var schedule else { return }
        for beat in schedule.beats(through: now + Int64(lookahead * sampleRate)) {
            let buffer = beat.subdivision > 0 ? subdivisionBuffer : beat.index == 0 ? accentBuffer : clickBuffer
            if let buffer {
                playerNode.scheduleBuffer(buffer, at: AVAudioTime(sampleTime: beat.sampleTime, atRate: sampleRate),
                                          options: [], completionHandler: nil)
            }
            pendingBeats.append(beat)
        }
        self.schedule = schedule
    }

    /// New tempo from the next unqueued click on, with no restart (so dragging the slider keeps
    /// the beat going).
    private func changeTempo() {
        let now = playerSampleTime() ?? 0
        schedule?.setBPM(bpm, earliest: now + Int64(lead * sampleRate))
    }

    /// Where the player is on its timeline, or nil before it has rendered.
    private func playerSampleTime() -> Int64? {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return nil }
        return playerTime.sampleTime
    }

    private func startDisplayTimer() {
        displayTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // .common so the beat keeps showing while you scroll or drag.
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    /// Tops up the click queue and lights the beat that's sounding now.
    private func refresh() {
        guard isPlaying, let now = playerSampleTime() else { return }
        queueClicks(from: now)
        let heard = now - outputLatencyFrames
        while let beat = pendingBeats.first, beat.sampleTime <= heard {
            pendingBeats.removeFirst()
            guard beat.subdivision == 0 else { continue }  // the lights follow the beats only
            currentBeat = beat.index
            beatPulse.toggle()
        }
    }

    // MARK: - Interruptions and route changes

    private func observeAudioChanges() {
        observers = [
            AudioSessionSetup.observe(AVAudioSession.interruptionNotification) { [weak self] notification in
                let interruption = AudioInterruption(notification)
                if interruption.began {
                    self?.pauseForSystem()
                } else if interruption.shouldResume {
                    self?.resumeAfterSystemPause()
                } else {
                    self?.resumesAfterSystemPause = false   // tap play to start again
                }
            },
            // The engine stops itself when the audio hardware changes (headphones, AirPods).
            AudioSessionSetup.observe(.AVAudioEngineConfigurationChange, object: engine) { [weak self] _ in
                guard let self, self.isPlaying else { return }
                self.halt()
                self.start()
            },
            // Without background audio, iOS silences the app once you leave it.
            AudioSessionSetup.observe(UIApplication.didEnterBackgroundNotification) { [weak self] _ in
                self?.pauseForSystem()
            },
            AudioSessionSetup.observe(UIApplication.willEnterForegroundNotification) { [weak self] _ in
                self?.resumeAfterSystemPause()
            },
        ]
    }

    /// iOS took the audio away: stop (the play button shows it) and start again afterwards.
    private func pauseForSystem() {
        guard isPlaying else { return }
        halt()
        resumesAfterSystemPause = true
    }

    private func resumeAfterSystemPause() {
        guard resumesAfterSystemPause else { return }
        start()
    }
}
