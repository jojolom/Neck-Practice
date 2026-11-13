//
//  CompositionFile.swift
//  Guitar Man
//
//  A composition as a file to send to someone else with Guitar Man (".guitarman"): the
//  composition as it's saved, in an envelope that says what it is and which version of the
//  format, so a file from a newer version of the app that this one can't read says so instead
//  of failing oddly. Reading one never trusts it: the composition's own decoding re-applies its
//  rules, the name is tidied, and it comes in as a new composition of its own (a new id), so
//  opening a file can't replace anything already saved.
//
//  No UI here, so scripts/chord-check.swift can check it.
//

import Foundation

enum CompositionFile {

    /// The file extension, and the type identifier the app declares for it (see Info.plist).
    static let fileExtension = "guitarman"
    static let typeIdentifier = "test.guitar-man.composition"

    static let format = "guitarman.composition"
    /// The newest version of the format this app writes and reads.
    static let version = 1
    /// Longest file worth reading (a composition is a few kilobytes).
    static let maxBytes = 1_000_000
    static let maxNameLength = 60

    enum ReadError: Error, Equatable {
        /// Not a Guitar Man composition at all.
        case notAComposition
        /// Made by a newer version of the app.
        case newerVersion
        case tooBig

        var message: String {
            switch self {
            case .notAComposition: return "That file isn't a Guitar Man composition."
            case .newerVersion:    return "That composition was made with a newer version of Guitar Man. Update the app to open it."
            case .tooBig:          return "That file is too big to be a Guitar Man composition."
            }
        }
    }

    private struct Envelope: Codable {
        var format: String
        var version: Int
        var composition: Composition
    }

    /// Only what says what the file is, read before the composition itself.
    private struct Header: Decodable {
        var format: String
        var version: Int
    }

    /// `composition` as a file's contents.
    static func data(for composition: Composition) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(Envelope(format: format, version: version, composition: composition))
    }

    /// The composition in a file's contents, as a new one of its own.
    static func composition(from data: Data) -> Result<Composition, ReadError> {
        guard data.count <= maxBytes else { return .failure(.tooBig) }
        let decoder = JSONDecoder()
        guard let header = try? decoder.decode(Header.self, from: data), header.format == format else {
            return .failure(.notAComposition)
        }
        guard header.version <= version else { return .failure(.newerVersion) }
        guard var composition = (try? decoder.decode(Envelope.self, from: data))?.composition else {
            return .failure(.notAComposition)
        }
        composition.id = UUID()
        composition.name = tidied(composition.name)
        composition.updatedAt = .now
        if let tempo = composition.tempo { composition.tempo = min(max(tempo, 40), 200) }
        return .success(composition)
    }

    /// A name fit to show: one line, not too long, never empty.
    static func tidied(_ name: String) -> String {
        let oneLine = name.components(separatedBy: .newlines).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return oneLine.isEmpty ? "Untitled" : String(oneLine.prefix(maxNameLength))
    }

    /// A file name for `name`: without the characters file systems and share sheets trip on.
    static func fileName(for name: String) -> String {
        let cleaned = tidied(name).map { "/\\:?%*|\"<>".contains($0) ? "-" : $0 }
        return String(cleaned)
    }
}
