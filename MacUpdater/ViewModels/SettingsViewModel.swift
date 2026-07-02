import Foundation
import Combine
import SwiftUI
import ServiceManagement
import MacUpdaterCore

@MainActor
final class SettingsViewModel: ObservableObject {
    private let helperLoginItem = SMAppService.loginItem(identifier: "FelzyTech.MacUpdater.Helper")

    @AppStorage("autoRefresh") var autoRefresh: Bool = true
    @AppStorage("refreshInterval") var refreshInterval: Double = 43200 {
        didSet { writeThroughSharedSettings() }
    }
    @AppStorage("showDowngrades") var showDowngrades: Bool = false
    @AppStorage("enableBeta") var enableBeta: Bool = false
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = true {
        didSet { writeThroughSharedSettings() }
    }
    @AppStorage("logRetentionDays") var logRetentionDays: Int = 7

    @Published var launchAtLogin: Bool = false {
        didSet {
            guard launchAtLogin != (helperLoginItem.status == .enabled) else { return }
            do {
                if launchAtLogin {
                    try helperLoginItem.register()
                } else {
                    try helperLoginItem.unregister()
                }
                logInfo("Helper launch at login set to \(launchAtLogin)", category: "Settings")
            } catch {
                logError("Failed to update helper login item: \(error.localizedDescription)", category: "Settings")
                launchAtLogin = helperLoginItem.status == .enabled
            }
        }
    }

    init() {
        let shared = SharedState.loadSettings()
        refreshInterval = shared.refreshIntervalSeconds
        notificationsEnabled = shared.notificationsEnabled
        launchAtLogin = helperLoginItem.status == .enabled
    }

    private func writeThroughSharedSettings() {
        SharedState.saveSettings(SharedSettings(refreshIntervalSeconds: refreshInterval, notificationsEnabled: notificationsEnabled))
    }

    static let refreshIntervalOptions: [(label: String, seconds: Double)] = [
        ("15 minutes", 900),
        ("30 minutes", 1800),
        ("1 hour", 3600),
        ("6 hours", 21600),
        ("12 hours", 43200),
        ("24 hours", 86400),
    ]

    static let retentionOptions: [(label: String, days: Int)] = [
        ("1 day", 1),
        ("3 days", 3),
        ("7 days", 7),
        ("14 days", 14),
        ("30 days", 30),
    ]
}
