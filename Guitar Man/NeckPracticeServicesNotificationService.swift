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
    static let categoryID = "PRACTICE_REMINDER"
    static let startNowActionID = "START_NOW"
    static let title = "Time to practice"
    static let body = "Don't break your streak — tap to start."
}

// MARK: - NotificationService

@Observable
final class NotificationService {

    static let shared = NotificationService()

    /// Cached authorization status, refreshed via `refreshAuthStatus()`.
    private(set) var authStatus: UNAuthorizationStatus = .notDetermined

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

    /// Cancels all pending practice reminders and re-schedules the given list.
    /// Each enabled reminder becomes one repeating calendar trigger that fires
    /// daily at the chosen `hour`/`minute`.
    func scheduleReminders(_ reminders: [PracticeReminder]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        for reminder in reminders where reminder.enabled {
            var components = DateComponents()
            components.hour = reminder.hour
            components.minute = reminder.minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

            let content = UNMutableNotificationContent()
            content.title = PracticeNotification.title
            content.body = PracticeNotification.body
            content.sound = .default
            content.categoryIdentifier = PracticeNotification.categoryID

            let request = UNNotificationRequest(
                identifier: reminder.id.uuidString,
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
