import Foundation

public struct MacOSInstaller: Identifiable, Sendable {
    public let id: UUID
    public let title: String
    public let version: String
    public let versionNumber: VersionNumber
    public let build: String
    public let sizeKiB: Int64
    public let isDeferred: Bool
    public var isDowngrade: Bool = false

    public init(
        id: UUID,
        title: String,
        version: String,
        versionNumber: VersionNumber,
        build: String,
        sizeKiB: Int64,
        isDeferred: Bool,
        isDowngrade: Bool = false
    ) {
        self.id = id
        self.title = title
        self.version = version
        self.versionNumber = versionNumber
        self.build = build
        self.sizeKiB = sizeKiB
        self.isDeferred = isDeferred
        self.isDowngrade = isDowngrade
    }

    public var displayName: String { "\(title) \(version)" }

    public var sizeFormatted: String {
        let bytes = Double(sizeKiB) * 1024
        let gb = bytes / 1_000_000_000
        if gb >= 1 {
            return String(format: "%.1f GB", gb)
        }
        let mb = bytes / 1_000_000
        return String(format: "%.0f MB", mb)
    }
}
