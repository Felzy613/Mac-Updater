import Foundation

enum LogLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case debug, info, warning, error

    private static let order: [LogLevel] = [.debug, .info, .warning, .error]

    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        let li = order.firstIndex(of: lhs) ?? 0
        let ri = order.firstIndex(of: rhs) ?? 0
        return li < ri
    }

    var symbol: String {
        switch self {
        case .debug: return "⚙"
        case .info: return "ℹ"
        case .warning: return "⚠"
        case .error: return "✕"
        }
    }

    var label: String { rawValue.capitalized }
}

struct AppLog: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let category: String
    let message: String

    var formattedTimestamp: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        return fmt.string(from: timestamp)
    }
}
