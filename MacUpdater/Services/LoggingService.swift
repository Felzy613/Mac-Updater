import Foundation

actor LoggingService {
    static let shared = LoggingService()

    private var entries: [AppLog] = []
    private var logFileURL: URL?
    private var fileHandle: FileHandle?
    private let encoder = JSONEncoder()
    private let maxEntries = 2000

    init() {
        encoder.dateEncodingStrategy = .iso8601
        Task { await self.setupPersistence() }
    }

    func log(_ level: LogLevel, category: String, _ message: String) {
        let entry = AppLog(id: UUID(), timestamp: Date(), level: level, category: category, message: message)
        entries.append(entry)
        if entries.count > maxEntries { entries.removeFirst(entries.count - maxEntries) }
        appendToDisk(entry)

        #if DEBUG
        let prefix = entry.level.symbol
        print("[\(prefix) \(category)] \(message)")
        #endif
    }

    func getEntries(level: LogLevel? = nil, category: String? = nil, search: String = "") -> [AppLog] {
        entries.filter { entry in
            if let level, entry.level < level { return false }
            if let category, entry.category != category { return false }
            if !search.isEmpty {
                return entry.message.localizedCaseInsensitiveContains(search) ||
                       entry.category.localizedCaseInsensitiveContains(search)
            }
            return true
        }
    }

    func exportAsText() -> String {
        entries.map { e in
            let ts = e.formattedTimestamp
            return "[\(ts)] [\(e.level.label.uppercased())] [\(e.category)] \(e.message)"
        }.joined(separator: "\n")
    }

    func clearAll() {
        entries.removeAll()
        if let url = logFileURL {
            try? FileManager.default.removeItem(at: url)
            fileHandle = nil
            setupPersistence()
        }
    }

    func clearOldEntries(retentionDays: Int) {
        let cutoff = Date().addingTimeInterval(-Double(retentionDays) * 86400)
        entries.removeAll { $0.timestamp < cutoff }
    }

    private func setupPersistence() {
        guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        let dir = support.appendingPathComponent("MacUpdater/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("app.jsonl")
        logFileURL = url

        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        fileHandle = try? FileHandle(forWritingTo: url)
        fileHandle?.seekToEndOfFile()

        loadFromDisk(url: url)
    }

    private func loadFromDisk(url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        entries = lines.compactMap { line in
            try? decoder.decode(AppLog.self, from: Data(line))
        }
    }

    private func appendToDisk(_ entry: AppLog) {
        guard let handle = fileHandle,
              let data = try? encoder.encode(entry) else { return }
        var line = data
        line.append(UInt8(ascii: "\n"))
        handle.write(line)
    }
}

func logDebug(_ message: String, category: String = "App") {
    Task { await LoggingService.shared.log(.debug, category: category, message) }
}

func logInfo(_ message: String, category: String = "App") {
    Task { await LoggingService.shared.log(.info, category: category, message) }
}

func logWarning(_ message: String, category: String = "App") {
    Task { await LoggingService.shared.log(.warning, category: category, message) }
}

func logError(_ message: String, category: String = "App") {
    Task { await LoggingService.shared.log(.error, category: category, message) }
}
