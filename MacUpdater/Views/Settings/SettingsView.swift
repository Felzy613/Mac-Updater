import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsVM: SettingsViewModel
    @EnvironmentObject private var logVM: LogViewerViewModel
    @State private var showingClearConfirm = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            notificationsTab
                .tabItem { Label("Notifications", systemImage: "bell") }
            logsTab
                .tabItem { Label("Logs", systemImage: "doc.text") }
            aboutTab
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
        .frame(width: 450)
    }

    private var generalTab: some View {
        Form {
            Section("Update Checking") {
                Toggle("Auto-refresh installer list", isOn: $settingsVM.autoRefresh)
                Picker("Refresh interval", selection: $settingsVM.refreshInterval) {
                    ForEach(SettingsViewModel.refreshIntervalOptions, id: \.seconds) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }
                .disabled(!settingsVM.autoRefresh)
            }
            Section("Display") {
                Toggle("Show unsupported downgrades", isOn: $settingsVM.showDowngrades)
                Toggle("Show beta installers", isOn: $settingsVM.enableBeta)
            }
        }
        .formStyle(.grouped)
    }

    private var notificationsTab: some View {
        Form {
            Section {
                Toggle("Enable notifications", isOn: $settingsVM.notificationsEnabled)
            }
            Section("Notify for") {
                Label("Download started", systemImage: "arrow.down.circle")
                Label("Download completed", systemImage: "checkmark.circle")
                Label("Download failed", systemImage: "xmark.circle")
                Label("Installer detected", systemImage: "externaldrive.badge.checkmark")
            }
            .foregroundStyle(settingsVM.notificationsEnabled ? .primary : .tertiary)
            .disabled(!settingsVM.notificationsEnabled)
        }
        .formStyle(.grouped)
    }

    private var logsTab: some View {
        Form {
            Section("Retention") {
                Picker("Keep logs for", selection: $settingsVM.logRetentionDays) {
                    ForEach(SettingsViewModel.retentionOptions, id: \.days) { option in
                        Text(option.label).tag(option.days)
                    }
                }
            }
            Section {
                Button("Clear All Logs", role: .destructive) {
                    showingClearConfirm = true
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Clear all logs?", isPresented: $showingClearConfirm) {
            Button("Clear All Logs", role: .destructive) { logVM.clearLogs() }
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            Text("Mac Updater")
                .font(.title.bold())
            Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")")
                .foregroundStyle(.secondary)
            Text("A native macOS front-end for downloading full macOS installers via Apple's softwareupdate tool.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Spacer()
        }
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
    }
}
