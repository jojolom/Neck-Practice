//
//  PracticeRemindersView.swift
//  Neck Practice
//
//  Manage daily-practice reminder times. Walks the user through OS-level
//  notification permission the first time they enable it.
//

import SwiftUI
import UserNotifications

struct PracticeRemindersView: View {

    @Bindable var store: PracticeRemindersStore
    @Environment(\.dismiss) private var dismiss

    @State private var authStatus: UNAuthorizationStatus = .notDetermined
    @State private var showingIntro = false
    @State private var editingReminderID: PracticeReminder.ID? = nil
    @State private var showingAddPicker = false

    /// Hour/minute draft used by the add/edit time picker.
    @State private var draftHour: Int = 19
    @State private var draftMinute: Int = 0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: masterBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Daily Reminders")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            Text(masterSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if shouldShowDeniedHelp {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Notifications Disabled", systemImage: "bell.slash.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.red)
                            Text("Reminders need notification permission. Enable it in Settings.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                openSettings()
                            } label: {
                                Text("Open Settings")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    if store.reminders.isEmpty {
                        Text("No reminders yet. Add one below.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.reminders) { reminder in
                            reminderRow(reminder)
                        }
                        .onDelete { indices in
                            for idx in indices {
                                store.deleteReminder(store.reminders[idx].id)
                            }
                        }
                    }

                    Button {
                        prepareAddReminder()
                    } label: {
                        Label("Add Reminder", systemImage: "plus.circle.fill")
                    }
                    .disabled(authStatus == .denied)
                } header: {
                    Text("Times")
                } footer: {
                    Text("Each enabled time will send one daily notification. Tap a time to edit. Swipe to delete.")
                }
            }
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showingIntro) {
                introSheet
            }
            .sheet(isPresented: addOrEditPresented) {
                timePickerSheet
            }
            .task {
                await NotificationService.shared.refreshAuthStatus()
                authStatus = NotificationService.shared.authStatus
            }
        }
    }

    // MARK: - Master toggle binding

    /// Wraps `store.remindersEnabled` so that flipping it on triggers the
    /// permission flow / seeds a default reminder.
    private var masterBinding: Binding<Bool> {
        Binding(
            get: { store.remindersEnabled },
            set: { newValue in
                if newValue {
                    handleEnableTapped()
                } else {
                    store.remindersEnabled = false
                }
            }
        )
    }

    private var masterSubtitle: String {
        switch authStatus {
        case .denied:        return "Notifications denied — enable in Settings"
        case .notDetermined: return "We'll ask permission before scheduling"
        default:
            if !store.remindersEnabled { return "Off — no reminders will fire" }
            let count = store.reminders.filter(\.enabled).count
            return count == 0 ? "On — add a time to get reminders"
                              : "\(count) reminder\(count == 1 ? "" : "s") scheduled"
        }
    }

    private var shouldShowDeniedHelp: Bool { authStatus == .denied }

    private func handleEnableTapped() {
        switch authStatus {
        case .notDetermined:
            showingIntro = true
        case .denied:
            // Master flip to "on" is a no-op when denied; the inline help points to Settings.
            store.remindersEnabled = false
        default:
            store.remindersEnabled = true
            store.ensureDefaultReminder()
        }
    }

    // MARK: - Intro sheet (before iOS prompt)

    private var introSheet: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.orange)
            VStack(spacing: 8) {
                Text("Daily Practice Reminders")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("We'll send a quick reminder at the times you choose. No spam, just a nudge to keep your streak alive.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)
            }
            Spacer()
            VStack(spacing: 12) {
                Button {
                    Task { await requestPermissionFromIntro() }
                } label: {
                    Text("Enable Reminders")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button {
                    showingIntro = false
                } label: {
                    Text("Not Now")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 30)
        }
        .presentationDetents([.medium])
    }

    private func requestPermissionFromIntro() async {
        let granted = await NotificationService.shared.requestAuthorization()
        authStatus = NotificationService.shared.authStatus
        showingIntro = false
        if granted {
            store.remindersEnabled = true
            store.ensureDefaultReminder()
        }
    }

    // MARK: - Time picker sheet (add / edit)

    private var addOrEditPresented: Binding<Bool> {
        Binding(
            get: { showingAddPicker || editingReminderID != nil },
            set: { newValue in
                if !newValue {
                    showingAddPicker = false
                    editingReminderID = nil
                }
            }
        )
    }

    private var timePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker(
                    "Time",
                    selection: timePickerBinding,
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle(editingReminderID == nil ? "New Reminder" : "Edit Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { addOrEditPresented.wrappedValue = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveDraft() }
                        .fontWeight(.semibold)
                }
            }
            .presentationDetents([.medium])
        }
    }

    private var timePickerBinding: Binding<Date> {
        Binding(
            get: {
                var c = DateComponents()
                c.hour = draftHour
                c.minute = draftMinute
                return Calendar.current.date(from: c) ?? .now
            },
            set: { newDate in
                let c = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                draftHour = c.hour ?? 19
                draftMinute = c.minute ?? 0
            }
        )
    }

    private func prepareAddReminder() {
        if authStatus == .notDetermined {
            showingIntro = true
            return
        }
        draftHour = 19
        draftMinute = 0
        showingAddPicker = true
    }

    private func saveDraft() {
        if let editingID = editingReminderID,
           var existing = store.reminders.first(where: { $0.id == editingID }) {
            existing.hour = draftHour
            existing.minute = draftMinute
            store.updateReminder(existing)
        } else {
            store.addReminder(hour: draftHour, minute: draftMinute)
        }
        addOrEditPresented.wrappedValue = false
    }

    // MARK: - Rows

    private func reminderRow(_ reminder: PracticeReminder) -> some View {
        HStack(spacing: 12) {
            Button {
                store.toggle(reminder.id)
            } label: {
                Image(systemName: reminder.enabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(reminder.enabled ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)

            Button {
                draftHour = reminder.hour
                draftMinute = reminder.minute
                editingReminderID = reminder.id
            } label: {
                HStack {
                    Text(reminder.displayTime)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(reminder.enabled ? .primary : .secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    PracticeRemindersView(store: PracticeRemindersStore())
}
