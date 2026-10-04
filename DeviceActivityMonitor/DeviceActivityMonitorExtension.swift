//
//  DeviceActivityMonitorExtension.swift
//  DeviceActivityMonitor
//
//  Runs in the background when a monitored schedule starts or ends. Starts: a new day begins, so
//  cover the chosen apps again. Ends: a 15-minute unlock ran out, so cover them again.
//

import DeviceActivity

class DeviceActivityMonitorExtension: DeviceActivityMonitor {

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity == ScreenTimeShared.dailyActivity {
            ScreenTimeShared.applyShield()
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity == ScreenTimeShared.unlockActivity {
            ScreenTimeShared.applyShield(ignoreUnlock: true)
        }
    }
}
