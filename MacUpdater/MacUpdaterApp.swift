import SwiftUI
import MacUpdaterCore

@main
struct MacUpdaterApp: App {
    private let shellService: ShellService
    private let systemInfoService: SystemInfoService
    private let discoveryService: InstallerDiscoveryService
    private let downloadService: DownloadService
    private let installedService: InstalledInstallerService
    private let notificationService: NotificationService

    @StateObject private var settingsVM = SettingsViewModel()
    @StateObject private var dashboardVM: DashboardViewModel
    @StateObject private var installerListVM: InstallerListViewModel
    @StateObject private var downloadVM: DownloadManagerViewModel
    @StateObject private var installedVM: InstalledInstallersViewModel
    @StateObject private var logVM = LogViewerViewModel()

    init() {
        let shell = ShellService()
        let sysInfo = SystemInfoService(shell: shell)
        let discovery = InstallerDiscoveryService(shell: shell)
        let download = DownloadService()
        let installed = InstalledInstallerService()
        let notif = NotificationService()

        shellService = shell
        systemInfoService = sysInfo
        discoveryService = discovery
        downloadService = download
        installedService = installed
        notificationService = notif

        _dashboardVM = StateObject(wrappedValue:
            DashboardViewModel(systemInfoService: sysInfo, installedService: installed))
        _installerListVM = StateObject(wrappedValue:
            InstallerListViewModel(discoveryService: discovery, systemInfoService: sysInfo, notificationService: notif))
        _downloadVM = StateObject(wrappedValue:
            DownloadManagerViewModel(downloadService: download, notificationService: notif))
        _installedVM = StateObject(wrappedValue:
            InstalledInstallersViewModel(installedService: installed))
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            MainView()
                .environmentObject(settingsVM)
                .environmentObject(dashboardVM)
                .environmentObject(installerListVM)
                .environmentObject(downloadVM)
                .environmentObject(installedVM)
                .environmentObject(logVM)
                .task { await notificationService.requestAuthorization() }
                .task { dashboardVM.refresh() }
                .task {
                    installerListVM.refresh()
                    if settingsVM.autoRefresh {
                        installerListVM.startAutoRefresh(interval: settingsVM.refreshInterval)
                    }
                }
                .task { installedVM.refresh() }
                .task { logVM.refresh() }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Mac Updater") {
                    NSApplication.shared.orderFrontStandardAboutPanel(nil)
                }
            }
            CommandGroup(after: .newItem) {
                Button("Refresh Installer List") {
                    installerListVM.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settingsVM)
                .environmentObject(logVM)
                .frame(width: 450)
        }

        MenuBarExtra("Mac Updater", systemImage: "arrow.down.circle") {
            MenuBarView()
                .environmentObject(downloadVM)
                .environmentObject(installerListVM)
        }
        .menuBarExtraStyle(.window)
    }
}
