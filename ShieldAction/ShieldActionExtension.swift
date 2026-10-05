//
//  ShieldActionExtension.swift
//  ShieldAction
//
//  What the shield's buttons do. A shield can't open another app, so "Open" posts a notification
//  the user can tap. "Unlock" lifts the shield for 15 minutes, up to twice a day, so the app is
//  never a trap.
//

import ManagedSettings
import UserNotifications

class ShieldActionExtension: ShieldActionDelegate {

    override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler: completionHandler)
    }

    override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        respond(to: action, completionHandler: completionHandler)
    }

    private func respond(to action: ShieldAction, completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            postOpenAppNotification { completionHandler(.close) }
        case .secondaryButtonPressed:
            // The shield comes off by itself once the store is cleared.
            completionHandler(ScreenTimeShared.beginUnlock() ? .none : .close)
        default:
            // Submenu items (iOS 26.4+) aren't configured on our shield.
            completionHandler(.close)
        }
    }

    private func postOpenAppNotification(then done: @escaping () -> Void) {
        let content = UNMutableNotificationContent()
        content.title = "Time to practice 🎸"
        content.body = "Tap to open \(ScreenTimeShared.appName) and unlock your apps."
        content.sound = .default
        content.categoryIdentifier = "PRACTICE_REMINDER"   // same category the app registers (Start Now)

        let request = UNNotificationRequest(
            identifier: "shield-open-app",
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        UNUserNotificationCenter.current().add(request) { _ in done() }
    }
}
