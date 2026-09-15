import Foundation

/// Everything we can learn about an `Install macOS *.app` bundle on disk.
///
/// The macOS version has to come from `DTPlatformVersion`: an installer's
/// `CFBundleShortVersionString` is the *InstallAssistant* version, not the OS version
/// (the macOS 27.0 installer reports `22.0.02`), so matching on it silently fails.
public struct InstallerBundleInfo: Sendable, Equatable, Identifiable {
    public enum Issue: String, Sendable, Equatable {
        case missingPayload
        case truncatedPayload
        case missingExecutable

        public var describes: String {
            switch self {
            case .missingPayload:
                return "the installer payload (SharedSupport.dmg) is missing"
            case .truncatedPayload:
                return "the installer payload looks truncated"
            case .missingExecutable:
                return "the installer application is missing its executable"
            }
        }
    }

    public var id: URL { bundleURL }

    public let bundleURL: URL
    public let displayName: String
    /// The macOS version this installer installs, e.g. "27.0".
    public let macOSVersion: String
    public let versionNumber: VersionNumber
    /// Empty when the bundle carries no trustworthy build string.
    public let build: String
    /// The InstallAssistant's own version — shown for diagnostics only.
    public let installAssistantVersion: String
    /// Size of `SharedSupport.dmg`; 0 when it is missing.
    public let payloadSize: Int64
    public let sizeOnDisk: Int64?
    public let dateModified: Date?
    public let issues: [Issue]

    public init(
        bundleURL: URL,
        displayName: String,
        macOSVersion: String,
        versionNumber: VersionNumber,
        build: String,
        installAssistantVersion: String,
        payloadSize: Int64,
        sizeOnDisk: Int64?,
        dateModified: Date?,
        issues: [Issue]
    ) {
        self.bundleURL = bundleURL
        self.displayName = displayName
        self.macOSVersion = macOSVersion
        self.versionNumber = versionNumber
        self.build = build
        self.installAssistantVersion = installAssistantVersion
        self.payloadSize = payloadSize
        self.sizeOnDisk = sizeOnDisk
        self.dateModified = dateModified
        self.issues = issues
    }

    public var isComplete: Bool { issues.isEmpty }

    public var issueDescription: String? {
        guard !issues.isEmpty else { return nil }
        let list = issues.map(\.describes).joined(separator: ", and ")
        return "This installer is incomplete — \(list). Delete it and download again."
    }
}

public enum InstallerBundleInspector {
    public static let applicationsURL = URL(fileURLWithPath: "/Applications")

    /// A full macOS installer payload is always well over 8 GB; anything smaller is a
    /// partial download left behind by an interrupted `softwareupdate` run.
    private static let minimumPlausiblePayload: Int64 = 8_000_000_000

    public static func isInstallerBundle(_ url: URL) -> Bool {
        url.lastPathComponent.hasPrefix("Install macOS") && url.pathExtension == "app"
    }

    public static func installedInstallers(in directory: URL = applicationsURL) throws -> [InstallerBundleInfo] {
        let items = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: .skipsHiddenFiles
        )
        return items
            .filter(isInstallerBundle)
            .compactMap { inspect(bundleURL: $0) }
    }

    /// Finds the installer for `version`, preferring an exact match and falling back to
    /// the same major.minor (installer bundles are not always stamped with the point release).
    public static func find(
        version: String,
        in directory: URL = applicationsURL,
        modifiedAfter: Date? = nil
    ) -> InstallerBundleInfo? {
        let candidates = (try? installedInstallers(in: directory)) ?? []
        guard !candidates.isEmpty else { return nil }
        guard let wanted = VersionNumber(version) else { return nil }

        if let exact = candidates.first(where: { $0.versionNumber == wanted }) {
            return exact
        }
        if let sameMinor = candidates.first(where: {
            $0.versionNumber.major == wanted.major && $0.versionNumber.minor == wanted.minor
        }) {
            return sameMinor
        }
        // Last resort: `softwareupdate` said it succeeded, so a bundle written since the
        // download began is the one it just produced, whatever it calls itself.
        if let since = modifiedAfter {
            return candidates
                .filter { ($0.dateModified ?? .distantPast) >= since }
                .max(by: { ($0.dateModified ?? .distantPast) < ($1.dateModified ?? .distantPast) })
        }
        return nil
    }

    public static func inspect(bundleURL: URL) -> InstallerBundleInfo? {
        let fm = FileManager.default
        guard let bundle = Bundle(url: bundleURL), let info = bundle.infoDictionary else { return nil }

        let displayName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent

        let installAssistantVersion = (info["CFBundleShortVersionString"] as? String) ?? ""
        let sharedSupport = readSharedSupportVersion(bundleURL: bundleURL)

        guard let (macOSVersion, versionNumber) = resolveOSVersion(
            info: info,
            sharedSupportVersion: sharedSupport?.version,
            displayName: displayName
        ) else { return nil }

        let payloadURL = bundleURL.appendingPathComponent("Contents/SharedSupport/SharedSupport.dmg")
        let legacyPayloadURL = bundleURL.appendingPathComponent("Contents/SharedSupport/InstallESD.dmg")
        let payloadSize = fileSize(at: payloadURL) ?? fileSize(at: legacyPayloadURL) ?? 0

        var issues: [InstallerBundleInfo.Issue] = []
        if payloadSize == 0 {
            issues.append(.missingPayload)
        } else if payloadSize < minimumPlausiblePayload {
            issues.append(.truncatedPayload)
        }
        if let executable = info["CFBundleExecutable"] as? String {
            let execURL = bundleURL.appendingPathComponent("Contents/MacOS/\(executable)")
            if !fm.isExecutableFile(atPath: execURL.path) {
                issues.append(.missingExecutable)
            }
        } else {
            issues.append(.missingExecutable)
        }

        let attributes = try? fm.attributesOfItem(atPath: bundleURL.path)

        return InstallerBundleInfo(
            bundleURL: bundleURL,
            displayName: displayName,
            macOSVersion: macOSVersion,
            versionNumber: versionNumber,
            build: sharedSupport?.build ?? "",
            installAssistantVersion: installAssistantVersion,
            payloadSize: payloadSize,
            // The payload is ~99.9% of the bundle; walking 18 GB of files to refine that
            // would stall the UI for no benefit.
            sizeOnDisk: payloadSize > 0 ? payloadSize : nil,
            dateModified: attributes?[.modificationDate] as? Date,
            issues: issues
        )
    }

    // MARK: - Private

    private static func resolveOSVersion(
        info: [String: Any],
        sharedSupportVersion: String?,
        displayName: String
    ) -> (String, VersionNumber)? {
        let candidates: [String?] = [
            info["DTPlatformVersion"] as? String,
            sharedSupportVersion,
            versionFromName(displayName),
            info["CFBundleShortVersionString"] as? String
        ]
        for case let candidate? in candidates {
            if let number = VersionNumber(candidate), number.major >= 10 {
                return (candidate, number)
            }
        }
        return nil
    }

    /// "Install macOS 27 Golden Gate" → "27". Named releases ("Install macOS Tahoe")
    /// carry no number and fall through to the next candidate.
    private static func versionFromName(_ name: String) -> String? {
        let parts = name.components(separatedBy: " ")
        return parts.first { part in
            guard let first = part.unicodeScalars.first, CharacterSet.decimalDigits.contains(first) else { return false }
            return VersionNumber(part) != nil
        }
    }

    private static func readSharedSupportVersion(bundleURL: URL) -> (version: String, build: String)? {
        let plistURL = bundleURL.appendingPathComponent("Contents/SharedSupport/SharedSupportVersion.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }

        let version = plist["SharedSupportVersion"] as? String
        let build = (plist["SharedSupportBuild"] as? String) ?? version ?? ""
        guard let version else { return nil }
        return (version, build)
    }

    private static func fileSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize, size > 0 else { return nil }
        return Int64(size)
    }
}
