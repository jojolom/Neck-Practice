//
//  AnswerPacing.swift
//  Guitar Man
//
//  What the games do after you answer: wait for you to tap Next, so there's time to take in
//  the answer on screen (the default), wait only after a wrong answer, or move on by
//  themselves after a moment as they used to. One setting for every game, in each game's
//  Settings. NextGate is what a game hands its "move on" step to.
//

import Foundation
import Observation

enum AnswerPacing: String, CaseIterable, Identifiable {
    /// Wait for Next after every answer.
    case always
    /// Wait for Next after a wrong answer; move on by itself after a right one.
    case afterMistakes
    /// Move on by itself after a moment.
    case automatic

    var id: String { rawValue }

    static let key = "games.answerPacing"

    static var current: AnswerPacing {
        UserDefaults.standard.string(forKey: key).flatMap(AnswerPacing.init(rawValue:)) ?? .always
    }

    var displayName: String {
        switch self {
        case .always:        return "Wait for Next"
        case .afterMistakes: return "Wait After Mistakes"
        case .automatic:     return "Move On by Itself"
        }
    }

    func waits(afterCorrect correct: Bool) -> Bool {
        switch self {
        case .always:        return true
        case .afterMistakes: return !correct
        case .automatic:     return false
        }
    }
}

/// Holds a game's next step after an answer: runs it after `delay`, or keeps it until Next is
/// tapped, as the player's AnswerPacing says.
@Observable
final class NextGate {

    /// Showing the Next button.
    private(set) var isWaiting = false

    private var pending: (() -> Void)?
    private var waitingSince = Date.distantPast

    /// After an answer (`correct` or not): do `action` after `delay`, or wait for `next()`.
    func after(_ delay: TimeInterval, correct: Bool, perform action: @escaping () -> Void) {
        if AnswerPacing.current.waits(afterCorrect: correct) {
            pending = action
            waitingSince = Date()
            isWaiting = true
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: action)
        }
    }

    /// Next was tapped. A tap right as the button appears (a double tap on the answer) is ignored.
    func next() {
        guard let action = pending, Date().timeIntervalSince(waitingSince) > 0.3 else { return }
        pending = nil
        isWaiting = false
        action()
    }

    /// Drop the waiting step (the game restarted or its settings changed).
    func cancel() {
        pending = nil
        isWaiting = false
    }
}
