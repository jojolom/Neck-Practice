//
//  LoopLibrary.swift
//  Neck Practice
//
//  File I/O for saved looper layers (mono Float32 CAF in Application Support/Loops),
//  sample-rate conversion, and a small player for auditioning layers. Foundation/AVFoundation
//  only (no AVAudioSession), so it can be exercised offline — see scripts/loop-library-check.swift.
//

import AVFoundation
import Foundation
import Observation

enum LoopLibraryError: Error {
    case invalidFormat
    case emptyAudio
}

enum LoopLibrary {

    /// Folder that holds saved layer audio. Overridable so tests don't touch the real library.
    static var directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Loops", isDirectory: true)
    }()

    static func fileURL(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    // MARK: - Write / read / delete

    /// Writes `samples` (mono) as `<uuid>.caf` and returns the file name.
    static func write(samples: [Float], sampleRate: Double) throws -> String {
        guard !samples.isEmpty else { throw LoopLibraryError.emptyAudio }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                         channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { throw LoopLibraryError.invalidFormat }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }

        let fileName = UUID().uuidString + ".caf"
        let file = try AVAudioFile(forWriting: fileURL(for: fileName), settings: format.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
        file.close()   // finalize before anyone reads it back
        return fileName
    }

    /// Reads a saved layer back as mono samples plus the rate it was stored at.
    static func read(fileName: String) throws -> (samples: [Float], sampleRate: Double) {
        let file = try AVAudioFile(forReading: fileURL(for: fileName),
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        guard file.length > 0 else { throw LoopLibraryError.emptyAudio }

        // `AVAudioFile.read(into:)` returns at most 65,536 frames per call, so read in chunks.
        let total = Int(file.length)
        var samples: [Float] = []
        samples.reserveCapacity(total)
        guard let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 32768) else {
            throw LoopLibraryError.invalidFormat
        }
        while samples.count < total {
            try file.read(into: chunk)
            guard chunk.frameLength > 0, let channel = chunk.floatChannelData?[0] else { break }
            samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(chunk.frameLength)))
        }
        guard !samples.isEmpty else { throw LoopLibraryError.emptyAudio }
        return (samples, format.sampleRate)
    }

    static func delete(fileName: String) {
        try? FileManager.default.removeItem(at: fileURL(for: fileName))
    }

    // MARK: - Sample-rate conversion

    /// Converts mono samples between sample rates with `AVAudioConverter` (no-op when equal).
    /// The result is exactly `count × to / from` frames long.
    static func resample(_ samples: [Float], from: Double, to: Double) -> [Float] {
        guard !samples.isEmpty, from > 0, to > 0, abs(from - to) > 0.5 else { return samples }

        let expected = Int((Double(samples.count) * to / from).rounded())
        guard let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: from, channels: 1, interleaved: false),
              let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: to, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let input = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(samples.count)),
              let output = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(expected + 4096)),
              let inChannel = input.floatChannelData?[0]
        else { return samples }

        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { inChannel.update(from: $0.baseAddress!, count: samples.count) }

        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .endOfStream
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, let outChannel = output.floatChannelData?[0] else { return samples }

        var result = Array(UnsafeBufferPointer(start: outChannel, count: Int(output.frameLength)))
        if result.count < expected {
            result += [Float](repeating: 0, count: expected - result.count)
        } else if result.count > expected {
            result.removeLast(result.count - expected)
        }
        return result
    }

    // MARK: - Preview audio

    /// 16-bit mono PCM WAV of `samples` (clipped to ±1), for auditioning a layer that only
    /// exists in memory.
    static func wavData(samples: [Float], sampleRate: Double) -> Data {
        var pcm = Data(count: samples.count * 2)
        pcm.withUnsafeMutableBytes { raw in
            let buf = raw.bindMemory(to: Int16.self)
            let scale = Float(Int16.max)
            for i in 0..<samples.count {
                let clipped = max(-1.0, min(1.0, samples[i]))
                buf[i] = Int16(clipped * scale)
            }
        }

        var wav = Data()
        func le<T: FixedWidthInteger>(_ v: T) { var x = v.littleEndian; wav.append(Data(bytes: &x, count: MemoryLayout<T>.size)) }
        let rate = UInt32(sampleRate.rounded())
        wav.append("RIFF".data(using: .ascii)!)
        le(UInt32(36 + pcm.count))
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        le(UInt32(16)); le(UInt16(1)); le(UInt16(1))      // PCM, mono
        le(rate); le(rate * 2)                            // sample rate, byte rate
        le(UInt16(2)); le(UInt16(16))                     // block align, bits
        wav.append("data".data(using: .ascii)!)
        le(UInt32(pcm.count))
        wav.append(pcm)
        return wav
    }
}

// MARK: - LoopPreviewPlayer

/// Plays one layer at a time for auditioning; tapping the playing one again stops it.
@Observable
final class LoopPreviewPlayer: NSObject, AVAudioPlayerDelegate {

    /// Identifies whichever layer is currently playing (for the ▶/■ icon).
    private(set) var playingID: AnyHashable?
    private var player: AVAudioPlayer?

    func toggle(id: AnyHashable, makePlayer: () -> AVAudioPlayer?) {
        if playingID == id {
            stop()
            return
        }
        stop()
        guard let newPlayer = makePlayer() else { return }
        newPlayer.delegate = self
        player = newPlayer
        playingID = id
        newPlayer.play()
    }

    func playSamples(id: AnyHashable, samples: [Float], sampleRate: Double) {
        toggle(id: id) {
            try? AVAudioPlayer(data: LoopLibrary.wavData(samples: samples, sampleRate: sampleRate))
        }
    }

    func playFile(id: AnyHashable, fileName: String) {
        toggle(id: id) {
            try? AVAudioPlayer(contentsOf: LoopLibrary.fileURL(for: fileName))
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.player === player {
                self.player = nil
                self.playingID = nil
            }
        }
    }
}
