//
//  SavedLoop.swift
//  Neck Practice
//
//  A single looper layer the user saved to reuse later. Only metadata lives in SwiftData;
//  the audio is a mono Float32 CAF in Application Support/Loops (see LoopLibrary).
//

import Foundation
import SwiftData

@Model
final class SavedLoop {
    var id: UUID
    var name: String
    var createdAt: Date
    /// Length of the saved layer in seconds.
    var duration: TimeInterval
    /// Sample rate the audio was recorded at; converted on load if the device is now at another rate.
    var sampleRate: Double
    /// File name inside `LoopLibrary.directory`.
    var fileName: String

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = .now,
        duration: TimeInterval,
        sampleRate: Double,
        fileName: String
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.duration = duration
        self.sampleRate = sampleRate
        self.fileName = fileName
    }
}

extension ModelContext {
    /// Deletes a saved loop together with its audio file (always delete through this, so no
    /// audio is orphaned on disk).
    func deleteSavedLoop(_ loop: SavedLoop) {
        LoopLibrary.delete(fileName: loop.fileName)
        delete(loop)
        try? save()
    }
}
