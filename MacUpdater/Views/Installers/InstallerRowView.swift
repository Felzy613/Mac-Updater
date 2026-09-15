import SwiftUI
import MacUpdaterCore

struct InstallerRowView: View {
    let installer: MacOSInstaller
    let onDownload: () -> Void

    @EnvironmentObject private var downloadVM: DownloadManagerViewModel

    private var tasksForInstaller: [DownloadTask] {
        downloadVM.tasks.filter { $0.installerVersion == installer.version }
    }

    private var activeTask: DownloadTask? {
        tasksForInstaller.first { $0.state.isActive }
    }

    private var completedTask: DownloadTask? {
        tasksForInstaller.first { if case .completed = $0.state { return true } else { return false } }
    }

    private var failedTask: DownloadTask? {
        tasksForInstaller.first { $0.state.failure != nil }
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

                if let failure = failedTask?.state.failure, activeTask == nil, completedTask == nil {
                    Label(failure.summary, systemImage: failure.symbol)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
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
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            } else if let completed = completedTask {
                VStack(alignment: .trailing, spacing: 4) {
                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                    if completed.installerURL != nil {
                        Button("Open Installer") { downloadVM.openInstaller(taskID: completed.id) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            } else {
                Button(failedTask == nil ? "Download" : "Try Again", action: onDownload)
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

    private var task: DownloadTask? {
        downloadVM.tasks.first { $0.id == taskID }
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Administrator Password Required")
                .font(.title2)
                .bold()

            if let name = task?.displayName {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Text("softwareupdate reported a permissions problem for this download. Retrying with administrator "
                 + "privileges lets it write to /Applications — macOS will ask for your password before it starts.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let raw = task?.state.failure?.rawOutput, !raw.isEmpty {
                ScrollView {
                    Text(raw)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 80)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 12) {
                Button("Not Now") {
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
        .frame(width: 420)
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}
