import SwiftUI
import MacUpdaterCore

struct InstalledInstallerRowView: View {
    let installer: InstalledInstaller
    let currentVersion: VersionNumber?
    let onLaunch: () -> Void

    private var sizeFormatted: String? {
        guard let size = installer.sizeOnDisk else { return nil }
        let gb = Double(size) / 1_000_000_000
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        let mb = Double(size) / 1_000_000
        return String(format: "%.0f MB", mb)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.checkmark")
                .font(.title)
                .foregroundStyle(.green)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(installer.displayName)
                    .font(.headline)
                HStack(spacing: 8) {
                    Text("Version \(installer.version)")
                    if !installer.build.isEmpty {
                        Text("Build \(installer.build)")
                    }
                    if let size = sizeFormatted {
                        Text(size)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let modified = installer.dateModified {
                    Text("Modified \(modified, style: .date)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Button("Open Installer", action: onLaunch)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                if let current = currentVersion, installer.versionNumber < current {
                    Label("Older version", systemImage: "arrow.down")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
