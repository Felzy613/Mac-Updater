import Foundation

public struct SystemInfo: Sendable {
    public let productName: String
    public let productVersion: String
    public let buildVersion: String
    public let architecture: String
    public let versionNumber: VersionNumber

    public init(
        productName: String,
        productVersion: String,
        buildVersion: String,
        architecture: String,
        versionNumber: VersionNumber
    ) {
        self.productName = productName
        self.productVersion = productVersion
        self.buildVersion = buildVersion
        self.architecture = architecture
        self.versionNumber = versionNumber
    }
}

public struct VersionNumber: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init?(_ string: String) {
        let parts = string.trimmingCharacters(in: .whitespaces).components(separatedBy: ".")
        guard !parts.isEmpty, let major = Int(parts[0]) else { return nil }
        self.major = major
        self.minor = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
        self.patch = parts.count > 2 ? (Int(parts[2]) ?? 0) : 0
    }

    public static func < (lhs: VersionNumber, rhs: VersionNumber) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    public var description: String {
        patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
    }
}
