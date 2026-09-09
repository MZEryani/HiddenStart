import Foundation
import Combine

@MainActor
public final class SettingsStore: ObservableObject, SettingsStoring {
    @Published public var apps: [ManagedApp] = []

    public let fileURL: URL
    private let fileManager: FileManager
    private let userDefaults: UserDefaults

    public static var defaultStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("HiddenStart/apps.json")
    }

    public init(
        fileURL: URL = SettingsStore.defaultStorageURL,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.userDefaults = userDefaults
    }

    public static let discordMigrationKey = "hasMigratedDiscordPresetArguments"

    public func load() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            apps = []
            return
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        var decodedApps = try decoder.decode([ManagedApp].self, from: data)

        if !userDefaults.bool(forKey: Self.discordMigrationKey) {
            var didMigrate = false
            for i in 0..<decodedApps.count {
                if decodedApps[i].isDiscord {
                    let tokens = decodedApps[i].customArguments.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                    if tokens.contains("--start-minimized") {
                        let remainingTokens = tokens.filter { $0 != "--start-minimized" }
                        decodedApps[i].customArguments = remainingTokens.joined(separator: " ")
                        didMigrate = true
                    }
                }
            }
            userDefaults.set(true, forKey: Self.discordMigrationKey)
            if didMigrate {
                self.apps = decodedApps
                try? save()
                return
            }
        }

        self.apps = decodedApps
    }

    public func save() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(apps)
        try data.write(to: fileURL, options: .atomic)
    }

    public func add(_ app: ManagedApp) throws {
        apps.append(app)
        try save()
    }

    public func remove(withId id: UUID) throws {
        apps.removeAll { $0.id == id }
        try save()
    }

    public func update(_ app: ManagedApp) throws {
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            apps[index] = app
            try save()
        }
    }
}
