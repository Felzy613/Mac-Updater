import Foundation
import AppKit

@MainActor
final class InstalledInstallersViewModel: ObservableObject {
    @Published private(set) var installers: [InstalledInstaller] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private let installedService: InstalledInstallerService

    init(installedService: InstalledInstallerService) {
        self.installedService = installedService
    }

    func refresh() {
        isLoading = true
        error = nil
        Task {
            do {
                let found = try await installedService.scanInstalledInstallers()
                installers = found.sorted { $0.versionNumber > $1.versionNumber }
                logInfo("Found \(found.count) installed installer(s)", category: "InstalledInstallers")
            } catch {
                self.error = error.localizedDescription
                logError("Scan failed: \(error.localizedDescription)", category: "InstalledInstallers")
            }
            isLoading = false
        }
    }

    func launch(_ installer: InstalledInstaller) {
        logInfo("Launching \(installer.displayName)", category: "InstalledInstallers")
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: installer.bundleURL, configuration: config) { _, error in
            if let error {
                logError("Launch failed: \(error.localizedDescription)", category: "InstalledInstallers")
            }
        }
    }
}
