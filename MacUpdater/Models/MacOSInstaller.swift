import Foundation

struct MacOSInstaller: Identifiable, Sendable {
    let id: UUID
    let title: String
    let version: String
    let versionNumber: VersionNumber
    let build: String
    let sizeKiB: Int64
    let isDeferred: Bool
    var isDowngrade: Bool = false

    var displayName: String { "\(title) \(version)" }

    var sizeFormatted: String {
        let bytes = Double(sizeKiB) * 1024
        let gb = bytes / 1_000_000_000
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = bytes / 1_000_000
        return String(format: "%.0f MB", mb)
    }
}

struct InstalledInstaller: Identifiable, Sendable {
    let id: UUID
    let bundleURL: URL
    let displayName: String
    let version: String
    let versionNumber: VersionNumber
    let build: String
    let sizeOnDisk: Int64?
    let dateModified: Date?
}
