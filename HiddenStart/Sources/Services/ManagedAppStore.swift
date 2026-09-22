import Foundation
import Combine

@MainActor
public final class ManagedAppStore: ObservableObject, ManagedAppStoring {
    @Published public private(set) var apps: [ManagedApp] = []

    public var appsPublisher: AnyPublisher<[ManagedApp], Never> {
        $apps.eraseToAnyPublisher()
    }

    public let fileURL: URL
    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let workspaceManager: WorkspaceManaging
    private let fileExistsChecker: (String) -> Bool
    private var missingIds: Set<UUID> = []

    public static let discordMigrationKey = "hasMigratedDiscordPresetArguments"

    public static var defaultStorageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("HiddenStart/apps.json")
    }

    public init(
        fileURL: URL = ManagedAppStore.defaultStorageURL,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        workspaceManager: WorkspaceManaging = SystemWorkspaceManager(),
        fileExistsChecker: ((String) -> Bool)? = nil
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        self.workspaceManager = workspaceManager
        if let fileExistsChecker {
            self.fileExistsChecker = fileExistsChecker
        } else {
            self.fileExistsChecker = { fileManager.fileExists(atPath: $0) }
        }
    }

    public func load() throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            apps = []
            missingIds.removeAll()
            return
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        var decodedApps = try decoder.decode([ManagedApp].self, from: data)

        var didMutate = false

        if !userDefaults.bool(forKey: Self.discordMigrationKey) {
            for i in 0..<decodedApps.count {
                if decodedApps[i].isDiscord {
                    let tokens = decodedApps[i].customArguments.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                    if tokens.contains("--start-minimized") {
                        let remainingTokens = tokens.filter { $0 != "--start-minimized" }
                        decodedApps[i].customArguments = remainingTokens.joined(separator: " ")
                        didMutate = true
                    }
                }
            }
            userDefaults.set(true, forKey: Self.discordMigrationKey)
        }

        missingIds.removeAll()

        for i in 0..<decodedApps.count {
            if evaluateAndHeal(&decodedApps[i]) {
                didMutate = true
            }
        }

        self.apps = decodedApps

        if didMutate {
            try save()
        }
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

    public func addApp(at url: URL) throws -> ManagedApp {
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let bundleIdentifier = bundle?.bundleIdentifier

        var newApp = AppPreset.makeManagedApp(
            name: name,
            bundlePath: url.path,
            bundleIdentifier: bundleIdentifier
        )

        evaluateAndHeal(&newApp)
        apps.append(newApp)

        try save()
        return newApp
    }

    internal func addDirectlyForTesting(_ app: ManagedApp) throws {
        var appToAdd = app
        evaluateAndHeal(&appToAdd)
        apps.append(appToAdd)
        try save()
    }

    public func remove(withId id: UUID) throws {
        apps.removeAll { $0.id == id }
        missingIds.remove(id)
        try save()
    }

    public func update(_ app: ManagedApp) throws {
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            var appToUpdate = app
            evaluateAndHeal(&appToUpdate)
            apps[index] = appToUpdate
            try save()
        }
    }

    public func isMissing(appId: UUID) -> Bool {
        missingIds.contains(appId)
    }

    func refreshAppHealth() {
        var didMutate = false
        for i in 0..<apps.count {
            if evaluateAndHeal(&apps[i]) {
                didMutate = true
            }
        }

        if didMutate {
            try? save()
        }
    }

    @discardableResult
    private func evaluateAndHeal(_ app: inout ManagedApp) -> Bool {
        var didHeal = false

        if !app.bundlePath.isEmpty && fileExistsChecker(app.bundlePath) {
            missingIds.remove(app.id)
        } else if let bundleId = app.bundleIdentifier, !bundleId.isEmpty,
                  let resolvedURL = workspaceManager.urlForApplication(withBundleIdentifier: bundleId),
                  fileExistsChecker(resolvedURL.path) {
            app.bundlePath = resolvedURL.path
            missingIds.remove(app.id)
            didHeal = true
        } else {
            missingIds.insert(app.id)
        }

        if app.customArguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let defaultArgs = AppPreset.defaultArguments(forBundleId: app.bundleIdentifier) {
            app.customArguments = defaultArgs
            didHeal = true
        }

        return didHeal
    }
}
