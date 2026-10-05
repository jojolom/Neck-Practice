//
//  AudioSession.swift
//  Neck Practice
//
//  The app's AVAudioSession setup in one place, plus helpers for reacting when iOS takes the
//  audio away (calls, Siri, alarms) or the route changes (headphones, AirPods, an interface).
//  Every category mixes with other apps' audio, so you can play along with a backing track in
//  Music, Spotify or YouTube instead of having it paused.
//

import AVFoundation

enum AudioSessionSetup {

    /// Playback only: notes, cues, and the metronome.
    static func activatePlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    /// Microphone plus playback: the tuner and looper. Plays through the speaker (not the
    /// earpiece) or Bluetooth headphones, and records from the built-in or wired mic.
    static func activateRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
        try session.setActive(true)
    }

    /// Calls `handler` on the main actor each time `name` is posted (by `object`, if given).
    /// Pass the returned token to `NotificationCenter.default.removeObserver(_:)` to stop.
    static func observe(_ name: Notification.Name, object: Any? = nil,
                        _ handler: @escaping @MainActor (Notification) -> Void) -> any NSObjectProtocol {
        NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { notification in
            MainActor.assumeIsolated { handler(notification) }
        }
    }
}

/// What an `AVAudioSession.interruptionNotification` reports.
struct AudioInterruption {
    /// True when the interruption started (a call came in), false when it ended.
    let began: Bool
    /// When it ended: iOS suggests picking up where playback left off.
    let shouldResume: Bool

    init(_ notification: Notification) {
        let info = notification.userInfo
        let type = (info?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
        began = type == .began
        let options = AVAudioSession.InterruptionOptions(rawValue: info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
        shouldResume = options.contains(.shouldResume)
    }
}
