import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published private(set) var systemInfo: SystemInfo?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var installedCount = 0

    private let systemInfoService: SystemInfoService
    private let installedService: InstalledInstallerService

    init(systemInfoService: SystemInfoService, installedService: InstalledInstallerService) {
        self.systemInfoService = systemInfoService
        self.installedService = installedService
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        Task {
            do {
                async let info = systemInfoService.detect()
                async let count = { try installedService.scanInstalledInstallers().count }()
                let (si, ic) = try await (info, count)
                systemInfo = si
                installedCount = ic
                logInfo("System info: \(si.productVersion) (\(si.buildVersion)) \(si.architecture)", category: "Dashboard")
            } catch {
                self.error = error.localizedDescription
                logError("Dashboard refresh failed: \(error.localizedDescription)", category: "Dashboard")
            }
            isLoading = false
        }
    }
}
