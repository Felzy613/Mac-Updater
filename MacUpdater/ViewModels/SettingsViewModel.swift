import Foundation
import Combine
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @AppStorage("autoRefresh") var autoRefresh: Bool = true
    @AppStorage("refreshInterval") var refreshInterval: Double = 3600
    @AppStorage("showDowngrades") var showDowngrades: Bool = false
    @AppStorage("enableBeta") var enableBeta: Bool = false
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = true
    @AppStorage("logRetentionDays") var logRetentionDays: Int = 7

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
