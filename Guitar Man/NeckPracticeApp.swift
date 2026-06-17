//
//  NeckPracticeApp.swift
//  Neck Practice
//
//  Created by Joe Lombardi on 2/16/26.
//

import SwiftUI
import SwiftData

@main
struct NeckPracticeApp: App {
    @State private var audioSettings = AudioSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(audioSettings)
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                }
                .onDisappear {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
        }
        .modelContainer(for: PracticeSessionLog.self)
    }
}
