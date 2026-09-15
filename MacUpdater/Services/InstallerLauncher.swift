import AppKit
import Foundation
import MacUpdaterCore

/// Opens `Install macOS *.app` bundles, with the checks that make a failure explainable.
///
/// An interrupted `softwareupdate` leaves a real-looking but unusable bundle behind, and
/// macOS reports that as a terse "the application is damaged" only after the user has
/// clicked Open. Checking first means the app can say what is actually wrong.
@MainActor
enum InstallerLauncher {
    /// Returns nil when the installer opened, or an alert explaining why it didn't.
    static func launch(bundleURL: URL) async -> InstallerAlert? {
        let inspected = await Task.detached(priority: .userInitiated) {
            InstallerBundleInspector.inspect(bundleURL: bundleURL)
        }.value

        guard let installer = inspected else {
            logError("Installer unreadable at \(bundleURL.path)", category: "InstallerLauncher")
            return InstallerAlert(
                title: "That installer is no longer there",
                message: "Nothing readable was found at \(bundleURL.path). It may have been moved or deleted."
            )
        }

        if let issue = installer.issueDescription {
            logError("Refused to launch incomplete installer: \(issue)", category: "InstallerLauncher")
            return InstallerAlert(
                title: "\(installer.displayName) can't run",
                message: issue,
                revealURL: installer.bundleURL
            )
        }

        logInfo("Launching \(installer.displayName) at \(installer.bundleURL.path)", category: "InstallerLauncher")

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false

        do {
            _ = try await NSWorkspace.shared.openApplication(
                at: installer.bundleURL,
                configuration: configuration
            )
            logInfo("\(installer.displayName) launched", category: "InstallerLauncher")
            return nil
        } catch {
            let nsError = error as NSError
            let details = [error.localizedDescription, nsError.localizedFailureReason]
                .compactMap { $0 }
                .joined(separator: " ")
            logError("Launch failed (\(nsError.domain) \(nsError.code)): \(details)", category: "InstallerLauncher")
            return InstallerAlert(
                title: "Couldn't open \(installer.displayName)",
                message: details
                    + " Try opening it from Finder — if macOS says the installer is damaged, delete it and download it again.",
                revealURL: installer.bundleURL
            )
        }
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
