import Foundation
import Combine

@MainActor
public final class SettingsStore: ObservableObject, SettingsStoring {
    @Published public var apps: [ManagedApp] = []

    public let fileURL: URL
    private let fileManager: FileManager

    public static var defaultStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("HiddenStart/apps.json")
    }

    public init(
        fileURL: URL = SettingsStore.defaultStorageURL,
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    public func load() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            apps = []
            return
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        apps = try decoder.decode([ManagedApp].self, from: data)
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
