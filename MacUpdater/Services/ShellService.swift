import Foundation

enum ShellError: LocalizedError, Sendable {
    case invalidVersion(String)
    case nonZeroExit(Int32, String)
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidVersion(let v): return "Invalid version format: \(v)"
        case .nonZeroExit(let code, let msg): return "Command exited \(code): \(msg)"
        case .launchFailed(let msg): return "Failed to launch: \(msg)"
        }
    }
}

enum ShellOutput: Sendable {
    case stdout(String)
    case stderr(String)
    case exit(code: Int32)
}

enum AllowedCommand: Sendable {
    case swVers
    case uname(flag: String)
    case listFullInstallers
    case fetchFullInstaller(version: String)

    nonisolated(unsafe) private static let versionPattern = /^[0-9]+\.[0-9]+(\.[0-9]+)?$/

    var executableURL: URL {
        switch self {
        case .swVers: return URL(fileURLWithPath: "/usr/bin/sw_vers")
        case .uname: return URL(fileURLWithPath: "/usr/bin/uname")
        case .listFullInstallers, .fetchFullInstaller: return URL(fileURLWithPath: "/usr/sbin/softwareupdate")
        }
    }

    var arguments: [String] {
        switch self {
        case .swVers: return []
        case .uname(let flag): return [flag]
        case .listFullInstallers: return ["--list-full-installers"]
        case .fetchFullInstaller(let version): return ["--fetch-full-installer", "--full-installer-version", version]
        }
    }

    static func makeFetchFullInstaller(version: String) throws -> AllowedCommand {
        guard (try? versionPattern.wholeMatch(in: version)) != nil else {
            throw ShellError.invalidVersion(version)
        }
        return .fetchFullInstaller(version: version)
    }
}

actor ShellService {
    func run(_ command: AllowedCommand) async throws -> String {
        let execURL = command.executableURL
        let args = command.arguments

        return try await Task.detached {
            let process = Process()
            process.executableURL = execURL
            process.arguments = args

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                throw ShellError.launchFailed(error.localizedDescription)
            }

            process.waitUntilExit()

            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outData, encoding: .utf8) ?? ""
            let errOutput = String(data: errData, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw ShellError.nonZeroExit(process.terminationStatus, errOutput.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return output
        }.value
    }
}
