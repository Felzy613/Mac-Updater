import Foundation

public struct SharedSettings: Codable, Sendable {
    public var refreshIntervalSeconds: Double
    public var notificationsEnabled: Bool

    public init(refreshIntervalSeconds: Double = 43200, notificationsEnabled: Bool = true) {
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.notificationsEnabled = notificationsEnabled
    }
}

public struct KnownUpgrades: Codable, Sendable {
    public var notifiedVersions: [String]

    public init(notifiedVersions: [String] = []) {
        self.notifiedVersions = notifiedVersions
    }
}

/// On-disk state shared between the main app and the background helper (different bundle IDs,
/// so UserDefaults can't be shared between them).
public enum SharedState {
    private static var stateDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("MacUpdater/state", isDirectory: true)
    }

    private static var settingsURL: URL { stateDirectory.appendingPathComponent("settings.json") }
    private static var knownUpgradesURL: URL { stateDirectory.appendingPathComponent("known-upgrades.json") }

    public static func loadSettings() -> SharedSettings {
        load(from: settingsURL) ?? SharedSettings()
    }

    public static func saveSettings(_ settings: SharedSettings) {
        save(settings, to: settingsURL)
    }

    public static func loadKnownUpgrades() -> KnownUpgrades {
        load(from: knownUpgradesURL) ?? KnownUpgrades()
    }

    public static func saveKnownUpgrades(_ upgrades: KnownUpgrades) {
        save(upgrades, to: knownUpgradesURL)
    }

    private static func load<T: Decodable>(from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func save<T: Encodable>(_ value: T, to url: URL) {
        try? FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
