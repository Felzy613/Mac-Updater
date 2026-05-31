import SwiftUI
import AppKit

struct LogViewerView: View {
    @EnvironmentObject private var logVM: LogViewerViewModel
    @State private var showingClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            if logVM.filteredEntries.isEmpty {
                EmptyStateView(symbol: "doc.text", title: "No Log Entries", subtitle: "Log entries will appear here as you use the app.")
            } else {
                List(logVM.filteredEntries) { entry in
                    LogEntryRow(entry: entry)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Logs")
        .searchable(text: $logVM.searchText, prompt: "Search logs…")
        .toolbar {
            ToolbarItemGroup {
                Picker("Level", selection: $logVM.filterLevel) {
                    Text("All Levels").tag(LogLevel?.none)
                    Divider()
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.label).tag(LogLevel?.some(level))
                    }
                }
                .frame(width: 120)

                Button { exportLogs() } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Button {
                    showingClearConfirm = true
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .tint(.red)

                Button { logVM.refresh() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .confirmationDialog("Clear all logs?", isPresented: $showingClearConfirm) {
            Button("Clear All Logs", role: .destructive) { logVM.clearLogs() }
        } message: {
            Text("This cannot be undone.")
        }
        .onAppear { logVM.refresh() }
    }

    private func exportLogs() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "MacUpdater-logs.txt"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let text = logVM.exportAsText()
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct LogEntryRow: View {
    let entry: AppLog

    var levelColor: Color {
        switch entry.level {
        case .debug: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.level.symbol)
                .foregroundStyle(levelColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(entry.formattedTimestamp)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                    Text(entry.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                }
                Text(entry.message)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 1)
    }
}
