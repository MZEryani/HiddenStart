import Testing
import Foundation
@testable import HiddenStart

@Suite("AppResolver Tests")
@MainActor
struct AppResolverTests {
    @Test("Valid app path returns valid result without modification")
    func testValidAppPath() {
        let mockWorkspace = MockWorkspaceManager()
        let resolver = AppResolver(
            workspaceManager: mockWorkspace,
            fileExistsChecker: { path in path == "/Applications/Discord.app" }
        )

        let app = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            bundleIdentifier: "com.hnc.Discord"
        )

        let result = resolver.resolveApp(app)
        #expect(result == .valid(app))
    }

    @Test("Moved app path heals using bundle identifier and updates bundlePath")
    func testMovedAppPathHeals() {
        let mockWorkspace = MockWorkspaceManager()
        let newURL = URL(fileURLWithPath: "/Users/test/Applications/Discord.app")
        mockWorkspace.applicationURLs["com.hnc.Discord"] = newURL

        let resolver = AppResolver(
            workspaceManager: mockWorkspace,
            fileExistsChecker: { path in path == "/Users/test/Applications/Discord.app" }
        )

        let app = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            bundleIdentifier: "com.hnc.Discord"
        )

        let result = resolver.resolveApp(app)
        switch result {
        case .healed(let healedApp):
            #expect(healedApp.id == app.id)
            #expect(healedApp.bundlePath == "/Users/test/Applications/Discord.app")
            #expect(healedApp.bundleIdentifier == "com.hnc.Discord")
        default:
            Issue.record("Expected healed result, got \(result)")
        }
    }

    @Test("Missing app without bundle identifier returns missing")
    func testMissingAppWithoutBundleIdentifier() {
        let mockWorkspace = MockWorkspaceManager()
        let resolver = AppResolver(
            workspaceManager: mockWorkspace,
            fileExistsChecker: { _ in false }
        )

        let app = ManagedApp(
            name: "CustomApp",
            bundlePath: "/Applications/CustomApp.app",
            bundleIdentifier: nil
        )

        let result = resolver.resolveApp(app)
        #expect(result == .missing(app))
    }

    @Test("Missing app with unresolvable bundle identifier returns missing")
    func testMissingAppWithUnresolvableBundleIdentifier() {
        let mockWorkspace = MockWorkspaceManager()
        let resolver = AppResolver(
            workspaceManager: mockWorkspace,
            fileExistsChecker: { _ in false }
        )

        let app = ManagedApp(
            name: "DeletedApp",
            bundlePath: "/Applications/DeletedApp.app",
            bundleIdentifier: "com.example.deleted"
        )

        let result = resolver.resolveApp(app)
        #expect(result == .missing(app))
    }

    @Test("Missing app where workspace returns URL that doesn't exist on disk returns missing")
    func testMissingAppWhereWorkspaceURLDoesNotExist() {
        let mockWorkspace = MockWorkspaceManager()
        mockWorkspace.applicationURLs["com.example.phantom"] = URL(fileURLWithPath: "/Applications/Phantom.app")

        let resolver = AppResolver(
            workspaceManager: mockWorkspace,
            fileExistsChecker: { _ in false }
        )

        let app = ManagedApp(
            name: "Phantom",
            bundlePath: "/Applications/OldPhantom.app",
            bundleIdentifier: "com.example.phantom"
        )

        let result = resolver.resolveApp(app)
        #expect(result == .missing(app))
    }

    @Test("resolveAndHeal updates store when an app is healed")
    func testResolveAndHealUpdatesStore() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storeURL = tempDir.appendingPathComponent("apps.json")
        let store = SettingsStore(fileURL: storeURL)

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
        let missingApp = ManagedApp(
            name: "MissingApp",
            bundlePath: "/Applications/MissingApp.app",
            bundleIdentifier: "com.example.missing"
        )

        try store.add(validApp)
        try store.add(movedApp)
        try store.add(missingApp)

        let mockWorkspace = MockWorkspaceManager()
        mockWorkspace.applicationURLs["com.example.moved"] = URL(fileURLWithPath: "/Applications/NewMovedApp.app")

        let resolver = AppResolver(
            workspaceManager: mockWorkspace,
            fileExistsChecker: { path in
                path == "/Applications/ValidApp.app" || path == "/Applications/NewMovedApp.app"
            }
        )

        let resolved = resolver.resolveAndHeal(apps: store.apps, store: store)

        #expect(resolved.count == 3)
        #expect(resolved[0].bundlePath == "/Applications/ValidApp.app")
        #expect(resolved[1].bundlePath == "/Applications/NewMovedApp.app")
        #expect(resolved[2].bundlePath == "/Applications/MissingApp.app")

        // Verify store was updated
        let storeMovedApp = store.apps.first { $0.id == movedApp.id }
        #expect(storeMovedApp?.bundlePath == "/Applications/NewMovedApp.app")

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("AppPreset recognizes modern Discord bundle identifier com.hnc.discord case-insensitively")
    func testModernDiscordPresetRecognition() {
        let presetConfig = AppPreset.knownPresets["com.hnc.discord"]
        #expect(presetConfig != nil)
        #expect(presetConfig?.customArguments == "")
        #expect(presetConfig?.waitForInternet == true)
        #expect(presetConfig?.launchHidden == true)

        let defaultArgs = AppPreset.defaultArguments(forBundleId: "COM.HNC.DISCORD")
        #expect(defaultArgs == nil)

        let managedApp = AppPreset.makeManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            bundleIdentifier: "com.hnc.Discord"
        )
        #expect(managedApp.customArguments == "")
        #expect(managedApp.waitForInternet == true)
        #expect(managedApp.launchHidden == true)
    }

    @Test("resolveAndHeal backfills empty customArguments for existing app with preset and persists to store")
    func testResolveAndHealBackfillsEmptyPresetArguments() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storeURL = tempDir.appendingPathComponent("apps.json")
        let store = SettingsStore(fileURL: storeURL)

        // Existing Steam app saved without arguments
        let existingSteam = ManagedApp(
            name: "Steam",
            bundlePath: "/Applications/Steam.app",
            bundleIdentifier: "com.valvesoftware.steam",
            customArguments: ""
        )
        // Existing app with custom user-supplied arguments that should NOT be overwritten
        let customApp = ManagedApp(
            name: "Steam Custom",
            bundlePath: "/Applications/Steam.app",
            bundleIdentifier: "com.valvesoftware.steam",
            customArguments: "--custom-flag"
        )

        try store.add(existingSteam)
        try store.add(customApp)

        let mockWorkspace = MockWorkspaceManager()
        let resolver = AppResolver(
            workspaceManager: mockWorkspace,
            fileExistsChecker: { $0 == "/Applications/Steam.app" }
        )

        let resolved = resolver.resolveAndHeal(apps: store.apps, store: store)

        #expect(resolved.count == 2)
        #expect(resolved[0].customArguments == "-silent")
        #expect(resolved[1].customArguments == "--custom-flag")

        let storedSteam = store.apps.first { $0.id == existingSteam.id }
        #expect(storedSteam?.customArguments == "-silent")

        let storedCustom = store.apps.first { $0.id == customApp.id }
        #expect(storedCustom?.customArguments == "--custom-flag")

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("resolveAndHeal preserves user-configured customArguments without overwriting")
    func testResolveAndHealPreservesUserArguments() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storeURL = tempDir.appendingPathComponent("apps.json")
        let store = SettingsStore(fileURL: storeURL)

        let userConfiguredApp = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            bundleIdentifier: "com.hnc.Discord",
            customArguments: "--custom-user-arg"
        )

        try store.add(userConfiguredApp)

        let mockWorkspace = MockWorkspaceManager()
        let resolver = AppResolver(
            workspaceManager: mockWorkspace,
            fileExistsChecker: { $0 == "/Applications/Discord.app" }
        )

        let resolved = resolver.resolveAndHeal(apps: store.apps, store: store)

        #expect(resolved.count == 1)
        #expect(resolved[0].customArguments == "--custom-user-arg")

        let storedApp = store.apps.first { $0.id == userConfiguredApp.id }
        #expect(storedApp?.customArguments == "--custom-user-arg")

        try? FileManager.default.removeItem(at: tempDir)
    }
}
