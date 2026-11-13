//
//  DeepLinkRouter.swift
//  Neck Practice
//
//  Carries "open this screen" requests that arrive outside SwiftUI (tapping a practice
//  reminder, its Start Now action, opening a composition file someone sent) over to the UI.
//  HomeView observes `pendingDailyPractice` and `pendingCompose`.
//

import Observation

@Observable
final class DeepLinkRouter {

    static let shared = DeepLinkRouter()

    /// Set when the user asked to open Daily Practice; HomeView clears it once it has navigated.
    var pendingDailyPractice = false

    /// Set when a composition file was opened from outside the app: HomeView goes to Compose,
    /// and its list shows what happened (`composeMessage`) and clears it.
    var pendingCompose = false
    var composeMessage: String? = nil

    private init() {}

    /// A composition file was opened; `message` says whether it was added.
    func openCompose(message: String) {
        composeMessage = message
        pendingCompose = true
    }

    func openDailyPractice() {
        pendingDailyPractice = true
    }
}
