import Testing
import Foundation
@testable import HiddenStart

@Suite("SettingsStore Tests")
struct SettingsStoreTests {

    private func createTempFileURL() -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return tempDir.appendingPathComponent("apps.json")
    }

    @Test("Loading non-existent file initializes empty apps array without error")
    @MainActor
    func testLoadNonExistentFile() throws {
        let fileURL = createTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = SettingsStore(fileURL: fileURL)
        try store.load()

        #expect(store.apps.isEmpty)
    }

    @Test("Saving and reloading managed apps persists to disk as JSON")
    @MainActor
    func testSaveAndLoad() throws {
        let fileURL = createTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = SettingsStore(fileURL: fileURL)
        let app1 = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app", customArguments: "--start-minimized")
        let app2 = ManagedApp(name: "Steam", bundlePath: "/Applications/Steam.app", customArguments: "-silent")

        store.apps = [app1, app2]
        try store.save()

        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        // Create a new store instance pointing to the same file
        let reloadedStore = SettingsStore(fileURL: fileURL)
        try reloadedStore.load()

        #expect(reloadedStore.apps.count == 2)
        #expect(reloadedStore.apps[0].name == "Discord")
        #expect(reloadedStore.apps[0].customArguments == "--start-minimized")
        #expect(reloadedStore.apps[1].name == "Steam")
        #expect(reloadedStore.apps[1].customArguments == "-silent")
    }

    @Test("Adding and removing apps updates the store and persists changes")
    @MainActor
    func testAddAndRemove() throws {
        let fileURL = createTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let store = SettingsStore(fileURL: fileURL)
        let app = ManagedApp(name: "Slack", bundlePath: "/Applications/Slack.app")

        try store.add(app)
        #expect(store.apps.count == 1)
        #expect(store.apps.first?.id == app.id)

        // Reload to verify it was saved automatically on add
        let reloadedStore = SettingsStore(fileURL: fileURL)
        try reloadedStore.load()
        #expect(reloadedStore.apps.count == 1)

        try store.remove(withId: app.id)
        #expect(store.apps.isEmpty)

        try reloadedStore.load()
        #expect(reloadedStore.apps.isEmpty)
    }

    @Test("Loading legacy JSON schema migrates to modern ManagedApp models with defaults")
    @MainActor
    func testMigrationFromLegacyJSON() throws {
        let fileURL = createTempFileURL()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Legacy format using "path" instead of "bundlePath", "arguments" instead of "customArguments", and omitting id
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

        let store = SettingsStore(fileURL: fileURL)
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
}
