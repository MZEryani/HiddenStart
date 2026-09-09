#if canImport(Testing)
import Testing
#endif
#if canImport(XCTest)
import XCTest
#endif
import AppKit
@testable import HiddenStart

@MainActor
final class MockAppTerminator: AppTerminating {
    private(set) var terminateCalled = false

    func terminate() {
        terminateCalled = true
    }
}

@MainActor
final class MockSettingsStore: SettingsStoring {
    var apps: [ManagedApp] = []
    var saveCallCount = 0
    var loadCallCount = 0

    init(apps: [ManagedApp] = []) {
        self.apps = apps
    }

    func load() throws {
        loadCallCount += 1
    }

    func save() throws {
        saveCallCount += 1
    }

    func add(_ app: ManagedApp) throws {
        apps.append(app)
        try save()
    }

    func remove(withId id: UUID) throws {
        apps.removeAll { $0.id == id }
        try save()
    }

    func update(_ app: ManagedApp) throws {
        if let index = apps.firstIndex(where: { $0.id == app.id }) {
            apps[index] = app
            try save()
        }
    }
}

#if canImport(Testing)
@Suite("StatusViewModel Tests")
@MainActor
struct StatusViewModelTests {
    @Test("Default initialization has expected title and status")
    func defaultInitialization() {
        let mockTerminator = MockAppTerminator()
        let viewModel = StatusViewModel(terminator: mockTerminator)

        #expect(viewModel.title == "HiddenStart")
        #expect(viewModel.statusMessage == "Ready")
    }

    @Test("Custom status message is preserved")
    func customStatusMessage() {
        let mockTerminator = MockAppTerminator()
        let viewModel = StatusViewModel(statusMessage: "3 apps queued", terminator: mockTerminator)

        #expect(viewModel.statusMessage == "3 apps queued")
    }

    @Test("Quit delegates to terminator")
    func quitDelegatesToTerminator() {
        let mockTerminator = MockAppTerminator()
        let viewModel = StatusViewModel(terminator: mockTerminator)

        #expect(!mockTerminator.terminateCalled)
        viewModel.quit()
        #expect(mockTerminator.terminateCalled)
    }

    @Test("Adding application updates managedApps and saves to store")
    func testAddApplication() async {
        let store = MockSettingsStore()
        let picker = MockApplicationPicker()
        let app = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app", customArguments: "--start-minimized")
        picker.appToReturn = app

        let viewModel = StatusViewModel(
            settingsStore: store,
            appPicker: picker
        )

        await viewModel.addApplication()

        #expect(viewModel.managedApps.count == 1)
        #expect(viewModel.managedApps.first?.name == "Discord")
        #expect(store.apps.count == 1)
        #expect(store.saveCallCount == 1)
    }

    @Test("Removing application removes from store and updates managedApps")
    func testRemoveApplication() {
        let app = ManagedApp(name: "Steam", bundlePath: "/Applications/Steam.app")
        let store = MockSettingsStore(apps: [app])
        let viewModel = StatusViewModel(settingsStore: store)

        #expect(viewModel.managedApps.count == 1)

        viewModel.removeApplication(withId: app.id)

        #expect(viewModel.managedApps.isEmpty)
        #expect(store.apps.isEmpty)
        #expect(store.saveCallCount == 1)
    }

    @Test("Toggling app enabled state flips isEnabled and saves")
    func testToggleAppEnabled() {
        let app = ManagedApp(name: "Steam", bundlePath: "/Applications/Steam.app", isEnabled: true)
        let store = MockSettingsStore(apps: [app])
        let viewModel = StatusViewModel(settingsStore: store)

        viewModel.toggleAppEnabled(withId: app.id)

        #expect(viewModel.managedApps.first?.isEnabled == false)
        #expect(store.apps.first?.isEnabled == false)
        #expect(store.saveCallCount == 1)
    }

    @Test("Test launch executes via workspace manager")
    func testLaunchApp() async {
        let workspace = MockWorkspaceManager()
        let app = ManagedApp(
            name: "Steam",
            bundlePath: "/Applications/Steam.app",
            launchHidden: true,
            customArguments: "-silent"
        )
        let viewModel = StatusViewModel(workspaceManager: workspace)

        await viewModel.testLaunch(app: app)

        #expect(workspace.openedURLs.count == 1)
        #expect(workspace.openedURLs.first == app.bundleURL)
        #expect(workspace.configurations.first?.hides == true)
        #expect(workspace.configurations.first?.activates == false)
        #expect(workspace.configurations.first?.arguments == ["-silent"])
        #expect(viewModel.statusMessage == "Test launch triggered for Steam")
    }
}
#endif
