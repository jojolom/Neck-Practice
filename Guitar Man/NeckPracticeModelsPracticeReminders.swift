//
//  PracticeReminders.swift
//  Neck Practice
//
//  Data model + observable store for the user's daily practice reminders.
//  Persists to UserDefaults; pushes any change down to NotificationService
//  so the OS-scheduled notifications stay in sync.
//

import Foundation
import Observation

// MARK: - PracticeReminder

struct PracticeReminder: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    /// 0–23.
    var hour: Int
    /// 0–59.
    var minute: Int
    var enabled: Bool = true

    /// Formatted local time string for display (e.g. "7:00 PM").
    var displayTime: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let date = Calendar.current.date(from: components) ?? .now
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - PracticeRemindersStore

@Observable
final class PracticeRemindersStore {

    private(set) var reminders: [PracticeReminder]
    var remindersEnabled: Bool {
        didSet { persist(); reschedule() }
    }

    private static let listKey = "practiceReminders.v1"
    private static let enabledKey = "practiceReminders.v1.enabled"
    private static let defaultReminder = PracticeReminder(hour: 19, minute: 0)

    init() {
        let loaded: [PracticeReminder] = {
            guard
                let data = UserDefaults.standard.data(forKey: Self.listKey),
                let decoded = try? JSONDecoder().decode([PracticeReminder].self, from: data)
            else { return [] }
            return decoded
        }()
        self.reminders = loaded
        self.remindersEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
    }

    // MARK: - Mutations

    /// Adds a new reminder at the given time. If this is the first reminder,
    /// flips the master toggle on as well (the user opted in by adding it).
    @discardableResult
    func addReminder(hour: Int, minute: Int) -> PracticeReminder {
        let reminder = PracticeReminder(hour: hour, minute: minute, enabled: true)
        reminders.append(reminder)
        if reminders.count == 1 { remindersEnabled = true }
        sortInPlace()
        persist()
        reschedule()
        return reminder
    }

    /// Adds a default 7 PM reminder if the user has none. Used when the master
    /// toggle is flipped on from off without any existing reminders.
    func ensureDefaultReminder() {
        guard reminders.isEmpty else { return }
        reminders.append(Self.defaultReminder)
        persist()
        reschedule()
    }

    func updateReminder(_ updated: PracticeReminder) {
        guard let idx = reminders.firstIndex(where: { $0.id == updated.id }) else { return }
        reminders[idx] = updated
        sortInPlace()
        persist()
        reschedule()
    }

    func deleteReminder(_ id: UUID) {
        reminders.removeAll { $0.id == id }
        persist()
        reschedule()
    }

    func toggle(_ id: UUID) {
        guard let idx = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[idx].enabled.toggle()
        persist()
        reschedule()
    }

    // MARK: - Plumbing

    private func sortInPlace() {
        reminders.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(data, forKey: Self.listKey)
        }
        UserDefaults.standard.set(remindersEnabled, forKey: Self.enabledKey)
    }

    /// Push the current state to the OS. Cancels everything if reminders are
    /// disabled at the master level.
    func reschedule() {
        if remindersEnabled {
            NotificationService.shared.scheduleReminders(reminders)
        } else {
            NotificationService.shared.cancelAll()
        }
    }
}
