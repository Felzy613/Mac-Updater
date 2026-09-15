import Foundation
import MacUpdaterCore

/// A `softwareupdate` failure translated into something a person can act on.
///
/// `softwareupdate` exits 1 for essentially everything, so the exit code alone says
/// nothing — the reason has to be read out of the output text and paired with the
/// state of the machine (free space, the size of the installer we asked for).
struct DownloadFailure: Sendable, Equatable, Identifiable {
    enum Reason: String, Sendable {
        case insufficientSpace
        case authorizationRequired
        case userCancelled
        case network
        case notEligible
        case versionUnavailable
        case updateInProgress
        case installerMissing
        case incompleteInstaller
        case launchFailed
        case unknown
    }

    let id: UUID
    let reason: Reason
    /// One line, shown on the download row.
    let summary: String
    /// What to do about it.
    let recovery: String?
    /// Everything `softwareupdate` printed, for the details disclosure.
    let rawOutput: String
    let exitCode: Int32?

    init(
        reason: Reason,
        summary: String,
        recovery: String? = nil,
        rawOutput: String = "",
        exitCode: Int32? = nil
    ) {
        self.id = UUID()
        self.reason = reason
        self.summary = summary
        self.recovery = recovery
        self.rawOutput = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        self.exitCode = exitCode
    }

    /// Retrying with an admin password only helps when the failure was actually about
    /// privileges — offering it for a full disk just wastes the user's time.
    var suggestsElevation: Bool { reason == .authorizationRequired }

    var isRetryable: Bool {
        switch reason {
        case .notEligible, .versionUnavailable: return false
        default: return true
        }
    }

    var symbol: String {
        switch reason {
        case .insufficientSpace: return "internaldrive.badge.exclamationmark"
        case .authorizationRequired: return "lock.shield"
        case .userCancelled: return "slash.circle"
        case .network: return "wifi.exclamationmark"
        case .notEligible: return "exclamationmark.octagon"
        case .versionUnavailable: return "questionmark.circle"
        case .updateInProgress: return "clock.arrow.circlepath"
        case .installerMissing, .incompleteInstaller: return "externaldrive.badge.xmark"
        case .launchFailed, .unknown: return "xmark.octagon"
        }
    }

    /// Everything the classifier needs to know about the attempt that just failed.
    struct Context: Sendable {
        let version: String
        let expectedBytes: Int64
        let space: DiskSpace?

        init(version: String, expectedBytes: Int64, space: DiskSpace? = DiskSpace.current()) {
            self.version = version
            self.expectedBytes = expectedBytes
            self.space = space
        }
    }

    static func classify(output: String, exitCode: Int32?, context: Context) -> DownloadFailure {
        let raw = tail(of: output)
        let haystack = output.lowercased()
        let lastLine = meaningfulLastLine(of: output)

        if contains(haystack, ["not enough free space", "enough free space", "no space left",
                               "insufficient space", "insufficient disk", "not enough disk space",
                               "enough space", "enospc"]) {
            return DownloadFailure(
                reason: .insufficientSpace,
                summary: "Not enough free disk space.",
                recovery: spaceRecovery(context: context),
                rawOutput: raw,
                exitCode: exitCode
            )
        }

        if contains(haystack, ["must be run as root", "requires root", "not authorized",
                               "authorization", "permission denied", "operation not permitted",
                               "administrator privileges", "you must be an administrator", "eperm"]) {
            return DownloadFailure(
                reason: .authorizationRequired,
                summary: "This download needs administrator privileges.",
                recovery: "Retry with your admin password — macOS will prompt you before the download starts.",
                rawOutput: raw,
                exitCode: exitCode
            )
        }

        if contains(haystack, ["not eligible", "cannot be installed on this computer",
                               "is not supported on this", "incompatible"]) {
            return DownloadFailure(
                reason: .notEligible,
                summary: "This Mac isn't eligible for macOS \(context.version).",
                recovery: "Apple's servers rejected this installer for this hardware. Choose a version your Mac supports.",
                rawOutput: raw,
                exitCode: exitCode
            )
        }

        if contains(haystack, ["could not connect", "no internet", "network connection",
                               "the network", "timed out", "nsurlerror", "unreachable",
                               "connection was lost", "connection failure"]) {
            return DownloadFailure(
                reason: .network,
                summary: "The download couldn't reach Apple's servers.",
                recovery: "Check your internet connection and try again. Large installers also fail if the Mac sleeps mid-download.",
                rawOutput: raw,
                exitCode: exitCode
            )
        }

        if contains(haystack, ["another update", "already in progress", "is currently running",
                               "update is already"]) {
            return DownloadFailure(
                reason: .updateInProgress,
                summary: "Another software update is already running.",
                recovery: "Wait for the update in System Settings to finish, then try again.",
                rawOutput: raw,
                exitCode: exitCode
            )
        }

        if contains(haystack, ["no such installer", "unable to find", "could not find",
                               "no installer", "not available", "no matching", "invalid version",
                               "update not found", "not found"]) {
            return DownloadFailure(
                reason: .versionUnavailable,
                summary: "macOS \(context.version) is no longer offered for this Mac.",
                recovery: "Refresh the installer list — Apple removes older builds as new ones ship.",
                rawOutput: raw,
                exitCode: exitCode
            )
        }

        return DownloadFailure(
            reason: .unknown,
            summary: lastLine ?? "softwareupdate failed\(exitCode.map { " (exit \($0))" } ?? "").",
            recovery: "Open Logs for the full output, or run `softwareupdate --fetch-full-installer --full-installer-version \(context.version)` in Terminal to see the raw error.",
            rawOutput: raw,
            exitCode: exitCode
        )
    }

    static func spaceRecovery(context: Context) -> String {
        guard context.expectedBytes > 0 else {
            return "Free up space on your startup disk and try again."
        }
        let required = DiskSpace.requiredBytes(forInstallerSize: context.expectedBytes)
        var text = "Downloading macOS \(context.version) needs about \(DiskSpace.formatted(required)) free — "
        text += "\(DiskSpace.formatted(context.expectedBytes)) for the download plus the same again while it expands into /Applications."
        if let space = context.space {
            text += " You have \(DiskSpace.formatted(space.availableCapacity)) available"
            let shortfall = required - space.availableCapacity
            if shortfall > 0 {
                text += ", so free up at least \(DiskSpace.formatted(shortfall))."
            } else {
                text += "."
            }
        }
        return text
    }

    // MARK: - Private

    private static func contains(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    private static func meaningfulLastLine(of output: String) -> String? {
        output
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: "\r")))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.contains("%") }
            .last
    }

    private static func tail(of output: String, limit: Int = 4000) -> String {
        let cleaned = output
            .components(separatedBy: CharacterSet.newlines.union(CharacterSet(charactersIn: "\r")))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard cleaned.count > limit else { return cleaned }
        return "…" + String(cleaned.suffix(limit))
    }
}
