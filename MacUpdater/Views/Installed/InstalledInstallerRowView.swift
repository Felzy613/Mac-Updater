import SwiftUI
import MacUpdaterCore

struct InstalledInstallerRowView: View {
    let installer: InstalledInstaller
    let currentVersion: VersionNumber?
    let onLaunch: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: installer.isComplete ? "externaldrive.badge.checkmark" : "externaldrive.badge.xmark")
                .font(.title)
                .foregroundStyle(installer.isComplete ? .green : .orange)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(installer.displayName)
                    .font(.headline)

                HStack(spacing: 8) {
                    Text("macOS \(installer.macOSVersion)")
                    if !installer.build.isEmpty {
                        Text("Build \(installer.build)")
                    }
                    if let size = installer.sizeFormatted {
                        Text(size)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let modified = installer.dateModified {
                    Text("Downloaded \(modified, style: .date)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let issue = installer.issueDescription {
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Button("Open Installer", action: onLaunch)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!installer.isComplete)

                Button("Show in Finder", action: onReveal)
                    .buttonStyle(.link)
                    .font(.caption)

                if let current = currentVersion, installer.versionNumber < current {
                    Label("Older than macOS \(current.description)", systemImage: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
