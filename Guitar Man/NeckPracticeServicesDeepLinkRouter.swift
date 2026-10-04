//
//  DeepLinkRouter.swift
//  Neck Practice
//
//  Carries "open this screen" requests that arrive outside SwiftUI (tapping a practice
//  reminder, its Start Now action) over to the UI. HomeView observes `pendingDailyPractice`.
//

import Observation

@Observable
final class DeepLinkRouter {

    static let shared = DeepLinkRouter()

    /// Set when the user asked to open Daily Practice; HomeView clears it once it has navigated.
    var pendingDailyPractice = false

    private init() {}

    func openDailyPractice() {
        pendingDailyPractice = true
    }
}
