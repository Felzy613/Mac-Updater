import Foundation

public actor SystemInfoService {
    private let shell: ShellService

    public init(shell: ShellService) {
        self.shell = shell
    }

    public func detect() async throws -> SystemInfo {
        async let swVersOutput = shell.run(.swVers)
        async let archOutput = shell.run(.uname(flag: "-m"))

        let (swVers, arch) = try await (swVersOutput, archOutput)
        return parse(swVers: swVers, arch: arch)
    }

    private func parse(swVers: String, arch: String) -> SystemInfo {
        var productName = "macOS"
        var productVersion = "0.0"
        var buildVersion = ""

        for line in swVers.components(separatedBy: .newlines) {
            let parts = line.components(separatedBy: ":")
            guard parts.count >= 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
            switch key {
            case "ProductName": productName = value
            case "ProductVersion": productVersion = value
            case "BuildVersion": buildVersion = value
            default: break
            }
        }

        let archClean = arch.trimmingCharacters(in: .whitespacesAndNewlines)
        let archDisplay = archClean == "arm64" ? "Apple Silicon" : (archClean == "x86_64" ? "Intel" : archClean)

        return SystemInfo(
            productName: productName,
            productVersion: productVersion,
            buildVersion: buildVersion,
            architecture: archDisplay,
            versionNumber: VersionNumber(productVersion) ?? VersionNumber("0.0")!
        )
    }
}
