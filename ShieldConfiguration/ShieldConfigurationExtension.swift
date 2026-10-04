//
//  ShieldConfigurationExtension.swift
//  ShieldConfiguration
//
//  The "🎸 Practice first" screen shown over a blocked app.
//

import ManagedSettings
import ManagedSettingsUI
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {

    override func configuration(shielding application: Application) -> ShieldConfiguration {
        practiceShield()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        practiceShield()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        practiceShield()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        practiceShield()
    }

    private func practiceShield() -> ShieldConfiguration {
        let name = ScreenTimeShared.appName
        let unlocksLeft = ScreenTimeShared.unlocksLeftToday

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: nil,
            icon: UIImage(systemName: "guitars.fill"),
            title: .init(text: "🎸 Practice first", color: .label),
            subtitle: .init(text: "Finish today's \(name) session to unlock this app.", color: .secondaryLabel),
            primaryButtonLabel: .init(text: "Open \(name)", color: .white),
            primaryButtonBackgroundColor: .systemBlue,
            secondaryButtonLabel: unlocksLeft > 0
                ? .init(text: "Unlock for \(ScreenTimeShared.unlockMinutes) min (\(unlocksLeft) left today)", color: .systemBlue)
                : nil
        )
    }
}
