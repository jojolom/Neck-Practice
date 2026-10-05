//
//  ScreenTime.swift
//  Neck Practice
//
//  App side of "block apps until you've practiced": Screen Time authorization, the chosen
//  apps, the daily schedule, and clearing the shield once you practice. The shield itself is
//  drawn and handled by the extensions; shared state lives in ScreenTimeShared (App Group).
//

import DeviceActivity
import FamilyControls
import Foundation
import Observation

@Observable
final class ScreenTimeBlocker {

    static let shared = ScreenTimeBlocker()

    private(set) var authorizationStatus: AuthorizationStatus
    private(set) var isEnabled: Bool

    /// The apps, categories, and sites to cover. Edited by `FamilyActivityPicker`.
    var selection: FamilyActivitySelection {
        didSet {
            ScreenTimeShared.selection = selection
            if isEnabled { ScreenTimeShared.applyShield() }
        }
    }

    var selectedCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    var isAuthorized: Bool { authorizationStatus == .approved }
    var unlocksLeftToday: Int { ScreenTimeShared.unlocksLeftToday }

    private init() {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
        isEnabled = ScreenTimeShared.isBlockingEnabled
        selection = ScreenTimeShared.selection
    }

    // MARK: - Authorization

    func refreshAuthorization() {
        authorizationStatus = AuthorizationCenter.shared.authorizationStatus
    }

    /// Asks for Screen Time access (the system shows its own prompt). True if approved.
    func requestAuthorization() async -> Bool {
        if authorizationStatus != .approved {
            do {
                try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            } catch {
                #if DEBUG
                NSLog("ScreenTimeBlocker: authorization failed: %@", "\(error)")
                #endif
            }
            refreshAuthorization()
        }
        return isAuthorized
    }

    // MARK: - Turning blocking on and off

    /// Starts blocking (needs Screen Time access). Covers the chosen apps right away unless you
    /// already practiced today; from then on the monitor extension re-covers them every midnight.
    @discardableResult
    func enable(practicedToday: Bool) -> Bool {
        guard isAuthorized else { return false }
        ScreenTimeShared.isBlockingEnabled = true
        isEnabled = true
        // Record today's practice first: the monitor's first callback can arrive right away and
        // covers the apps unless it sees you've practiced.
        if practicedToday { ScreenTimeShared.markPracticedToday() }
        startDailyMonitoring()
        reconcile(practicedToday: practicedToday)
        return true
    }

    func disable() {
        ScreenTimeShared.isBlockingEnabled = false
        isEnabled = false
        DeviceActivityCenter().stopMonitoring()
        ScreenTimeShared.endUnlock()
        ScreenTimeShared.clearShield()
    }

    // MARK: - Keeping the shield in step with practice

    /// Call at launch, when the app becomes active, and after a session is logged. Practiced today
    /// lifts the shield for the rest of the day; otherwise it's (re)applied if blocking is on.
    func reconcile(practicedToday: Bool) {
        if practicedToday {
            ScreenTimeShared.markPracticedToday()
            if isEnabled {
                ScreenTimeShared.endUnlock()
                ScreenTimeShared.clearShield()
            }
        } else if isEnabled {
            if !DeviceActivityCenter().activities.contains(ScreenTimeShared.dailyActivity) {
                startDailyMonitoring()
            }
            ScreenTimeShared.applyShield()
        }
    }

    private func startDailyMonitoring() {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        do {
            try DeviceActivityCenter().startMonitoring(ScreenTimeShared.dailyActivity, during: schedule)
        } catch {
            #if DEBUG
            NSLog("ScreenTimeBlocker: couldn't start daily monitoring: %@", "\(error)")
            #endif
        }
    }
}
