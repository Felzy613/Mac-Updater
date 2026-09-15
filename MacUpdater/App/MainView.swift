import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard, installers, downloads, installed, logs

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .installers: return "Available Updates"
        case .downloads: return "Downloads"
        case .installed: return "Installed"
        case .logs: return "Logs"
        }
    }

    var symbol: String {
        switch self {
        case .dashboard: return "house"
        case .installers: return "square.and.arrow.down.on.square"
        case .downloads: return "arrow.down.circle"
        case .installed: return "externaldrive.badge.checkmark"
        case .logs: return "doc.text"
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var installerListVM: InstallerListViewModel
    @EnvironmentObject private var downloadVM: DownloadManagerViewModel
    @EnvironmentObject private var installedVM: InstalledInstallersViewModel
    @EnvironmentObject private var dashboardVM: DashboardViewModel
    @State private var selectedSection: AppSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selectedSection) { section in
                Label(section.label, systemImage: section.symbol)
                    .badge(badge(for: section))
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .listStyle(.sidebar)
        } detail: {
            detailView
                .navigationSplitViewColumnWidth(min: 500, ideal: 700)
        }
        .frame(minWidth: 720, minHeight: 500)
        // A download that just finished changes both of these, so re-read them when the
        // user actually looks rather than showing a stale scan.
        .onChange(of: selectedSection) { section in
            switch section {
            case .installed: installedVM.refresh()
            case .dashboard: dashboardVM.refresh()
            default: break
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSection {
        case .dashboard, nil:
            DashboardView()
        case .installers:
            InstallerListView()
        case .downloads:
            DownloadManagerView()
        case .installed:
            InstalledInstallersView()
        case .logs:
            LogViewerView()
        }
    }

    private func badge(for section: AppSection) -> Int {
        switch section {
        case .installers: return installerListVM.upgradeCount
        case .downloads: return downloadVM.activeCount
        default: return 0
        }
    }
}
