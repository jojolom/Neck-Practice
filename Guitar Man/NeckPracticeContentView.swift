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
            .task { NotificationService.shared.refreshSchedule(logs: logs) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active || phase == .background {
                    NotificationService.shared.refreshSchedule(logs: logs)
                }
            }
            .onChange(of: logs.count) {
                NotificationService.shared.refreshSchedule(logs: logs)
            }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: PracticeSessionLog.self, inMemory: true)
}
