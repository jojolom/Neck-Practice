//
//  BlockAppsView.swift
//  Neck Practice
//
//  Settings for "Block apps until I practice": turn it on (Screen Time permission), choose the
//  apps to cover, and see how the shield and its 15-minute unlock work.
//

import FamilyControls
import SwiftData
import SwiftUI

struct BlockAppsView: View {

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PracticeSessionLog.completedAt, order: .reverse)
    private var logs: [PracticeSessionLog]

    @Bindable private var blocker = ScreenTimeBlocker.shared
    @State private var showPicker = false
    @State private var working = false
    @State private var message: String?

    private var appName: String { ScreenTimeShared.appName }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: enabledBinding) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Block apps until I practice")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(working)
                } footer: {
                    if let message {
                        Text(message).foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        showPicker = true
                    } label: {
                        HStack {
                            Label("Choose apps", systemImage: "square.grid.2x2")
                            Spacer()
                            Text(blocker.selectedCount == 0 ? "None" : "\(blocker.selectedCount) selected")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!blocker.isAuthorized)
                } header: {
                    Text("Apps to cover")
                } footer: {
                    Text(blocker.isAuthorized
                         ? "Pick the apps, categories, or sites that get in the way of practice."
                         : "Turn blocking on first to allow Screen Time access.")
                }

                Section("How it works") {
                    explainRow("sunrise", "Each morning at midnight your chosen apps are covered by a “Practice first” screen.")
                    explainRow("checkmark.circle", "Finish a \(appName) session and they unlock for the rest of the day.")
                    explainRow("clock.arrow.circlepath", "Need an app anyway? The cover has an “Unlock for \(ScreenTimeShared.unlockMinutes) min” button — \(ScreenTimeShared.maxUnlocksPerDay) times a day, so you're never locked out.")
                    explainRow("bell", "“Open \(appName)” on the cover sends you a notification to tap, since iOS doesn't let covers open apps directly.")
                }
            }
            .navigationTitle("Block Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(isPresented: $showPicker) {
                NavigationStack {
                    FamilyActivityPicker(selection: $blocker.selection)
                        .navigationTitle("Choose Apps")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showPicker = false }
                                    .fontWeight(.semibold)
                            }
                        }
                }
            }
            .task { blocker.refreshAuthorization() }
        }
    }

    // MARK: - Pieces

    private var subtitle: String {
        if blocker.authorizationStatus == .denied { return "Screen Time access was denied" }
        if !blocker.isEnabled { return "Off" }
        let left = blocker.unlocksLeftToday
        return blocker.selectedCount == 0
            ? "On — choose apps to cover"
            : "On · \(left) unlock\(left == 1 ? "" : "s") left today"
    }

    private func explainRow(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { blocker.isEnabled },
            set: { newValue in
                if newValue {
                    Task { await turnOn() }
                } else {
                    message = nil
                    blocker.disable()
                }
            }
        )
    }

    private func turnOn() async {
        working = true
        defer { working = false }
        message = nil

        guard await blocker.requestAuthorization() else {
            message = blocker.authorizationStatus == .denied
                ? "Screen Time access was denied. You can allow it in Settings → Screen Time."
                : "Couldn't get Screen Time access. Try again on your iPhone."
            return
        }

        // The cover's "Open" button works through a notification, so make sure those are allowed.
        await NotificationService.shared.refreshAuthStatus()
        if NotificationService.shared.authStatus == .notDetermined {
            _ = await NotificationService.shared.requestAuthorization()
        }

        blocker.enable(practicedToday: PracticeHistory.didPracticeToday(logs))
        if blocker.selectedCount == 0 { showPicker = true }
    }
}

#Preview {
    BlockAppsView()
        .modelContainer(for: PracticeSessionLog.self, inMemory: true)
}
