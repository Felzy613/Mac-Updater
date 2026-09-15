import Foundation
import MacUpdaterCore

/// The installed-installer model is `InstallerBundleInfo` from MacUpdaterCore — the same
/// type the download verifier uses, so both halves of the app agree on what an installer
/// is and which macOS version it carries.
typealias InstalledInstaller = InstallerBundleInfo

extension InstallerBundleInfo {
    var sizeFormatted: String? {
        guard let size = sizeOnDisk, size > 0 else { return nil }
        return DiskSpace.formatted(size)
    }

    /// macOS upgrades need far more room than the installer itself; this is Apple's
    /// rough guidance for an upgrade with room for the conversion.
    static let recommendedFreeSpaceForInstall: Int64 = 25_000_000_000
}
