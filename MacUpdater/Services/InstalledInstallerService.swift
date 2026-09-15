import Foundation
import MacUpdaterCore

actor InstalledInstallerService {
    func scanInstalledInstallers() throws -> [InstalledInstaller] {
        try InstallerBundleInspector.installedInstallers()
    }

    /// Re-reads a single bundle from disk. Used right before launching, so a bundle that
    /// was deleted or half-written since the last scan is caught rather than handed to
    /// LaunchServices.
    func inspect(bundleURL: URL) -> InstalledInstaller? {
        InstallerBundleInspector.inspect(bundleURL: bundleURL)
    }

    func findInstaller(version: String) -> InstalledInstaller? {
        InstallerBundleInspector.find(version: version)
    }
}
