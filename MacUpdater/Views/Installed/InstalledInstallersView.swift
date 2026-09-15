import SwiftUI
import MacUpdaterCore

struct InstalledInstallersView: View {
    @EnvironmentObject private var installedVM: InstalledInstallersViewModel
    @EnvironmentObject private var dashboardVM: DashboardViewModel

    var body: some View {
        Group {
            if installedVM.isLoading && installedVM.installers.isEmpty {
                ProgressView("Scanning /Applications…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = installedVM.error {
                ErrorView(message: error) { installedVM.refresh() }
            } else if installedVM.installers.isEmpty {
                EmptyStateView(
                    symbol: "externaldrive.badge.questionmark",
                    title: "No Installers Found",
                    subtitle: "Download a macOS installer to see it here."
                )
            } else {
                VStack(spacing: 0) {
                    if installedVM.hasLowSpaceForInstall, let space = installedVM.diskSpace {
                        spaceWarning(space)
                    }
                    List(installedVM.installers) { installer in
                        InstalledInstallerRowView(
                            installer: installer,
                            currentVersion: dashboardVM.systemInfo?.versionNumber,
                            onLaunch: { installedVM.launch(installer) },
                            onReveal: { installedVM.revealInFinder(installer.bundleURL) }
                        )
                    }
                    .listStyle(.inset)
                }
            }
        }
        .navigationTitle("Installed Installers")
        .installerAlert($installedVM.alert)
        .toolbar {
            ToolbarItem {
                if installedVM.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button { installedVM.refresh() } label: {
                        Label("Rescan", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
    }

    /// Running an installer with a nearly full disk fails partway through the upgrade,
    /// which is a much worse place to find out.
    private func spaceWarning(_ space: DiskSpace) -> some View {
        Label(
            "Only \(DiskSpace.formatted(space.availableCapacity)) free. A macOS upgrade usually needs at least "
                + "\(DiskSpace.formatted(InstallerBundleInfo.recommendedFreeSpaceForInstall)) — free up space before installing.",
            systemImage: "internaldrive.badge.exclamationmark"
        )
        .font(.callout)
        .foregroundStyle(.orange)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.orange.opacity(0.1))
    }
}
