import Foundation

struct SystemInfo: Sendable {
    let productName: String
    let productVersion: String
    let buildVersion: String
    let architecture: String
    let versionNumber: VersionNumber
}

struct VersionNumber: Comparable, Hashable, Sendable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ string: String) {
        let parts = string.trimmingCharacters(in: .whitespaces).components(separatedBy: ".")
        guard !parts.isEmpty, let major = Int(parts[0]) else { return nil }
        self.major = major
        self.minor = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        self.patch = parts.count > 2 ? (Int(parts[2]) ?? 0) : 0
    }

    static func < (lhs: VersionNumber, rhs: VersionNumber) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    var description: String {
        patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }
}
