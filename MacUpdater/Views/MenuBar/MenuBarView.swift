import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var downloadVM: DownloadManagerViewModel
    @EnvironmentObject private var installerListVM: InstallerListViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if downloadVM.tasks.isEmpty {
                emptyState
            } else {
                downloadList
            }
            Divider()
            footer
        }
        .frame(width: 280)
    }

    private var header: some View {
        HStack {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.blue)
            VStack(alignment: .leading) {
                Text("Mac Updater")
                    .font(.headline)
                Text(downloadVM.activeCount > 0
                     ? "\(downloadVM.activeCount) active download\(downloadVM.activeCount == 1 ? "" : "s")"
                     : "\(installerListVM.upgradeCount) upgrade\(installerListVM.upgradeCount == 1 ? "" : "s") available")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        Text("No downloads")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
    }

    private var downloadList: some View {
        ForEach(downloadVM.tasks.prefix(5)) { task in
            MenuBarDownloadRow(task: task)
            if task.id != downloadVM.tasks.prefix(5).last?.id {
                Divider().padding(.horizontal)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open Mac Updater") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                NSApplication.shared.windows.first?.makeKeyAndOrderFront(nil)
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct MenuBarDownloadRow: View {
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(task.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                stateIndicator
            }
            if case .downloading(let progress) = task.state {
                ProgressView(value: progress)
                    .controlSize(.mini)
                HStack {
                    if let speed = task.speedFormatted {
                        Text(speed).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let eta = task.etaFormatted {
                        Text(eta).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var stateIndicator: some View {
        switch task.state {
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red).font(.caption)
        case .cancelled:
            Image(systemName: "slash.circle").foregroundStyle(.secondary).font(.caption)
        case .queued, .preparing:
            ProgressView().controlSize(.mini)
        case .verifying:
            Image(systemName: "magnifyingglass").foregroundStyle(.blue).font(.caption)
        case .downloading:
            EmptyView()
        }
    }
}
