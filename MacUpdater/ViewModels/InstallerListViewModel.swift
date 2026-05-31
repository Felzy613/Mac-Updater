import Foundation
import Combine

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
    private var systemInfo: SystemInfo?
    private var refreshTimer: AnyCancellable?
    private var settingsCancellable: AnyCancellable?

    init(discoveryService: InstallerDiscoveryService, systemInfoService: SystemInfoService) {
        self.discoveryService = discoveryService
        self.systemInfoService = systemInfoService
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
                let currentVersion = si.versionNumber
                let tagged = raw.map { installer -> MacOSInstaller in
                    var i = installer
                    i.isDowngrade = i.versionNumber <= currentVersion
                    return i
                }
                .sorted { $0.versionNumber > $1.versionNumber }

                installers = tagged
                lastRefreshed = Date()
                applyFilter()
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

    private func applyFilter() {
        if showDowngrades {
            filteredInstallers = installers
        } else {
            filteredInstallers = installers.filter { !$0.isDowngrade }
        }
    }
}
