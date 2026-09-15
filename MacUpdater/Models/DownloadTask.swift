import Foundation
import MacUpdaterCore

enum DownloadState: Sendable, Equatable {
    case queued
    /// `softwareupdate` is scanning Apple's catalogue; nothing is downloading yet.
    case preparing
    case downloading(progress: Double)
    /// The package has been fetched and is being expanded into /Applications.
    case installing(progress: Double?)
    case verifying
    case completed
    case failed(DownloadFailure)
    case cancelled

    var label: String {
        switch self {
        case .queued: return "Waiting"
        case .preparing: return "Looking up installer…"
        case .downloading(let p): return String(format: "Downloading %.0f%%", p * 100)
        case .installing(let p):
            guard let p else { return "Expanding installer…" }
            return String(format: "Expanding installer %.0f%%", p * 100)
        case .verifying: return "Checking /Applications"
        case .completed: return "Ready to install"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var isActive: Bool {
        switch self {
        case .queued, .preparing, .downloading, .installing, .verifying: return true
        default: return false
        }
    }

    var isFinished: Bool { !isActive }

    var progress: Double? {
        switch self {
        case .downloading(let p): return p
        case .installing(let p): return p
        default: return nil
        }
    }

    var failure: DownloadFailure? {
        if case .failed(let failure) = self { return failure }
        return nil
    }
}

struct DownloadTask: Identifiable, Sendable {
    let id: UUID
    let installerVersion: String
    let installerTitle: String
    /// Download size reported by `softwareupdate --list-full-installers`; drives the
    /// space pre-flight, the fallback progress bar and the ETA.
    let expectedBytes: Int64
    var state: DownloadState
    var startedAt: Date?
    var completedAt: Date?
    var bytesPerSecond: Double?
    var etaSeconds: Double?
    /// Where the finished installer landed, once verification has found it.
    var installerURL: URL?
    /// Set when nothing has been written to disk for several minutes.
    var isStalled = false
    /// True after the user has chosen to ignore the disk-space pre-flight for this task.
    var spaceCheckOverridden = false
    var usedElevation = false

    var displayName: String { "\(installerTitle) \(installerVersion)" }

    var sizeFormatted: String? {
        guard expectedBytes > 0 else { return nil }
        return DiskSpace.formatted(expectedBytes)
    }

    var speedFormatted: String? {
        guard let bps = bytesPerSecond, bps > 0 else { return nil }
        return "\(DiskSpace.formatted(Int64(bps)))/s"
    }

    var etaFormatted: String? {
        guard let eta = etaSeconds, eta > 0, eta.isFinite else { return nil }
        if eta < 60 { return "< 1 min" }
        let minutes = Int(eta / 60)
        if minutes < 60 { return "~\(minutes) min" }
        return "~\(minutes / 60)h \(minutes % 60)m"
    }

    var duration: TimeInterval? {
        guard let startedAt else { return nil }
        return (completedAt ?? Date()).timeIntervalSince(startedAt)
    }
}
