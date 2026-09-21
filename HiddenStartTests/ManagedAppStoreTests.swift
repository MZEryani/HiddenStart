import Testing
import Foundation
@testable import HiddenStart

@Suite("ManagedAppStore Tests")
@MainActor
struct ManagedAppStoreTests {

    private func createTempFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return tempDir.appendingPathComponent("apps.json")
    }

    private func createSimulatedAppBundle(name: String, bundleId: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleURL = tempDir.appendingPathComponent("\(name).app")
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let infoPlistData = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleName": name,
                "CFBundleDisplayName": name,
                "CFBundleIdentifier": bundleId
            ],
            format: .xml,
            options: 0
        )
        try infoPlistData.write(to: contentsURL.appendingPathComponent("Info.plist"))
        return bundleURL
    }

    @Test("Loading non-existent file initializes empty apps array without error")
    func testLoadNonExistentFile() throws {
        let fileURL = createTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = ManagedAppStore(fileURL: fileURL)
        try store.load()

        #expect(store.apps.isEmpty)
    }

    @Test("Saving and reloading managed apps persists to disk as JSON")
    func testSaveAndLoad() throws {
        let fileURL = createTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let userDefaults = UserDefaults(suiteName: UUID().uuidString)!
        userDefaults.set(true, forKey: "hasMigratedDiscordPresetArguments")
        let store = ManagedAppStore(
            fileURL: fileURL,
            userDefaults: userDefaults,
            fileExistsChecker: { _ in true }
        )
        let app1 = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app", customArguments: "--start-minimized")
        let app2 = ManagedApp(name: "Steam", bundlePath: "/Applications/Steam.app", customArguments: "-silent")

        try store.addDirectlyForTesting(app1)
        try store.addDirectlyForTesting(app2)

        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        let reloadedStore = ManagedAppStore(
            fileURL: fileURL,
            userDefaults: userDefaults,
            fileExistsChecker: { _ in true }
        )
        try reloadedStore.load()

        #expect(reloadedStore.apps.count == 2)
        #expect(reloadedStore.apps[0].name == "Discord")
        #expect(reloadedStore.apps[0].customArguments == "--start-minimized")
        #expect(reloadedStore.apps[1].name == "Steam")
        #expect(reloadedStore.apps[1].customArguments == "-silent")
    }

    @Test("Adding and removing apps updates the store and persists changes")
    func testAddAndRemove() throws {
        let fileURL = createTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = ManagedAppStore(fileURL: fileURL, fileExistsChecker: { _ in true })
        let app = ManagedApp(name: "Slack", bundlePath: "/Applications/Slack.app")

        try store.addDirectlyForTesting(app)
        #expect(store.apps.count == 1)
        #expect(store.apps.first?.id == app.id)

        let reloadedStore = ManagedAppStore(fileURL: fileURL, fileExistsChecker: { _ in true })
        try reloadedStore.load()
        #expect(reloadedStore.apps.count == 1)

        try store.remove(withId: app.id)
        #expect(store.apps.isEmpty)

        try reloadedStore.load()
        #expect(reloadedStore.apps.isEmpty)
    }

    @Test("addApp(at: URL) extracts bundle metadata and maps preset configuration")
    func testAddAppAtURLWithPreset() throws {
        let fileURL = createTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let steamBundleURL = try createSimulatedAppBundle(name: "Steam", bundleId: "com.valvesoftware.steam")
        defer { try? FileManager.default.removeItem(at: steamBundleURL.deletingLastPathComponent()) }

        let store = ManagedAppStore(fileURL: fileURL, fileExistsChecker: { _ in true })
        let addedApp = try store.addApp(at: steamBundleURL)

        #expect(store.apps.count == 1)
        #expect(addedApp.name == "Steam")
        #expect(addedApp.bundleIdentifier == "com.valvesoftware.steam")
        #expect(addedApp.bundlePath == steamBundleURL.path)
        #expect(addedApp.customArguments == "-silent")
        #expect(addedApp.waitForInternet == true)
        #expect(addedApp.launchHidden == true)
        #expect(store.isMissing(appId: addedApp.id) == false)

        // Verify it was persisted to disk
        let reloadedStore = ManagedAppStore(fileURL: fileURL, fileExistsChecker: { _ in true })
        try reloadedStore.load()
        #expect(reloadedStore.apps.count == 1)
        #expect(reloadedStore.apps.first?.name == "Steam")
        #expect(reloadedStore.apps.first?.customArguments == "-silent")
    }

    @Test("addApp(at: URL) for Discord applies empty arguments and enables launchHidden")
    func testAddAppAtURLDiscordPreset() throws {
        let fileURL = createTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let discordBundleURL = try createSimulatedAppBundle(name: "Discord", bundleId: "com.hnc.Discord")
        defer { try? FileManager.default.removeItem(at: discordBundleURL.deletingLastPathComponent()) }

        let store = ManagedAppStore(fileURL: fileURL, fileExistsChecker: { _ in true })
        let addedApp = try store.addApp(at: discordBundleURL)

        #expect(addedApp.name == "Discord")
        #expect(addedApp.bundleIdentifier == "com.hnc.Discord")
        #expect(addedApp.customArguments == "")
        #expect(addedApp.launchHidden == true)
        #expect(addedApp.waitForInternet == true)
    }

    @Test("Loading legacy JSON schema migrates to modern ManagedApp models with defaults")
    func testMigrationFromLegacyJSON() throws {
        let fileURL = createTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let legacyJSON = """
        [
            {
                "name": "Legacy Discord",
                "path": "/Applications/Discord.app",
                "arguments": "--start-minimized"
            }
        ]
        """
        try legacyJSON.data(using: .utf8)!.write(to: fileURL)

        let store = ManagedAppStore(fileURL: fileURL, fileExistsChecker: { _ in true })
        try store.load()

        #expect(store.apps.count == 1)
        let migratedApp = store.apps[0]
        #expect(migratedApp.name == "Legacy Discord")
        #expect(migratedApp.bundlePath == "/Applications/Discord.app")
        #expect(migratedApp.customArguments == "--start-minimized")
        #expect(migratedApp.delaySeconds == 10)
        #expect(migratedApp.waitForInternet == true)
        #expect(migratedApp.launchHidden == true)
        #expect(migratedApp.isEnabled == true)
    }

    @Test("Loading store with legacy Discord entry migrates --start-minimized to empty string")
    func testDiscordLegacyStartMinimizedMigration() throws {
        let fileURL = createTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let discordJSON = """
        [
            {
                "id": "\(UUID().uuidString)",
                "name": "Discord",
                "bundlePath": "/Applications/Discord.app",
                "bundleIdentifier": "com.hnc.Discord",
                "customArguments": "--start-minimized",
                "delaySeconds": 10,
                "waitForInternet": true,
                "launchHidden": true,
                "isEnabled": true,
                "sortOrder": 0
            }
        ]
        """
        try discordJSON.data(using: .utf8)!.write(to: fileURL)

        let userDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = ManagedAppStore(
            fileURL: fileURL,
            userDefaults: userDefaults,
            fileExistsChecker: { _ in true }
        )
        try store.load()

        #expect(store.apps.count == 1)
        #expect(store.apps[0].customArguments == "")
        #expect(userDefaults.bool(forKey: "hasMigratedDiscordPresetArguments") == true)
    }

    @Test("Loading store with legacy Discord entry migrates --start-minimized while preserving user arguments")
    func testDiscordLegacyStartMinimizedMigrationPreservesUserArguments() throws {
        let fileURL = createTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let discordJSON = """
        [
            {
                "id": "\(UUID().uuidString)",
                "name": "Discord",
                "bundlePath": "/Applications/Discord.app",
                "bundleIdentifier": "com.hnc.Discord",
                "customArguments": "--start-minimized --disable-smooth-scrolling",
                "delaySeconds": 10,
                "waitForInternet": true,
                "launchHidden": true,
                "isEnabled": true,
                "sortOrder": 0
            }
        ]
        """
        try discordJSON.data(using: .utf8)!.write(to: fileURL)

        let userDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = ManagedAppStore(
            fileURL: fileURL,
            userDefaults: userDefaults,
            fileExistsChecker: { _ in true }
        )
        try store.load()

        #expect(store.apps.count == 1)
        #expect(store.apps[0].customArguments == "--disable-smooth-scrolling")
        #expect(userDefaults.bool(forKey: "hasMigratedDiscordPresetArguments") == true)

        var modifiedApp = store.apps[0]
        modifiedApp.customArguments = "--user-updated-flag"
        try store.update(modifiedApp)

        let reloadedStore = ManagedAppStore(
            fileURL: fileURL,
            userDefaults: userDefaults,
            fileExistsChecker: { _ in true }
        )
        try reloadedStore.load()
        #expect(reloadedStore.apps[0].customArguments == "--user-updated-flag")
    }

    @Test("Moved app path heals on load using bundle identifier and updates bundlePath")
    func testMovedAppPathHealsOnLoad() throws {
        let fileURL = createTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let mockWorkspace = MockWorkspaceManager()
        let newURL = URL(fileURLWithPath: "/Users/test/Applications/Discord.app")
        mockWorkspace.applicationURLs["com.hnc.Discord"] = newURL

        let store = ManagedAppStore(
            fileURL: fileURL,
            workspaceManager: mockWorkspace,
            fileExistsChecker: { path in path == "/Users/test/Applications/Discord.app" }
        )

        let app = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/OldDiscord.app",
            bundleIdentifier: "com.hnc.Discord"
        )
        try store.addDirectlyForTesting(app)

        #expect(store.isMissing(appId: app.id) == false)
        #expect(store.apps[0].bundlePath == "/Users/test/Applications/Discord.app")

        // Reload to verify healed path was persisted to disk
        let reloadedStore = ManagedAppStore(
            fileURL: fileURL,
            workspaceManager: mockWorkspace,
            fileExistsChecker: { path in path == "/Users/test/Applications/Discord.app" }
        )
        try reloadedStore.load()

        #expect(reloadedStore.apps[0].bundlePath == "/Users/test/Applications/Discord.app")
        #expect(reloadedStore.isMissing(appId: app.id) == false)
    }

    @Test("Missing app without bundle identifier returns missing")
    func testMissingAppWithoutBundleIdentifier() throws {
        let fileURL = createTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let mockWorkspace = MockWorkspaceManager()
        let store = ManagedAppStore(
            fileURL: fileURL,
            workspaceManager: mockWorkspace,
            fileExistsChecker: { _ in false }
        )

        let app = ManagedApp(
            name: "CustomApp",
            bundlePath: "/Applications/CustomApp.app",
            bundleIdentifier: nil
        )
        try store.addDirectlyForTesting(app)

        #expect(store.isMissing(appId: app.id) == true)
    }

    @Test("Missing app with unresolvable bundle identifier returns missing")
    func testMissingAppWithUnresolvableBundleIdentifier() throws {
        let fileURL = createTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let mockWorkspace = MockWorkspaceManager()
        let store = ManagedAppStore(
            fileURL: fileURL,
            workspaceManager: mockWorkspace,
            fileExistsChecker: { _ in false }
        )

        let app = ManagedApp(
            name: "DeletedApp",
            bundlePath: "/Applications/DeletedApp.app",
            bundleIdentifier: "com.example.deleted"
        )
        try store.addDirectlyForTesting(app)

        #expect(store.isMissing(appId: app.id) == true)
    }

    @Test("Missing app where workspace returns URL that doesn't exist on disk returns missing")
    func testMissingAppWhereWorkspaceURLDoesNotExist() throws {
        let fileURL = createTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let mockWorkspace = MockWorkspaceManager()
        mockWorkspace.applicationURLs["com.example.phantom"] = URL(fileURLWithPath: "/Applications/Phantom.app")

        let store = ManagedAppStore(
            fileURL: fileURL,
            workspaceManager: mockWorkspace,
            fileExistsChecker: { _ in false }
        )

        let app = ManagedApp(
            name: "Phantom",
            bundlePath: "/Applications/OldPhantom.app",
            bundleIdentifier: "com.example.phantom"
        )
        try store.addDirectlyForTesting(app)

        #expect(store.isMissing(appId: app.id) == true)
    }

    @Test("refreshAppHealth heals moved apps and backfills presets")
    func testRefreshAppHealthHealsAndBackfills() throws {
        let fileURL = createTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let validApp = ManagedApp(
            name: "ValidApp",
            bundlePath: "/Applications/ValidApp.app",
            bundleIdentifier: "com.example.valid"
        )
        let movedApp = ManagedApp(
            name: "MovedApp",
            bundlePath: "/Applications/OldMovedApp.app",
            bundleIdentifier: "com.example.moved"
        )
        let steamApp = ManagedApp(
            name: "Steam",
            bundlePath: "/Applications/Steam.app",
            bundleIdentifier: "com.valvesoftware.steam",
            customArguments: ""
        )

        let mockWorkspace = MockWorkspaceManager()
        mockWorkspace.applicationURLs["com.example.moved"] = URL(fileURLWithPath: "/Applications/NewMovedApp.app")

        let store = ManagedAppStore(
            fileURL: fileURL,
            workspaceManager: mockWorkspace,
            fileExistsChecker: { path in
                path == "/Applications/ValidApp.app" ||
                path == "/Applications/NewMovedApp.app" ||
                path == "/Applications/Steam.app"
            }
        )

        try store.addDirectlyForTesting(validApp)
        try store.addDirectlyForTesting(movedApp)
        try store.addDirectlyForTesting(steamApp)

        store.refreshAppHealth()

        #expect(store.apps.count == 3)
        #expect(store.apps[0].bundlePath == "/Applications/ValidApp.app")
        #expect(store.apps[1].bundlePath == "/Applications/NewMovedApp.app")
        #expect(store.apps[2].customArguments == "-silent")
        #expect(store.isMissing(appId: validApp.id) == false)
        #expect(store.isMissing(appId: movedApp.id) == false)
        #expect(store.isMissing(appId: steamApp.id) == false)
    }

    @Test("refreshAppHealth preserves user-configured customArguments without overwriting")
    func testPreservesUserArguments() throws {
        let fileURL = createTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let userConfiguredApp = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            bundleIdentifier: "com.hnc.Discord",
            customArguments: "--custom-user-arg"
        )

        let store = ManagedAppStore(
            fileURL: fileURL,
            fileExistsChecker: { _ in true }
        )

        try store.addDirectlyForTesting(userConfiguredApp)
        store.refreshAppHealth()

        #expect(store.apps.count == 1)
        #expect(store.apps[0].customArguments == "--custom-user-arg")
    }
}
