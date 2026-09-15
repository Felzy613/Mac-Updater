import SwiftUI
import MacUpdaterCore

struct DashboardView: View {
    @EnvironmentObject private var dashboardVM: DashboardViewModel
    @EnvironmentObject private var installerListVM: InstallerListViewModel
    @EnvironmentObject private var downloadVM: DownloadManagerViewModel

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let error = dashboardVM.error {
                    ErrorView(message: error) { dashboardVM.refresh() }
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        systemCard
                        updatesCard
                        downloadsCard
                        installedCard
                        storageCard
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItem {
                if dashboardVM.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button { dashboardVM.refresh() } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }

    private var systemCard: some View {
        DashboardCard(
            symbol: "desktopcomputer",
            title: "Current System",
            color: .blue
        ) {
            if let info = dashboardVM.systemInfo {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(info.productName) \(info.productVersion)")
                        .font(.headline)
                    Text("Build \(info.buildVersion)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(info.architecture)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: Capsule())
                }
            } else {
                Text("Detecting…")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var updatesCard: some View {
        DashboardCard(
            symbol: "square.and.arrow.down.on.square",
            title: "Available Updates",
            color: .green
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(installerListVM.upgradeCount)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                Text(installerListVM.upgradeCount == 1 ? "upgrade available" : "upgrades available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let refreshed = installerListVM.lastRefreshed {
                    Text("Updated \(refreshed, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var downloadsCard: some View {
        DashboardCard(
            symbol: "arrow.down.circle",
            title: "Downloads",
            color: .orange
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(downloadVM.activeCount)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.orange)
                Text(downloadVM.activeCount == 1 ? "active download" : "active downloads")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                let totalTasks = downloadVM.tasks.count
                if totalTasks > 0 {
                    Text("\(totalTasks) total in history")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    /// Free space is the single most common reason a download or an upgrade fails,
    /// so it belongs on the front page rather than in an error message afterwards.
    private var storageCard: some View {
        DashboardCard(
            symbol: "internaldrive",
            title: "Free Space",
            color: hasRoomToInstall ? .teal : .orange
        ) {
            VStack(alignment: .leading, spacing: 4) {
                if let space = dashboardVM.diskSpace {
                    Text(DiskSpace.formatted(space.availableCapacity))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(hasRoomToInstall ? .teal : .orange)
                    Text("of \(DiskSpace.formatted(space.totalCapacity)) available")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !hasRoomToInstall {
                        Text("A macOS upgrade usually needs at least \(DiskSpace.formatted(InstallerBundleInfo.recommendedFreeSpaceForInstall)).")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Checking…").foregroundStyle(.secondary)
                }
            }
        }
    }

    private var hasRoomToInstall: Bool {
        guard let space = dashboardVM.diskSpace else { return true }
        return space.availableCapacity >= InstallerBundleInfo.recommendedFreeSpaceForInstall
    }

    private var installedCard: some View {
        DashboardCard(
            symbol: "externaldrive.badge.checkmark",
            title: "Installed Installers",
            color: .purple
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(dashboardVM.installedCount)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.purple)
                Text(dashboardVM.installedCount == 1 ? "installer found" : "installers found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct DashboardCard<Content: View>: View {
    let symbol: String
    let title: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            content
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator, lineWidth: 0.5)
        )
    }
}
