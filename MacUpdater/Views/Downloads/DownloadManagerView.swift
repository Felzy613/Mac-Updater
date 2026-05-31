import SwiftUI

struct DownloadManagerView: View {
    @EnvironmentObject private var downloadVM: DownloadManagerViewModel

    var body: some View {
        Group {
            if downloadVM.tasks.isEmpty {
                EmptyStateView(
                    symbol: "arrow.down.circle",
                    title: "No Downloads",
                    subtitle: "Downloads you start will appear here."
                )
            } else {
                List(downloadVM.tasks) { task in
                    DownloadRowView(task: task)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Downloads")
        .toolbar {
            ToolbarItem {
                Button("Clear Completed") {
                    downloadVM.clearCompleted()
                }
                .disabled(downloadVM.tasks.allSatisfy { $0.state.isActive })
            }
        }
        .sheet(item: $downloadVM.pendingElevationTaskID) { taskID in
            ElevationSheet(taskID: taskID)
        }
    }
}
