import Foundation
import MacUpdaterCore

actor InstalledInstallerService {
    func scanInstalledInstallers() throws -> [InstalledInstaller] {
        let appsURL = URL(fileURLWithPath: "/Applications")
        let items = try FileManager.default.contentsOfDirectory(
            at: appsURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        )
        return items
            .filter { $0.lastPathComponent.hasPrefix("Install macOS") && $0.pathExtension == "app" }
            .compactMap { readInstallerBundle(at: $0) }
    }

    func scanForInstaller(version: String) -> Bool {
        let appsURL = URL(fileURLWithPath: "/Applications")
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: appsURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return false }

        return items.contains { url in
            guard url.lastPathComponent.hasPrefix("Install macOS"), url.pathExtension == "app" else { return false }
            if let bundle = Bundle(url: url),
               let v = bundle.infoDictionary?["CFBundleShortVersionString"] as? String {
                return v.hasPrefix(version)
            }
            return false
        }
    }

    private func readInstallerBundle(at url: URL) -> InstalledInstaller? {
        guard let bundle = Bundle(url: url),
              let info = bundle.infoDictionary else { return nil }

        let displayName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let version = (info["CFBundleShortVersionString"] as? String) ?? "0.0"
        guard let versionNumber = VersionNumber(version) else { return nil }

        let build = readBuildFromSharedSupport(url: url) ?? ""

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let dateModified = attributes?[.modificationDate] as? Date

        let sizeOnDisk = calculateDirectorySize(url: url)

        return InstalledInstaller(
            id: UUID(),
            bundleURL: url,
            displayName: displayName,
            version: version,
            versionNumber: versionNumber,
            build: build,
            sizeOnDisk: sizeOnDisk,
            dateModified: dateModified
        )
    }

    private func readBuildFromSharedSupport(url: URL) -> String? {
        let plistURL = url
            .appendingPathComponent("Contents/SharedSupport/SharedSupportVersion.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let build = plist["SharedSupportVersion"] as? String else { return nil }
        return build
    }

    private func calculateDirectorySize(url: URL) -> Int64? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
