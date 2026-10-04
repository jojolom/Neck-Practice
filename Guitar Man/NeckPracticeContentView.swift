//
//  ContentView.swift
//  Neck Practice
//
//  Created by Joe Lombardi on 2/16/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {

    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \PracticeSessionLog.completedAt, order: .reverse)
    private var logs: [PracticeSessionLog]

    var body: some View {
        HomeView()
            // Keep the next 7 days of reminders in step with today's practice: at launch,
            // whenever the app becomes active or goes to the background, and when logs change.
            .task { refreshPracticeState() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active || phase == .background {
                    refreshPracticeState()
                }
            }
            .onChange(of: logs.count) {
                refreshPracticeState()
            }
    }

    /// Reminders and the app-blocking shield both depend on whether you've practiced today.
    private func refreshPracticeState() {
        NotificationService.shared.refreshSchedule(logs: logs)
        ScreenTimeBlocker.shared.reconcile(practicedToday: PracticeHistory.didPracticeToday(logs))
    }
}

#Preview {
    ContentView()
        .modelContainer(for: PracticeSessionLog.self, inMemory: true)
}
