//
//  SynthTone.swift
//  Neck Practice
//
//  Tiny synthesized beeps (tuner chime, looper count-in clicks). Builds a decaying sine
//  as an in-memory WAV so no audio assets are needed.
//

import AVFoundation

enum SynthTone {

    /// An `AVAudioPlayer` holding a decaying sine burst, ready to `play()`.
    static func player(frequency: Double, duration: Double,
                       amplitude: Double = 0.25, volume: Float = 1.0) -> AVAudioPlayer? {
        let player = try? AVAudioPlayer(data: wavData(frequency: frequency, duration: duration, amplitude: amplitude))
        player?.volume = volume
        player?.prepareToPlay()
        return player
    }

    /// 16-bit mono PCM WAV of a sine at `frequency` Hz that decays linearly to silence.
    static func wavData(frequency: Double, duration: Double, amplitude: Double = 0.25) -> Data {
        let sampleRate = 44100
        let count = Int(Double(sampleRate) * duration)

        // Generate 16-bit PCM samples
        var pcm = Data(count: count * 2)
        pcm.withUnsafeMutableBytes { raw in
            let buf = raw.bindMemory(to: Int16.self)
            for i in 0..<count {
                let t = Double(i) / Double(sampleRate)
                let envelope = 1.0 - t / duration
                buf[i] = Int16(sin(2.0 * .pi * frequency * t) * envelope * amplitude * Double(Int16.max))
            }
        }

        // Build a minimal WAV in memory
        var wav = Data()
        let dataSize = pcm.count
        func le<T: FixedWidthInteger>(_ v: T) { var x = v.littleEndian; wav.append(Data(bytes: &x, count: MemoryLayout<T>.size)) }

        wav.append("RIFF".data(using: .ascii)!)
        le(UInt32(36 + dataSize))
        wav.append("WAVE".data(using: .ascii)!)
        wav.append("fmt ".data(using: .ascii)!)
        le(UInt32(16));   le(UInt16(1));   le(UInt16(1))            // PCM, mono
        le(UInt32(sampleRate)); le(UInt32(sampleRate * 2))          // sample rate, byte rate
        le(UInt16(2));   le(UInt16(16))                              // block align, bits
        wav.append("data".data(using: .ascii)!)
        le(UInt32(dataSize))
        wav.append(pcm)
        return wav
    }
}
