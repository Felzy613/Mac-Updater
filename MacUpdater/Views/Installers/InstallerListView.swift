import SwiftUI

struct InstallerListView: View {
    @EnvironmentObject private var installerListVM: InstallerListViewModel
    @EnvironmentObject private var downloadVM: DownloadManagerViewModel
    @EnvironmentObject private var settingsVM: SettingsViewModel

    var body: some View {
        Group {
            if installerListVM.isLoading && installerListVM.filteredInstallers.isEmpty {
                ProgressView("Fetching available installers…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = installerListVM.error {
                ErrorView(message: error) { installerListVM.refresh() }
            } else if installerListVM.filteredInstallers.isEmpty {
                EmptyStateView(
                    symbol: "square.and.arrow.down.on.square",
                    title: "No Updates Available",
                    subtitle: "Your macOS version is up to date, or no newer installers were found."
                )
            } else {
                List(installerListVM.filteredInstallers) { installer in
                    InstallerRowView(installer: installer) {
                        downloadVM.startDownload(installer: installer)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Available Updates")
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $installerListVM.showDowngrades) {
                    Label("Show Downgrades", systemImage: "arrow.down.backward.circle")
                }
                .toggleStyle(.button)
                .help("Show installers older than your current macOS version")

                if installerListVM.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Button { installerListVM.refresh() } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
        }
        .sheet(item: $downloadVM.pendingElevationTaskID) { taskID in
            ElevationSheet(taskID: taskID)
        }
    }
}
