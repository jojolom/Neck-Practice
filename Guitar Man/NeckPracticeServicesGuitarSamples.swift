//
//  GuitarSamples.swift
//  Guitar Man
//
//  The recorded nylon-string guitar AudioPlayer plays: one recording per note (from the FreePats
//  Spanish Classical Guitar, CC0), built into GuitarSamples/ by scripts/build-guitar-samples.swift,
//  which also measured how far each recording is out of tune. Notes without their own
//  recording borrow the nearest one, pitched to fit; every note is retuned exactly on playback.
//  No UIKit or audio session here, so it's checked offline by scripts/sampler-check.swift.
//

import AVFoundation
import Foundation

// MARK: - GuitarSampleBank

/// The decoded recordings, kept as 16-bit samples (about 15 MB).
nonisolated final class GuitarSampleBank {

    /// One recorded note.
    final class Recording {
        let midi: Int
        /// How many cents sharp (+) or flat (-) the string was when recorded.
        let cents: Double
        let sampleRate: Double
        let samples: [Int16]

        init(midi: Int, cents: Double, sampleRate: Double, samples: [Int16]) {
            self.midi = midi
            self.cents = cents
            self.sampleRate = sampleRate
            self.samples = samples
        }
    }

    private struct Manifest: Decodable {
        struct Note: Decodable { var midi: Int; var file: String; var cents: Double }
        var attackRMS: Double
        var notes: [Note]
    }

    static let manifestName = "nylon-guitar"

    private static let sharedLock = NSLock()
    nonisolated(unsafe) private static var loaded: GuitarSampleBank?
    nonisolated(unsafe) private static var isLoading = false

    /// The app's recordings once `preload()` has finished; nil before then, or if they failed.
    static var shared: GuitarSampleBank? {
        sharedLock.lock(); defer { sharedLock.unlock() }
        return loaded
    }

    /// Decodes the app's recordings in the background (once), so they're ready by the first note.
    static func preload() {
        sharedLock.lock()
        guard !isLoading else { sharedLock.unlock(); return }
        isLoading = true
        sharedLock.unlock()
        DispatchQueue.global(qos: .userInitiated).async {
            let started = Date()
            let bank = load()
            if let bank {
                print(String(format: "GuitarSampleBank: loaded %d recordings in %.2f s", bank.recordings.count,
                             Date().timeIntervalSince(started)))
            } else {
                print("GuitarSampleBank: recordings didn't load; AudioPlayer will use the synth")
            }
            sharedLock.lock(); loaded = bank; sharedLock.unlock()
        }
    }

    /// Sorted by pitch.
    let recordings: [Recording]
    /// RMS (0–1) of every recording's first 250 ms: they're all leveled to it.
    let attackRMS: Double

    private init(recordings: [Recording], attackRMS: Double) {
        self.recordings = recordings.sorted { $0.midi < $1.midi }
        self.attackRMS = attackRMS
    }

    /// Loads the recordings from `directory`, or from the app bundle; nil if they're missing
    /// or any fails to decode.
    static func load(from directory: URL? = nil) -> GuitarSampleBank? {
        func url(_ name: String, _ ext: String) -> URL? {
            if let directory { return directory.appendingPathComponent("\(name).\(ext)") }
            return Bundle.main.url(forResource: name, withExtension: ext)
                ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "GuitarSamples")
        }
        guard let manifestURL = url(manifestName, "json"),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }
        var recordings: [Recording] = []
        for note in manifest.notes {
            let name = (note.file as NSString).deletingPathExtension, ext = (note.file as NSString).pathExtension
            guard let fileURL = url(name, ext), let samples = decode(fileURL) else { return nil }
            recordings.append(Recording(midi: note.midi, cents: note.cents,
                                        sampleRate: samples.rate, samples: samples.data))
        }
        return recordings.isEmpty ? nil : GuitarSampleBank(recordings: recordings, attackRMS: manifest.attackRMS)
    }

    private static func decode(_ url: URL) -> (data: [Int16], rate: Double)? {
        guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let channel = buffer.floatChannelData?[0] else { return nil }
        let samples = (0..<Int(buffer.frameLength)).map { Int16(max(-1, min(1, channel[$0])) * 32767) }
        return (samples, file.processingFormat.sampleRate)
    }

    /// The recording to play `midi` from: its own, or the nearest (the lower one on a tie).
    func recording(for midi: Int) -> Recording {
        var best = recordings[0]
        for recording in recordings where abs(recording.midi - midi) < abs(best.midi - midi) {
            best = recording
        }
        return best
    }
}

// MARK: - SampledNote

/// One note played from a recording: read at whatever speed puts it exactly in tune at the
/// output rate (cubic interpolation between samples), from its scheduled frame, until the
/// recording ends or the note fades out.
nonisolated final class SampledNote: NoteVoice {

    private var envelope: NoteEnvelope
    private let recording: GuitarSampleBank.Recording
    /// Recording samples per output frame.
    private let step: Double
    private var position: Double = 0
    private let gain: Float

    var isFinished: Bool { envelope.isFinished }

    init(midi: Int, recording: GuitarSampleBank.Recording, outputRate: Double,
         startFrame: Int64, releaseFrame: Int64, releaseFrames: Int, gain: Float) {
        envelope = NoteEnvelope(startFrame: startFrame, releaseFrame: releaseFrame, releaseFrames: releaseFrames)
        self.recording = recording
        let semitones = Double(midi - recording.midi) - recording.cents / 100
        step = recording.sampleRate / outputRate * pow(2, semitones / 12)
        self.gain = gain / 32768
    }

    func isSounding(at frame: Int64) -> Bool { envelope.isSounding(at: frame) }

    func release(at frame: Int64, fadeFrames: Int) { envelope.release(at: frame, fadeFrames: fadeFrames) }

    func render(into out: UnsafeMutablePointer<Float>, count: Int, bufferStart: Int64) {
        guard let first = envelope.firstFrame(bufferStart: bufferStart, count: count) else { return }
        recording.samples.withUnsafeBufferPointer { x in
            let last = x.count - 1
            for i in first..<count {
                let index = Int(position)
                guard index + 2 <= last else {
                    envelope.finish()  // the recording has ended
                    return
                }
                guard let level = envelope.level(at: bufferStart + Int64(i)) else { return }
                // Catmull-Rom between x[index] and x[index + 1].
                let t = Float(position - Double(index))
                let p0 = Float(x[max(index - 1, 0)]), p1 = Float(x[index])
                let p2 = Float(x[index + 1]), p3 = Float(x[index + 2])
                let sample = p1 + 0.5 * t * (p2 - p0 + t * (2 * p0 - 5 * p1 + 4 * p2 - p3 + t * (3 * (p1 - p2) + p3 - p0)))
                out[i] += sample * gain * level
                position += step
            }
        }
    }
}
