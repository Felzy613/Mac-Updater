import AppKit
import MacUpdaterCore

@MainActor
final class HelperAppDelegate: NSObject, NSApplicationDelegate {
    private let shell = ShellService()
    private lazy var systemInfoService = SystemInfoService(shell: shell)
    private lazy var discoveryService = InstallerDiscoveryService(shell: shell)
    private let notificationService = NotificationService()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        logInfo("Helper launched", category: "Helper")

        Task {
            await notificationService.requestAuthorization()
            while !Task.isCancelled {
                await checkOnce()
                let interval = SharedState.loadSettings().refreshIntervalSeconds
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private func checkOnce() async {
        guard SharedState.loadSettings().notificationsEnabled else {
            logInfo("Notifications disabled, skipping check", category: "Helper")
            return
        }
        do {
            async let info = systemInfoService.detect()
            async let discovered = discoveryService.fetchInstallers()
            let (systemInfo, raw) = try await (info, discovered)

            let known = Set(SharedState.loadKnownUpgrades().notifiedVersions)
            let (tagged, newlyAvailable) = diffNewUpgrades(
                installers: raw, currentVersion: systemInfo.versionNumber, knownVersions: known
            )

            if let newest = newlyAvailable.max(by: { $0.versionNumber < $1.versionNumber }) {
                notificationService.sendUpdateAvailable(title: newest.title, version: newest.version)
            }
            let allUpgradeVersions = tagged.filter { !$0.isDowngrade }.map(\.version)
            SharedState.saveKnownUpgrades(KnownUpgrades(notifiedVersions: allUpgradeVersions))
            logInfo("Check complete: \(raw.count) installers, \(newlyAvailable.count) new", category: "Helper")
        } catch {
            logError("Check failed: \(error.localizedDescription)", category: "Helper")
        }
    }
}

@main
enum HelperMain {
    @MainActor
    static func main() {
        let delegate = HelperAppDelegate()
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}
