import SwiftUI

struct DownloadRowView: View {
    let task: DownloadTask
    @EnvironmentObject private var downloadVM: DownloadManagerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.displayName)
                        .font(.headline)
                    Text(task.state.label)
                        .font(.subheadline)
                        .foregroundStyle(stateColor)
                }
                Spacer()
                stateIcon
            }

            if case .downloading(let progress) = task.state {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: progress)

                    HStack {
                        if let speed = task.speedFormatted {
                            Text(speed)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let eta = task.etaFormatted {
                            Text(eta)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else if case .preparing = task.state {
                ProgressView()
                    .controlSize(.small)
            }

            if case .failed(let error) = task.state {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if task.state.isActive {
                    Button("Cancel") { downloadVM.cancel(taskID: task.id) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.red)
                }
                if case .failed = task.state {
                    Button("Retry") { downloadVM.retry(taskID: task.id) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                if let started = task.startedAt {
                    Spacer()
                    Text(started, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    + Text(" ago")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var stateColor: Color {
        switch task.state {
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .secondary
        case .downloading, .preparing, .verifying: return .blue
        case .queued: return .secondary
        }
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch task.state {
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "slash.circle").foregroundStyle(.secondary)
        case .queued:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .verifying:
            Image(systemName: "magnifyingglass.circle").foregroundStyle(.blue)
        case .preparing, .downloading:
            EmptyView()
        }
    }
}
