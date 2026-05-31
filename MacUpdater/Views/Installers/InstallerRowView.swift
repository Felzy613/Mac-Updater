import SwiftUI

struct InstallerRowView: View {
    let installer: MacOSInstaller
    let onDownload: () -> Void

    @EnvironmentObject private var downloadVM: DownloadManagerViewModel

    private var activeTask: DownloadTask? {
        downloadVM.tasks.first { task in
            task.installerVersion == installer.version && task.state.isActive
        }
    }

    private var isCompleted: Bool {
        downloadVM.tasks.contains { task in
            guard task.installerVersion == installer.version else { return false }
            if case .completed = task.state { return true }
            return false
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.title)
                .foregroundStyle(.secondary)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(installer.displayName)
                        .font(.headline)
                    if installer.isDowngrade {
                        Label("Downgrade", systemImage: "arrow.down.backward.circle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.15), in: Capsule())
                    }
                    if installer.isDeferred {
                        Text("Deferred")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.15), in: Capsule())
                    }
                }
                Text("Build \(installer.build) · \(installer.sizeFormatted)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let task = activeTask {
                VStack(alignment: .trailing, spacing: 4) {
                    Text(task.state.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let progress = task.state.progress {
                        ProgressView(value: progress)
                            .frame(width: 100)
                    }
                }
            } else if isCompleted {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            } else {
                Button("Download", action: onDownload)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ElevationSheet: View {
    let taskID: UUID
    @EnvironmentObject private var downloadVM: DownloadManagerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Administrator Password Required")
                .font(.title2)
                .bold()

            Text("This download requires your administrator password. macOS will prompt you to authenticate before the download begins.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Cancel") {
                    downloadVM.dismissElevation()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Continue with Password") {
                    downloadVM.confirmElevation(taskID: taskID)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 400)
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
