//
//  Analytics.swift
//  Guitar Man
//
//  Anonymous usage counts through TelemetryDeck (https://telemetrydeck.com): how many people
//  use the app each day, which screens they open, and how Daily Practice sessions go. No
//  personal data: TelemetryDeck identifies a device only by a salted hash of an anonymous ID,
//  and nothing is linked to a person or used for tracking. Debug builds send test signals,
//  which TelemetryDeck keeps apart from real ones. Keep docs/index.html (the privacy policy)
//  in step with what's sent here.
//
//  Signals:
//    TelemetryDeck.Session.started   sent by the SDK on launch and on returning to the app
//    Feature.opened                  feature: the screen's name ("Compose", "Tuner", …)
//    DailyPractice.started           stepsPlanned
//    DailyPractice.ended             stepsPlanned, stepsCompleted, minutes, finishedAll
//

import Foundation
import TelemetryDeck

enum Analytics {

    /// The app's TelemetryDeck App ID ("Guitar Man"; not a secret: it only lets the app send
    /// signals). Empty turns analytics off.
    private static let appID = "003DCE31-5584-4763-BF27-4FF171F6EAC9"

    private static var isEnabled = false

    /// Call once at launch.
    static func start() {
        guard !appID.isEmpty, !isEnabled else { return }
        TelemetryDeck.initialize(config: TelemetryDeck.Config(appID: appID))
        isEnabled = true
    }

    static func featureOpened(_ name: String) {
        send("Feature.opened", ["feature": name])
    }

    static func dailyPracticeStarted(stepsPlanned: Int) {
        send("DailyPractice.started", ["stepsPlanned": String(stepsPlanned)])
    }

    static func dailyPracticeEnded(stepsPlanned: Int, stepsCompleted: Int, minutes: Int) {
        send("DailyPractice.ended", [
            "stepsPlanned": String(stepsPlanned),
            "stepsCompleted": String(stepsCompleted),
            "minutes": String(minutes),
            "finishedAll": String(stepsCompleted >= stepsPlanned),
        ])
    }

    private static func send(_ name: String, _ parameters: [String: String] = [:]) {
        guard isEnabled else { return }
        TelemetryDeck.signal(name, parameters: parameters)
    }
}
