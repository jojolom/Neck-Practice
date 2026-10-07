//
//  build-guitar-samples.swift
//
//  Builds the app's guitar sounds (Guitar Man/GuitarSamples/) from the FreePats Spanish
//  Classical Guitar SoundFont: https://freepats.zenvoid.org/Guitar/acoustic-guitar.html
//  (recorded by roberto@zenvoid.org, CC0 1.0 public domain dedication).
//
//  For each recorded note from C2 up it:
//    - trims the silence before the pluck (1 ms pre-roll, faded in), so notes start on time;
//    - caps the length at 7 s with a 60 ms fade-out (the app never rings a note longer);
//    - gives short recordings a natural sustain: the recordings above about A3 were faded out
//      early (gone within 2-3 s, cutting off long chords), so from where a note has fallen
//      24 dB, a stretch of whole periods (~80 ms) is looped seamlessly (crossfaded, its decay
//      flattened) and decays at a real string's rate while it mellows (a gentle, closing low-pass),
//      so every note rings at least 5 s (3 s at the top);
//    - evens out loudness: the first 250 ms of every note gets the same RMS, the loudest every
//      note can reach with its peak under -0.5 dBFS (the app sets its playback level from it);
//    - measures the note's actual pitch and records how far off it is, so the app can retune it
//      on playback. Pitch is measured as the ear hears it, from the first four harmonics over
//      about a second after the attack (a low string's fundamental alone wobbles with beating);
//    - writes AAC in CAF (mono, 44.1 kHz, 160 kbps) with afconvert.
//  plus nylon-guitar.json listing each note's file and tuning correction.
//
//  Run from the repo root (download and unpack SpanishClassicalGuitar-SF2-20190618.7z first):
//    swiftc -O -o /tmp/build-guitar-samples scripts/build-guitar-samples.swift && /tmp/build-guitar-samples path/to/SpanishClassicalGuitar-20190618.sf2
//

import Foundation

let lowestRoot = 36             // C2: a little below the guitar's low E
let maxSeconds = 7.0
let fadeOutSeconds = 0.06
let preRollSeconds = 0.001
let bitRate = 160_000
let outputDir = URL(fileURLWithPath: "Guitar Man/GuitarSamples", isDirectory: true)

// MARK: - SoundFont parsing

struct Sample { var name: String; var data: [Int16]; var rate: Double; var root: Int }

func readSamples(_ url: URL) -> [Sample] {
    let data = try! Data(contentsOf: url)
    func u32(_ o: Int) -> Int { Int(data[o]) | Int(data[o+1]) << 8 | Int(data[o+2]) << 16 | Int(data[o+3]) << 24 }
    func u16(_ o: Int) -> Int { Int(data[o]) | Int(data[o+1]) << 8 }
    func name(_ o: Int) -> String {
        String(decoding: data[o..<o+20].prefix { $0 != 0 }, as: UTF8.self)
    }
    var smpl = 0..<0, shdr = 0..<0, inst = 0..<0, ibag = 0..<0, igen = 0..<0
    var off = 12
    while off < data.count {
        let id = String(decoding: data[off..<off+4], as: UTF8.self), size = u32(off + 4)
        if id == "LIST" {
            var o = off + 12
            while o < off + 8 + size {
                let cid = String(decoding: data[o..<o+4], as: UTF8.self), cs = u32(o + 4)
                switch cid {
                case "smpl": smpl = (o + 8)..<(o + 8 + cs)
                case "shdr": shdr = (o + 8)..<(o + 8 + cs)
                case "inst": inst = (o + 8)..<(o + 8 + cs)
                case "ibag": ibag = (o + 8)..<(o + 8 + cs)
                case "igen": igen = (o + 8)..<(o + 8 + cs)
                default: break
                }
                o += 8 + cs + (cs & 1)
            }
        }
        off += 8 + size + (size & 1)
    }
    // The first instrument's zones, each naming a sample (generator 53).
    let firstBag = u16(inst.lowerBound + 20), endBag = u16(inst.lowerBound + 22 + 20)
    var result: [Sample] = []
    for bag in firstBag..<endBag {
        let g0 = u16(ibag.lowerBound + bag * 4), g1 = u16(ibag.lowerBound + (bag + 1) * 4)
        for g in g0..<g1 where u16(igen.lowerBound + g * 4) == 53 {
            let s = shdr.lowerBound + u16(igen.lowerBound + g * 4 + 2) * 46
            let start = u32(s + 20), end = u32(s + 24), rate = u32(s + 36), root = Int(data[s + 40])
            let pcm = (start..<end).map { i -> Int16 in
                let o = smpl.lowerBound + i * 2
                return Int16(bitPattern: UInt16(data[o]) | UInt16(data[o + 1]) << 8)
            }
            result.append(Sample(name: name(s), data: pcm, rate: Double(rate), root: root))
        }
    }
    return result
}

// MARK: - Analysis

func rms(_ x: ArraySlice<Float>) -> Float { (x.reduce(0) { $0 + $1 * $1 } / Float(max(x.count, 1))).squareRoot() }

/// Goertzel magnitude of a Hann-windowed segment at `hz`.
func magnitude(_ x: [Float], _ hz: Double, _ rate: Double) -> Double {
    let n = x.count, w = 2 * Double.pi * hz / rate, c = 2 * cos(w)
    var s1 = 0.0, s2 = 0.0
    for i in 0..<n {
        let hann = 0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(n - 1))
        let s0 = Double(x[i]) * hann + c * s1 - s2
        s2 = s1; s1 = s0
    }
    return max(s1 * s1 + s2 * s2 - c * s1 * s2, 0).squareRoot()
}

/// How far (in cents) `x` is from `midi`: each of the first four harmonics' peak (within
/// ±80 cents of where it should be), weighted by its strength.
func pitchError(_ x: ArraySlice<Float>, midi: Int, rate: Double) -> Double {
    let segment = Array(x)
    let f = 440 * pow(2, Double(midi - 69) / 12)
    var weighted = 0.0, total = 0.0
    for k in 1...4 where Double(k) * f < rate / 2 * 0.9 {
        var lo = -80.0, hi = 80.0, peak = 0.0
        for step in [4.0, 0.4, 0.04] {
            var best = lo, bestMag = -1.0, c = lo
            while c <= hi {
                let m = magnitude(segment, Double(k) * f * pow(2, c / 1200), rate)
                if m > bestMag { bestMag = m; best = c }
                c += step
            }
            lo = best - step; hi = best + step; peak = bestMag
        }
        weighted += peak * (lo + hi) / 2
        total += peak
    }
    return total > 0 ? weighted / total : 0
}

/// The slice to measure pitch on: from 0.15 s after the pluck, about a second long.
func pitchWindow(_ x: [Float], rate: Double) -> ArraySlice<Float> {
    let begin = min(Int(0.15 * rate), x.count / 4)
    return x[begin..<min(x.count, begin + Int(1.0 * rate))]
}

// MARK: - Build

func writeWav(_ x: [Float], rate: Double, to url: URL) {
    var pcm = Data(capacity: x.count * 2)
    for s in x { var v = Int16(max(-1, min(1, s)) * 32767).littleEndian; pcm.append(Data(bytes: &v, count: 2)) }
    var wav = Data()
    func le<T: FixedWidthInteger>(_ v: T) { var x = v.littleEndian; wav.append(Data(bytes: &x, count: MemoryLayout<T>.size)) }
    wav.append("RIFF".data(using: .ascii)!); le(UInt32(36 + pcm.count)); wav.append("WAVE".data(using: .ascii)!)
    wav.append("fmt ".data(using: .ascii)!); le(UInt32(16)); le(UInt16(1)); le(UInt16(1))
    le(UInt32(rate)); le(UInt32(rate * 2)); le(UInt16(2)); le(UInt16(16))
    wav.append("data".data(using: .ascii)!); le(UInt32(pcm.count)); wav.append(pcm)
    try! wav.write(to: url)
}

struct Entry: Codable { var midi: Int; var file: String; var cents: Double }
struct Manifest: Codable {
    var source = "FreePats Spanish Classical Guitar 2019-06-18 (https://freepats.zenvoid.org/Guitar/acoustic-guitar.html), CC0 1.0"
    var sampleRate: Double
    /// RMS of every note's first 250 ms (0–1 full scale), for the app to set its level from.
    var attackRMS: Double
    /// Each note's recording, and how many cents sharp (+) or flat (-) it was recorded.
    var notes: [Entry]
}

let samples = readSamples(URL(fileURLWithPath: CommandLine.arguments[1])).filter { $0.root >= lowestRoot }
try? FileManager.default.removeItem(at: outputDir)
try! FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
let temp = FileManager.default.temporaryDirectory.appendingPathComponent("guitar-build-\(getpid())")
try! FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)

// Trim each note, then find the common loudness to match.
var trimmed: [(Sample, [Float])] = []
for s in samples {
    let x = s.data.map { Float($0) / 32768 }
    let peak = x.map(abs).max() ?? 1
    let onset = x.firstIndex { abs($0) > peak * 0.05 } ?? 0
    let start = max(0, onset - Int(preRollSeconds * s.rate))
    var y = Array(x[start..<min(x.count, start + Int(maxSeconds * s.rate))])
    let fadeIn = onset - start
    for i in 0..<fadeIn { y[i] *= Float(i) / Float(max(fadeIn, 1)) }
    trimmed.append((s, y))
}

// MARK: - Sustain

/// How long every note should ring at least: a whole note at a slow tempo.
func sustainSeconds(_ midi: Int) -> Double { midi <= 72 ? 5 : max(3, 5 - Double(midi - 72) / 6) }

/// A real string's decay in dB/s (the same ring time as the app's synth, PluckedString).
func stringDecay(_ midi: Int) -> Double { 60 / (10 * pow(2, -Double(midi - 40) / 24)) }

/// `y` rung out to `sustainSeconds`, if it's shorter: see the header.
func extended(_ y: [Float], midi: Int, cents: Double, rate: Double) -> [Float] {
    let needed = Int(sustainSeconds(midi) * rate)
    guard y.count < needed else { return y }
    // Splice where the note has fallen 24 dB (or 0.2 s before the recording ends).
    let frame = Int(0.02 * rate)
    let attackLevel = rms(y.prefix(Int(0.25 * rate)))
    var splice = y.count - Int(0.2 * rate)
    var at = Int(0.3 * rate)
    while at + frame < splice {
        if rms(y[at..<at + frame]) < attackLevel * 0.063 { splice = at; break }  // -24 dB
        at += frame
    }
    let period = rate / (440 * pow(2, (Double(midi - 69) + cents / 100) / 12))
    let loopLength = Int((Double(max(1, Int((0.08 * rate / period).rounded()))) * period).rounded())
    let crossfade = min(Int(0.015 * rate), loopLength / 2)
    let loopStart = splice - loopLength
    guard loopStart - crossfade > Int(0.1 * rate) else { return y }

    // Flatten the decay across the looped stretch (and the crossfade before it) so the loop
    // doesn't pulse: scale every sample to the level at the splice.
    let region = loopStart - crossfade
    let early = rms(y[region..<region + loopLength / 2]), late = rms(y[splice - loopLength / 2..<splice])
    let perSample = log(Double(late / max(early, 1e-9))) / Double(splice - loopLength / 2 - region)
    let flat = (region..<splice).map { i in y[i] * Float(exp(-perSample * Double(i - splice))) }
    // The loop: [loopStart, splice), its end crossfaded into what comes just before its start, so
    // wrapping around is seamless.
    var loop = Array(flat[crossfade..<flat.count])
    for i in 0..<crossfade {
        let w = Float(0.5 - 0.5 * cos(Double.pi * Double(i) / Double(crossfade)))
        loop[loopLength - crossfade + i] = loop[loopLength - crossfade + i] * (1 - w) + flat[i] * w
    }
    // The recording up to the splice, ending in the same crossfade, then the loop over and over,
    // decaying like a string and slowly losing its brightness.
    var out = Array(y[0..<splice - crossfade]) + loop[(loopLength - crossfade)...]
    let decayPerSample = -stringDecay(midi) / 20 * log(10) / rate
    var lowPassed: Float = 0
    for n in 0..<(needed - out.count) {
        let raw = loop[n % loopLength] * Float(exp(decayPerSample * Double(n)))
        let alpha = Float(0.25 + 0.75 * exp(-Double(n) / (0.8 * rate)))
        lowPassed = n == 0 ? raw : lowPassed + alpha * (raw - lowPassed)
        out.append(lowPassed)
    }
    return out
}
let attack = Int(0.25 * 44_100)
let peakLimit: Float = 0.944  // -0.5 dBFS
// The loudest attack RMS every note can reach without its peak going over the limit.
let target = trimmed.map { rms($0.1.prefix(attack)) * peakLimit / ($0.1.map(abs).max() ?? 1) }.min() ?? 0.1

var manifest = Manifest(sampleRate: samples.first?.rate ?? 44_100, attackRMS: Double(target), notes: [])
for (s, y) in trimmed {
    let gain = target / max(rms(y.prefix(attack)), 1e-6)
    let cents = pitchError(pitchWindow(y, rate: s.rate), midi: s.root, rate: s.rate)
    var out = extended(y.map { $0 * gain }, midi: s.root, cents: cents, rate: s.rate)
    let fade = min(Int(fadeOutSeconds * s.rate), out.count)
    for i in 0..<fade { out[out.count - 1 - i] *= Float(0.5 - 0.5 * cos(Double.pi * Double(i) / Double(fade))) }
    let file = "nylon-guitar-\(s.root).caf"
    let wav = temp.appendingPathComponent("\(s.root).wav")
    writeWav(out, rate: s.rate, to: wav)
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
    p.arguments = ["-f", "caff", "-d", "aac", "-b", String(bitRate), wav.path, outputDir.appendingPathComponent(file).path]
    try! p.run(); p.waitUntilExit()
    precondition(p.terminationStatus == 0, "afconvert failed for \(file)")
    manifest.notes.append(Entry(midi: s.root, file: file, cents: (cents * 10).rounded() / 10))
    print(String(format: "%-5@ MIDI %d  %.1f s  gain %+.1f dB  tuning %+.1f cents", s.name, s.root,
                 Double(out.count) / s.rate, 20 * log10(Double(gain)), cents))
}
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try! encoder.encode(manifest).write(to: outputDir.appendingPathComponent("nylon-guitar.json"))
try? FileManager.default.removeItem(at: temp)
let bytes = (try! FileManager.default.contentsOfDirectory(at: outputDir, includingPropertiesForKeys: [.fileSizeKey]))
    .compactMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }.reduce(0, +)
print(String(format: "%d notes, attack RMS %.1f dBFS, %.1f MB in %@", manifest.notes.count,
             20 * log10(Double(target)), Double(bytes) / 1e6, outputDir.path))
