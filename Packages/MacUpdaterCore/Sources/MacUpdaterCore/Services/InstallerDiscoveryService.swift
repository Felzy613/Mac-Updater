import Foundation

public actor InstallerDiscoveryService {
    private let shell: ShellService

    public init(shell: ShellService) {
        self.shell = shell
    }

    public func fetchInstallers() async throws -> [MacOSInstaller] {
        let output = try await shell.run(.listFullInstallers)
        return parseOutput(output)
    }

    private func parseOutput(_ output: String) -> [MacOSInstaller] {
        output
            .components(separatedBy: .newlines)
            .filter { $0.hasPrefix("* ") }
            .compactMap { parseLine(String($0.dropFirst(2))) }
    }

    private func parseLine(_ line: String) -> MacOSInstaller? {
        var fields: [String: String] = [:]
        for part in line.components(separatedBy: ", ") {
            let kv = part.components(separatedBy: ": ")
            guard kv.count >= 2 else { continue }
            let key = kv[0].trimmingCharacters(in: .whitespaces)
            let value = kv[1...].joined(separator: ": ").trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }

        guard let title = fields["Title"],
              let version = fields["Version"],
              let versionNumber = VersionNumber(version),
              let build = fields["Build"] else { return nil }

        var sizeKiB: Int64 = 0
        if let sizeStr = fields["Size"] {
            let digits = sizeStr.replacingOccurrences(of: "KiB", with: "").trimmingCharacters(in: .whitespaces)
            sizeKiB = Int64(digits) ?? 0
        }

        let isDeferred = fields["Deferred"]?.uppercased() == "YES"

        return MacOSInstaller(
            id: UUID(),
            title: title,
            version: version,
            versionNumber: versionNumber,
            build: build,
            sizeKiB: sizeKiB,
            isDeferred: isDeferred
        )
    }
}
