import Foundation

public enum LogLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case debug, info, warning, error

    private static let order: [LogLevel] = [.debug, .info, .warning, .error]

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        let li = order.firstIndex(of: lhs) ?? 0
        let ri = order.firstIndex(of: rhs) ?? 0
        return li < ri
    }

    public var symbol: String {
        switch self {
        case .debug: return "⚙"
        case .info: return "ℹ"
        case .warning: return "⚠"
        case .error: return "✕"
        }
    }

    public var label: String { rawValue.capitalized }
}

public struct AppLog: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let level: LogLevel
    public let category: String
    public let message: String

    public init(id: UUID, timestamp: Date, level: LogLevel, category: String, message: String) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
    }

    public var formattedTimestamp: String {
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss.SSS"
        return fmt.string(from: timestamp)
    }
}
