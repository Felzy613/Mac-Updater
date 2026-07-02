import Foundation
import MacUpdaterCore

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
