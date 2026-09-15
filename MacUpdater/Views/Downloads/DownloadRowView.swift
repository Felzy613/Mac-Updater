import SwiftUI
import MacUpdaterCore

struct DownloadRowView: View {
    let task: DownloadTask
    @EnvironmentObject private var downloadVM: DownloadManagerViewModel
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            progressSection
            if let failure = task.state.failure {
                FailureView(failure: failure, showDetails: $showDetails)
            }
            actions
        }
        .padding(.vertical, 6)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.displayName)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(task.state.label)
                        .foregroundStyle(stateColor)
                    if let size = task.sizeFormatted {
                        Text("· \(size)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
            Spacer()
            stateIcon
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        if let progress = task.state.progress {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                HStack {
                    if let speed = task.speedFormatted {
                        Text(speed)
                    }
                    Spacer()
                    if let eta = task.etaFormatted {
                        Text(eta)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } else if task.state.isActive {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                if case .preparing = task.state {
                    Text("softwareupdate is checking Apple's catalogue — this can take a minute.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        if task.isStalled {
            Label(
                "No data has arrived for several minutes. The download may be stuck — cancelling and retrying is safe.",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            if task.state.isActive {
                Button("Cancel") { downloadVM.cancel(taskID: task.id) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
            }

            if case .completed = task.state, task.installerURL != nil {
                Button("Open Installer") { downloadVM.openInstaller(taskID: task.id) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Show in Finder") { downloadVM.revealInstaller(taskID: task.id) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            if let failure = task.state.failure {
                if failure.isRetryable {
                    Button("Retry") { downloadVM.retry(taskID: task.id) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if failure.suggestsElevation {
                    Button("Retry with Password") { downloadVM.confirmElevation(taskID: task.id) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                // Our space estimate is a rule of thumb; let the user overrule it.
                if failure.reason == .insufficientSpace {
                    Button("Download Anyway") { downloadVM.retryIgnoringSpaceCheck(taskID: task.id) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            Spacer()

            if let started = task.startedAt {
                HStack(spacing: 2) {
                    Text(started, style: .relative)
                    Text("ago")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var stateColor: Color {
        switch task.state {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        case .downloading, .preparing, .verifying, .installing: return .blue
        case .queued: return .secondary
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch task.state {
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let failure):
            Image(systemName: failure.symbol).foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "slash.circle").foregroundStyle(.secondary)
        case .queued:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .verifying:
            Image(systemName: "magnifyingglass.circle").foregroundStyle(.blue)
        case .preparing, .downloading, .installing:
            EmptyView()
        }
    }
}

/// What went wrong, what to do about it, and — on request — exactly what
/// `softwareupdate` printed. The last part is what previously only existed in the log.
private struct FailureView: View {
    let failure: DownloadFailure
    @Binding var showDetails: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(failure.summary, systemImage: failure.symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.red)

            if let recovery = failure.recovery {
                Text(recovery)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !failure.rawOutput.isEmpty {
                DisclosureGroup(isExpanded: $showDetails) {
                    VStack(alignment: .leading, spacing: 6) {
                        ScrollView(.vertical) {
                            Text(failure.rawOutput)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)

                        Button("Copy Details") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(failure.rawOutput, forType: .string)
                        }
                        .buttonStyle(.link)
                        .font(.caption)
                    }
                    .padding(.top, 4)
                } label: {
                    Text("Details from softwareupdate")
                        .font(.caption)
                }
                .font(.caption)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}
