//
//  NotificationService.swift
//  Neck Practice
//
//  Wraps UNUserNotificationCenter for the Daily Practice reminder system.
//

import Foundation
import UserNotifications
import Observation

// MARK: - Constants

enum PracticeNotification {
    nonisolated static let categoryID = "PRACTICE_REMINDER"
    nonisolated static let startNowActionID = "START_NOW"
}

// MARK: - NotificationService

@Observable
final class NotificationService {

    static let shared = NotificationService()

    /// Cached authorization status, refreshed via `refreshAuthStatus()`.
    private(set) var authStatus: UNAuthorizationStatus = .notDetermined

    /// Practice state from the last `refreshSchedule(logs:)`, so changes made in the reminders
    /// screen can re-plan without access to the logs.
    private var snapshot: (streak: Int, practicedToday: Bool)?
    /// The in-flight reschedule; a newer refresh cancels it so they never interleave.
    private var scheduleTask: Task<Void, Never>?

    private init() {}

    // MARK: - Setup

    /// Registers the practice-reminder category with its quick-action button.
    /// Call once at app launch.
    func registerCategory() {
        let startNow = UNNotificationAction(
            identifier: PracticeNotification.startNowActionID,
            title: "Start Now",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: PracticeNotification.categoryID,
            actions: [startNow],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Authorization

    /// Pulls the current OS-level auth status into `authStatus`.
    @MainActor
    func refreshAuthStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authStatus = settings.authorizationStatus
    }

    /// Triggers the iOS permission prompt if not yet determined. Returns
    /// `true` if reminders are now allowed.
    @MainActor
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthStatus()
            return granted
        } catch {
            await refreshAuthStatus()
            return false
        }
    }

    // MARK: - Scheduling

    /// Recomputes the next 7 days of reminders from the user's reminder times and practice
    /// history (see `ReminderPlanner`): skips today if you already practiced, mentions the
    /// streak when it's on the line, and adds a 9 PM streak saver. Replaces everything pending.
    ///
    /// Call at launch, when the app backgrounds, and right after a session is logged.
    /// Never prompts for permission — that happens when the user turns reminders on.
    func refreshSchedule(logs: [PracticeSessionLog]) {
        snapshot = (
            streak: PracticeHistory.currentStreak(from: logs),
            practicedToday: PracticeHistory.didPracticeToday(logs)
        )
        applySchedule()
    }

    /// Re-plans using the practice state from the last `refreshSchedule(logs:)`.
    func refreshScheduleFromSnapshot() {
        applySchedule()
    }

    private func applySchedule() {
        let center = UNUserNotificationCenter.current()
        let saved = PracticeRemindersStore.loadPersisted()

        guard saved.enabled else {
            center.removeAllPendingNotificationRequests()
            return
        }

        let state = snapshot ?? (streak: 0, practicedToday: false)
        let plan = ReminderPlanner.plan(
            reminders: saved.reminders,
            practicedToday: state.practicedToday,
            streak: state.streak,
            now: .now
        )

        scheduleTask?.cancel()
        scheduleTask = Task {
            let settings = await center.notificationSettings()
            let allowed: Bool
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: allowed = true
            default: allowed = false
            }

            guard !Task.isCancelled else { return }
            center.removeAllPendingNotificationRequests()
            guard allowed else { return }

            for item in plan {
                guard !Task.isCancelled else { return }
                let content = UNMutableNotificationContent()
                content.title = item.title
                content.body = item.body
                content.sound = .default
                content.categoryIdentifier = PracticeNotification.categoryID

                let components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: item.fireDate
                )
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try? await center.add(UNNotificationRequest(
                    identifier: item.identifier, content: content, trigger: trigger
                ))
            }

            #if DEBUG
            NSLog("NotificationService: scheduled %d reminders (streak %d, practiced today: %@)",
                  plan.count, state.streak, state.practicedToday ? "yes" : "no")
            for item in plan { NSLog("  %@ [%@] %@", "\(item.fireDate)", "\(item.kind)", item.title) }
            NSLog("NotificationService: %d pending", await center.pendingNotificationRequests().count)
            #endif
        }
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
