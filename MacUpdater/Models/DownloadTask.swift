import Foundation

enum DownloadState: Sendable {
    case queued
    case preparing
    case downloading(progress: Double)
    case verifying
    case completed
    case failed(error: String)
    case cancelled

    var label: String {
        switch self {
        case .queued: return "Queued"
        case .preparing: return "Preparing"
        case .downloading(let p): return String(format: "Downloading %.0f%%", p * 100)
        case .verifying: return "Verifying"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var isActive: Bool {
        switch self {
        case .queued, .preparing, .downloading, .verifying: return true
        default: return false
        }
    }

    var progress: Double? {
        if case .downloading(let p) = self { return p }
        return nil
    }
}

struct DownloadTask: Identifiable, Sendable {
    let id: UUID
    let installerVersion: String
    let installerTitle: String
    var state: DownloadState
    var startedAt: Date?
    var completedAt: Date?
    var bytesPerSecond: Double?
    var etaSeconds: Double?

    var displayName: String { "\(installerTitle) \(installerVersion)" }

    var speedFormatted: String? {
        guard let bps = bytesPerSecond, bps > 0 else { return nil }
        let mbps = bps / 1_000_000
        if mbps >= 1 {
            return String(format: "%.1f MB/s", mbps)
        }
        let kbps = bps / 1_000
        return String(format: "%.0f KB/s", kbps)
    }

    var etaFormatted: String? {
        guard let eta = etaSeconds, eta > 0 else { return nil }
        if eta < 60 { return "< 1 min" }
        let minutes = Int(eta / 60)
        if minutes < 60 { return "~\(minutes) min" }
        let hours = minutes / 60
        let mins = minutes % 60
        return "~\(hours)h \(mins)m"
    }
}
