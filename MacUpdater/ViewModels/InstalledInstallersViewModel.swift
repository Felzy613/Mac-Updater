import Foundation
import Combine
import AppKit
import MacUpdaterCore

/// A problem worth interrupting the user for, with an optional "show me" escape hatch.
struct InstallerAlert: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let message: String
    var revealURL: URL?
}

@MainActor
final class InstalledInstallersViewModel: ObservableObject {
    @Published private(set) var installers: [InstalledInstaller] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var diskSpace: DiskSpace?
    @Published var alert: InstallerAlert?

    private let installedService: InstalledInstallerService

    init(installedService: InstalledInstallerService) {
        self.installedService = installedService
    }

    var hasLowSpaceForInstall: Bool {
        guard let diskSpace else { return false }
        return diskSpace.availableCapacity < InstallerBundleInfo.recommendedFreeSpaceForInstall
    }

    func refresh() {
        isLoading = true
        error = nil
        Task {
            do {
                let found = try await installedService.scanInstalledInstallers()
                installers = found.sorted { $0.versionNumber > $1.versionNumber }
                diskSpace = DiskSpace.current()
                let incomplete = found.filter { !$0.isComplete }
                logInfo("Found \(found.count) installed installer(s), \(incomplete.count) incomplete",
                        category: "InstalledInstallers")
            } catch {
                self.error = error.localizedDescription
                logError("Scan failed: \(error.localizedDescription)", category: "InstalledInstallers")
            }
            isLoading = false
        }
    }

    func launch(_ installer: InstalledInstaller) {
        Task {
            if let alert = await InstallerLauncher.launch(bundleURL: installer.bundleURL) {
                self.alert = alert
                refresh()
            }
        }
    }

    func revealInFinder(_ url: URL) {
        InstallerLauncher.reveal(url)
    }
}
