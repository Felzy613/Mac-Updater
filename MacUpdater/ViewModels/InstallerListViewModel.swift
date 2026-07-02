import Foundation
import Combine
import MacUpdaterCore

@MainActor
final class InstallerListViewModel: ObservableObject {
    @Published private(set) var installers: [MacOSInstaller] = []
    @Published private(set) var filteredInstallers: [MacOSInstaller] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastRefreshed: Date?
    @Published private(set) var error: String?
    @Published var showDowngrades = false {
        didSet { applyFilter() }
    }

    var upgradeCount: Int { filteredInstallers.filter { !$0.isDowngrade }.count }

    private let discoveryService: InstallerDiscoveryService
    private let systemInfoService: SystemInfoService
    private let notificationService: NotificationService
    private var systemInfo: SystemInfo?
    private var refreshTimer: AnyCancellable?
    private var settingsCancellable: AnyCancellable?

    init(
        discoveryService: InstallerDiscoveryService,
        systemInfoService: SystemInfoService,
        notificationService: NotificationService
    ) {
        self.discoveryService = discoveryService
        self.systemInfoService = systemInfoService
        self.notificationService = notificationService
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        logInfo("Fetching installer list...", category: "InstallerList")
        Task {
            do {
                async let info = systemInfoService.detect()
                async let discovered = discoveryService.fetchInstallers()
                let (si, raw) = try await (info, discovered)

                systemInfo = si
                let known = Set(SharedState.loadKnownUpgrades().notifiedVersions)
                let (tagged, newlyAvailable) = diffNewUpgrades(
                    installers: raw, currentVersion: si.versionNumber, knownVersions: known
                )

                installers = tagged.sorted { $0.versionNumber > $1.versionNumber }
                lastRefreshed = Date()
                applyFilter()
                notify(newlyAvailable: newlyAvailable, allUpgradeVersions: tagged.filter { !$0.isDowngrade }.map(\.version))
                logInfo("Found \(raw.count) installers (\(upgradeCount) upgrades)", category: "InstallerList")
            } catch {
                self.error = error.localizedDescription
                logError("Installer fetch failed: \(error.localizedDescription)", category: "InstallerList")
            }
            isLoading = false
        }
    }

    func startAutoRefresh(interval: Double) {
        refreshTimer?.cancel()
        refreshTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.refresh() }
    }

    func stopAutoRefresh() {
        refreshTimer?.cancel()
        refreshTimer = nil
    }

    private func notify(newlyAvailable: [MacOSInstaller], allUpgradeVersions: [String]) {
        if let newest = newlyAvailable.max(by: { $0.versionNumber < $1.versionNumber }) {
            notificationService.sendUpdateAvailable(title: newest.title, version: newest.version)
        }
        SharedState.saveKnownUpgrades(KnownUpgrades(notifiedVersions: allUpgradeVersions))
    }

    private func applyFilter() {
        if showDowngrades {
            filteredInstallers = installers
        } else {
            filteredInstallers = installers.filter { !$0.isDowngrade }
        }
    }
}
