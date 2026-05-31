import Foundation
import Combine

@MainActor
final class LogViewerViewModel: ObservableObject {
    @Published private(set) var allEntries: [AppLog] = []
    @Published var filterLevel: LogLevel? = nil
    @Published var filterCategory: String? = nil
    @Published var searchText: String = ""

    var filteredEntries: [AppLog] {
        allEntries.reversed().filter { entry in
            if let level = filterLevel, entry.level < level { return false }
            if let cat = filterCategory, entry.category != cat { return false }
            if !searchText.isEmpty {
                return entry.message.localizedCaseInsensitiveContains(searchText) ||
                       entry.category.localizedCaseInsensitiveContains(searchText)
            }
            return true
        }
    }

    var availableCategories: [String] {
        Array(Set(allEntries.map(\.category))).sorted()
    }

    func refresh() {
        Task {
            let entries = await LoggingService.shared.getEntries()
            allEntries = entries
        }
    }

    func exportAsText() -> String {
        filteredEntries.map { e in
            "[\(e.formattedTimestamp)] [\(e.level.label.uppercased())] [\(e.category)] \(e.message)"
        }.joined(separator: "\n")
    }

    func clearLogs() {
        Task {
            await LoggingService.shared.clearAll()
            allEntries = []
        }
    }
}
