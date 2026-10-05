//
//  AudioSession.swift
//  Neck Practice
//
//  The app's AVAudioSession setup in one place. Every category mixes with other apps' audio,
//  so you can play along with a backing track in Music, Spotify or YouTube instead of having
//  it paused.
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
}
