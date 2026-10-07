//
//  NeckPracticeApp.swift
//  Neck Practice
//
//  Created by Joe Lombardi on 2/16/26.
//

import SwiftUI
import SwiftData
import UserNotifications

// MARK: - AppDelegate

/// Sets up notification handling: registers the Start Now action, shows reminders as banners
/// while the app is open, and routes taps (and Start Now) to Daily Practice.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        NotificationService.shared.registerCategory()
        center.setBadgeCount(0)
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        guard action == UNNotificationDefaultActionIdentifier
                || action == PracticeNotification.startNowActionID else { return }
        await MainActor.run { DeepLinkRouter.shared.openDailyPractice() }
    }
}

// MARK: - App

@main
struct NeckPracticeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var audioSettings = AudioSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(audioSettings)
                .onAppear {
                    UIApplication.shared.isIdleTimerDisabled = true
                    // Decode the guitar recordings in the background, ready for the first note.
                    GuitarSampleBank.preload()
                }
                .onDisappear {
                    UIApplication.shared.isIdleTimerDisabled = false
                }
        }
        .modelContainer(for: [PracticeSessionLog.self, SavedLoop.self])
    }
}
