//
//  ScreenTimeShared.swift
//  Neck Practice
//
//  "Block apps until you've practiced": state and shield logic shared by the app and its three
//  Screen Time extensions (DeviceActivityMonitor, ShieldConfiguration, ShieldAction). This file
//  is compiled into all four targets, so it must stay plain, nonisolated code. Everything lives
//  in the App Group so the processes agree on what's happening.
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

nonisolated enum ScreenTimeShared {

    // MARK: - Constants

    static let appGroupID = "group.test.Guitar-Man"
    /// Shown on the shield and in its notification.
    static let appName = "Neck Practice"
    static let maxUnlocksPerDay = 2
    static let unlockMinutes = 15

    /// Repeats every day from midnight; its start re-applies the shield.
    static let dailyActivity = DeviceActivityName("practice.daily")
    /// One-off schedule that re-applies the shield when an unlock runs out.
    static let unlockActivity = DeviceActivityName("practice.unlock")

    private static var store: ManagedSettingsStore { ManagedSettingsStore(named: .init("practice")) }

    private enum Key {
        static let enabled = "blocking.enabled"
        static let selection = "blocking.selection"
        static let lastPracticeDay = "blocking.lastPracticeDay"
        static let unlockDay = "blocking.unlockDay"
        static let unlocksUsed = "blocking.unlocksUsed"
        static let unlockUntil = "blocking.unlockUntil"
    }

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroupID) ?? .standard }

    // MARK: - Persisted state

    static var isBlockingEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    static var selection: FamilyActivitySelection {
        get {
            guard let data = defaults.data(forKey: Key.selection),
                  let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
            else { return FamilyActivitySelection() }
            return decoded
        }
        set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.selection)
        }
    }

    /// Local calendar day, e.g. "2026-10-04".
    static func dayStamp(_ date: Date = .now) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static var practicedToday: Bool {
        defaults.string(forKey: Key.lastPracticeDay) == dayStamp()
    }

    static func markPracticedToday() {
        defaults.set(dayStamp(), forKey: Key.lastPracticeDay)
    }

    static var unlocksUsedToday: Int {
        defaults.string(forKey: Key.unlockDay) == dayStamp() ? defaults.integer(forKey: Key.unlocksUsed) : 0
    }

    static var unlocksLeftToday: Int { max(0, maxUnlocksPerDay - unlocksUsedToday) }

    /// True while a 15-minute unlock is running.
    static var isUnlockActive: Bool {
        guard let until = defaults.object(forKey: Key.unlockUntil) as? Date else { return false }
        return until > .now
    }

    // MARK: - Shield

    /// Covers the chosen apps — unless blocking is off, you've practiced today, or an unlock is
    /// running. `ignoreUnlock` is for the moment an unlock ends, when its timestamp may still be
    /// a few milliseconds in the future.
    static func applyShield(ignoreUnlock: Bool = false) {
        guard isBlockingEnabled, !practicedToday, ignoreUnlock || !isUnlockActive else { return }

        let chosen = selection
        let store = store
        store.shield.applications = chosen.applicationTokens.isEmpty ? nil : chosen.applicationTokens
        store.shield.applicationCategories = chosen.categoryTokens.isEmpty ? nil : .specific(chosen.categoryTokens)
        store.shield.webDomains = chosen.webDomainTokens.isEmpty ? nil : chosen.webDomainTokens
    }

    static func clearShield() {
        store.clearAllSettings()
    }

    // MARK: - Unlock for 15 minutes

    /// Uses one of today's unlocks: lifts the shield and schedules it to return in
    /// `unlockMinutes`. Returns false when none are left.
    @discardableResult
    static func beginUnlock() -> Bool {
        guard unlocksLeftToday > 0 else { return false }

        let used = unlocksUsedToday + 1
        defaults.set(dayStamp(), forKey: Key.unlockDay)
        defaults.set(used, forKey: Key.unlocksUsed)

        let now = Date()
        let end = now.addingTimeInterval(TimeInterval(unlockMinutes * 60))
        defaults.set(end, forKey: Key.unlockUntil)
        clearShield()

        // DeviceActivity calls the monitor extension when this interval ends, which re-applies
        // the shield (if you still haven't practiced).
        let calendar = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents([.hour, .minute, .second], from: now),
            intervalEnd: calendar.dateComponents([.hour, .minute, .second], from: end),
            repeats: false
        )
        try? DeviceActivityCenter().startMonitoring(unlockActivity, during: schedule)
        return true
    }

    /// Cancels a running unlock (once you've practiced it no longer matters).
    static func endUnlock() {
        defaults.removeObject(forKey: Key.unlockUntil)
        DeviceActivityCenter().stopMonitoring([unlockActivity])
    }
}
