import SwiftUI
import MacUpdaterCore

struct InstalledInstallersView: View {
    @EnvironmentObject private var installedVM: InstalledInstallersViewModel
    @EnvironmentObject private var dashboardVM: DashboardViewModel

    var body: some View {
        Group {
            if installedVM.isLoading {
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
                List(installedVM.installers) { installer in
                    InstalledInstallerRowView(
                        installer: installer,
                        currentVersion: dashboardVM.systemInfo?.versionNumber
                    ) {
                        installedVM.launch(installer)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Installed Installers")
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
}
