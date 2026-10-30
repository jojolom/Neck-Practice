//
//  BackingTrack.swift
//  Guitar Man
//
//  Plays Solo Buddy's groove on a loop, on AudioPlayer's sample-accurate timeline. A timer
//  hands each bar to AudioPlayer a moment before it's due (see BarClock), so every bar starts
//  exactly where the last ended, and a change to the groove (chords, style, tempo, key) comes
//  in at the next bar. An optional one-bar count-in and a click on every beat use the
//  metronome's click (ClickVoice). Stops for calls and when the app goes to the background.
//

import AVFoundation
import Observation
import UIKit

@Observable
final class BackingTrack {

    /// What it plays; changes take effect from the next bar.
    var groove = SoloGroove()
    /// One bar of clicks before the backing starts.
    var countsIn = true
    /// A click on every beat while it plays.
    var clicks = false

    private(set) var isPlaying = false
    /// The bar you're hearing (0 = the first after the count-in), or nil (stopped, counting in).
    private(set) var bar: Int?
    /// The beat you're hearing in the bar (or in the count-in), 0-based.
    private(set) var beat = 0
    private(set) var isCountingIn = false

    /// How far ahead of its start a bar is handed to AudioPlayer.
    private let lookahead: TimeInterval = 0.3
    private var clock: BarClock?
    private var scheduled: [BarClock.Bar] = []
    private var countInStart: Int64 = 0
    private var countInFrames: Int64 = 0
    private var sampleRate: Double = 48_000
    private var timer: Timer?
    private var observers: [any NSObjectProtocol] = []

    private var framesPerBeat: Double { groove.secondsPerBeat * sampleRate }
    private var framesPerBar: Int64 { Int64((Double(groove.beatsPerBar) * framesPerBeat).rounded()) }

    func start() {
        guard !isPlaying, let timeline = AudioPlayer.shared.timeline() else { return }
        AudioPlayer.shared.stopAll()
        sampleRate = timeline.sampleRate
        var first = timeline.frame + Int64(0.15 * sampleRate)
        countInStart = first
        countInFrames = 0
        if countsIn {
            countInFrames = framesPerBar
            let beatSeconds = groove.secondsPerBeat
            AudioPlayer.shared.play((0..<groove.beatsPerBar).map { beat in
                AudioPlayer.ScheduledNote(midi: 0, delay: Double(beat) * beatSeconds, gain: 1,
                                          sound: beat == 0 ? .accentClick : .click)
            }, fromFrame: first)
            first += countInFrames
        }
        clock = BarClock(firstBarFrame: first)
        scheduled = []
        isPlaying = true
        isCountingIn = countsIn
        bar = nil
        beat = 0
        observe()
        tick()
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        guard isPlaying else { return }
        timer?.invalidate()
        timer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        AudioPlayer.shared.stopAll()
        isPlaying = false
        isCountingIn = false
        bar = nil
        beat = 0
        clock = nil
        scheduled = []
    }

    // MARK: - Scheduling

    private func tick() {
        guard isPlaying, var clock, let timeline = AudioPlayer.shared.timeline() else { return }
        let now = timeline.frame
        let due = clock.bars(dueBy: now + Int64(lookahead * sampleRate), framesPerBar: framesPerBar)
        self.clock = clock
        for bar in due { schedule(bar) }
        scheduled += due
        if scheduled.count > 8 { scheduled.removeFirst(scheduled.count - 8) }

        // What you're hearing: the timeline runs a little ahead of the speaker.
        let session = AVAudioSession.sharedInstance()
        let heard = now - Int64((session.outputLatency + session.ioBufferDuration) * sampleRate)
        if let position = clock.position(at: heard, in: scheduled) {
            isCountingIn = false
            bar = position.index
            beat = min(Int(position.fraction * Double(groove.beatsPerBar)), groove.beatsPerBar - 1)
        } else if countInFrames > 0, heard >= countInStart {
            isCountingIn = true
            beat = min(Int(Double(heard - countInStart) / framesPerBeat), groove.beatsPerBar - 1)
        }
    }

    private func schedule(_ bar: BarClock.Bar) {
        let beatSeconds = Double(bar.frames) / sampleRate / Double(groove.beatsPerBar)
        var notes = groove.hits(forBar: bar.index).map { hit in
            AudioPlayer.ScheduledNote(midi: hit.midi, delay: hit.beat * beatSeconds + hit.roll,
                                      duration: hit.beats * beatSeconds, gain: hit.gain)
        }
        if clicks {
            notes += (0..<groove.beatsPerBar).map { beat in
                AudioPlayer.ScheduledNote(midi: 0, delay: Double(beat) * beatSeconds, gain: 0.8,
                                          sound: beat == 0 ? .accentClick : .click)
            }
        }
        AudioPlayer.shared.play(notes, fromFrame: bar.frame)
    }

    // MARK: - Interruptions

    private func observe() {
        observers = [
            AudioSessionSetup.observe(AVAudioSession.interruptionNotification) { [weak self] _ in self?.stop() },
            AudioSessionSetup.observe(UIApplication.didEnterBackgroundNotification) { [weak self] _ in self?.stop() },
        ]
    }
}
