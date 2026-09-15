import Foundation

/// A snapshot of free space on the volume that holds `/Applications`.
///
/// `softwareupdate --fetch-full-installer` needs room for two copies of the installer:
/// the downloaded package under `/Library/Updates` plus the expanded
/// `Install macOS *.app` in `/Applications`. `requiredBytes(forInstallerSize:)`
/// encodes that so the app can explain a space failure with real numbers instead of
/// letting `softwareupdate` fail with a bare exit code.
public struct DiskSpace: Sendable, Equatable {
    /// Total size of the volume.
    public let totalCapacity: Int64
    /// Free blocks — what actually shrinks while a download runs.
    public let freeCapacity: Int64
    /// What macOS reports as usable, including space it could purge on demand.
    public let availableCapacity: Int64

    public init(totalCapacity: Int64, freeCapacity: Int64, availableCapacity: Int64) {
        self.totalCapacity = totalCapacity
        self.freeCapacity = freeCapacity
        self.availableCapacity = availableCapacity
    }

    public static let applicationsURL = URL(fileURLWithPath: "/Applications")

    public static func current(for url: URL = DiskSpace.applicationsURL) -> DiskSpace? {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }

        let total = Int64(values.volumeTotalCapacity ?? 0)
        let free = Int64(values.volumeAvailableCapacity ?? 0)
        // Important-usage capacity counts purgeable space, so it is never smaller than free.
        let important = values.volumeAvailableCapacityForImportantUsage ?? free

        return DiskSpace(totalCapacity: total, freeCapacity: free, availableCapacity: max(free, important))
    }

    /// Space `softwareupdate` needs to land an installer of `installerSize` bytes:
    /// the package, the expanded app, and a little headroom.
    public static func requiredBytes(forInstallerSize installerSize: Int64) -> Int64 {
        guard installerSize > 0 else { return 0 }
        return installerSize * 2 + 2_000_000_000
    }

    public static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}
