#if canImport(Testing)
import Testing
#endif
#if canImport(XCTest)
import XCTest
#endif
import AppKit
@testable import HiddenStart

#if canImport(Testing)
@Suite("StatusViewModel Tests")
@MainActor
struct StatusViewModelTests {
    @Test("Default initialization has expected title and status")
    func defaultInitialization() {
        let viewModel = StatusViewModel()

        #expect(viewModel.title == "HiddenStart")
        #expect(viewModel.statusMessage == "Ready")
        #expect(viewModel.networkStatusLevel == .waiting)
    }

    @Test("Custom status message is preserved")
    func customStatusMessage() {
        let viewModel = StatusViewModel(statusMessage: "3 apps queued")

        #expect(viewModel.statusMessage == "3 apps queued")
    }

    @Test("Quit delegates to terminator")
    func quitDelegatesToTerminator() {
        var terminateCalled = false
        let viewModel = StatusViewModel(terminateApp: { terminateCalled = true })

        #expect(!terminateCalled)
        viewModel.quit()
        #expect(terminateCalled)
    }

    @Test("Adding application updates managedApps and saves to store")
    func testAddApplication() async {
        let store = MockManagedAppStore()
        var selectedURL: URL? = URL(fileURLWithPath: "/Applications/Discord.app")
        let picker = ApplicationPicker(
            appActivator: { _ in },
            panelPresenter: { _ in (.OK, selectedURL) }
        )
        let discordApp = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app", bundleIdentifier: "com.hnc.discord", customArguments: "")
        store.appToReturnFromAddApp = discordApp

        let viewModel = StatusViewModel(
            managedAppStore: store,
            appPicker: picker
        )

        await viewModel.addApplication()

        #expect(viewModel.managedApps.count == 1)
        #expect(viewModel.managedApps.first?.name == "Discord")
        #expect(store.apps.count == 1)
        #expect(store.saveCallCount == 1)
        #expect(viewModel.statusMessage == "Added Discord (Launch Hidden configured; custom arguments empty)")

        let slackApp = ManagedApp(name: "Slack", bundlePath: "/Applications/Slack.app")
        store.appToReturnFromAddApp = slackApp
        selectedURL = URL(fileURLWithPath: "/Applications/Slack.app")
        await viewModel.addApplication()
        #expect(viewModel.statusMessage == "Added Slack")
    }


    @Test("Removing application removes from store and updates managedApps")
    func testRemoveApplication() {
        let app = ManagedApp(name: "Steam", bundlePath: "/Applications/Steam.app")
        let store = MockManagedAppStore(apps: [app])
        let viewModel = StatusViewModel(managedAppStore: store)

        #expect(viewModel.managedApps.count == 1)

        viewModel.removeApplication(withId: app.id)

        #expect(viewModel.managedApps.isEmpty)
        #expect(store.apps.isEmpty)
        #expect(store.saveCallCount == 1)
    }

    @Test("Toggling app enabled state flips isEnabled and saves")
    func testToggleAppEnabled() {
        let app = ManagedApp(name: "Steam", bundlePath: "/Applications/Steam.app", isEnabled: true)
        let store = MockManagedAppStore(apps: [app])
        let viewModel = StatusViewModel(managedAppStore: store)

        viewModel.toggleAppEnabled(withId: app.id)

        #expect(viewModel.managedApps.first?.isEnabled == false)
        #expect(store.apps.first?.isEnabled == false)
        #expect(store.saveCallCount == 1)
    }

    @Test("Test launch passes configured app settings to launch coordinator")
    func testLaunchPassesConfiguredAppSettings() async {
        let coordinator = MockStartupRunCoordinator()
        let storeApp = ManagedApp(
            name: "Steam",
            bundlePath: "/Applications/Steam.app",
            launchHidden: false,
            customArguments: ""
        )
        let store = MockManagedAppStore(apps: [storeApp])
        let viewModel = StatusViewModel(managedAppStore: store, startupRunCoordinator: coordinator)

        var editedApp = storeApp
        editedApp.launchHidden = true
        editedApp.customArguments = "-silent"

        await viewModel.testLaunch(app: editedApp)

        #expect(coordinator.launchImmediatelyCallCount == 1)
        #expect(coordinator.lastAppLaunchedImmediately?.launchHidden == true)
        #expect(coordinator.lastAppLaunchedImmediately?.customArguments == "-silent")
        #expect(viewModel.statusMessage == "Test launch triggered for Steam")
    }


    @Test("Test launch delegates to startup run coordinator")
    func testLaunchDelegatesToCoordinator() async {
        let coordinator = MockStartupRunCoordinator()
        let app = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app", launchHidden: true)
        let store = MockManagedAppStore(apps: [app])
        let viewModel = StatusViewModel(managedAppStore: store, startupRunCoordinator: coordinator)

        await viewModel.testLaunch(app: app)

        #expect(coordinator.launchImmediatelyCallCount == 1)
        #expect(coordinator.lastAppLaunchedImmediately?.id == app.id)
        #expect(viewModel.statusMessage == "Test launch triggered for Discord")
    }

    @Test("startStartupRun delegates to launch coordinator")
    func startStartupRunDelegatesToCoordinator() {
        let app = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app")
        let store = MockManagedAppStore(apps: [app])
        let coordinator = MockStartupRunCoordinator()
        let viewModel = StatusViewModel(managedAppStore: store, startupRunCoordinator: coordinator)

        viewModel.startStartupRun()

        #expect(coordinator.startStartupRunCallCount == 1)
        #expect(coordinator.lastAppsStarted.count == 1)
        #expect(coordinator.lastAppsStarted.first?.id == app.id)
    }

    @Test("Toggling app to disabled cancels in-flight launch")
    func toggleAppToDisabledCancelsLaunch() {
        let app = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app", isEnabled: true)
        let store = MockManagedAppStore(apps: [app])
        let coordinator = MockStartupRunCoordinator()
        let viewModel = StatusViewModel(managedAppStore: store, startupRunCoordinator: coordinator)

        viewModel.toggleAppEnabled(withId: app.id)

        #expect(coordinator.cancelledAppIds == [app.id])
    }

    @Test("Removing app cancels in-flight launch")
    func removingAppCancelsLaunch() {
        let app = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app")
        let store = MockManagedAppStore(apps: [app])
        let coordinator = MockStartupRunCoordinator()
        let viewModel = StatusViewModel(managedAppStore: store, startupRunCoordinator: coordinator)

        viewModel.removeApplication(withId: app.id)

        #expect(coordinator.cancelledAppIds == [app.id])
    }

    @Test("Quitting cancels all in-flight launches")
    func quittingCancelsAllLaunches() {
        var terminateCalled = false
        let coordinator = MockStartupRunCoordinator()
        let viewModel = StatusViewModel(
            startupRunCoordinator: coordinator,
            terminateApp: { terminateCalled = true }
        )

        viewModel.quit()

        #expect(coordinator.cancelAllCallCount == 1)
        #expect(terminateCalled)
    }


    @Test("Updating application updates store and managedApps list")
    func updateApplicationUpdatesStore() {
        let app = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app", delaySeconds: 10)
        let store = MockManagedAppStore(apps: [app])
        let viewModel = StatusViewModel(managedAppStore: store)

        var modified = app
        modified.delaySeconds = 30
        viewModel.updateApplication(modified)

        #expect(viewModel.managedApps.first?.delaySeconds == 30)
        #expect(store.apps.first?.delaySeconds == 30)
        #expect(store.saveCallCount == 1)
    }

    @Test("Coordinator delay updates remainingDelays and statusMessage")
    func delayUpdatesRemainingDelaysAndStatus() async {
        let id = UUID()
        let app = ManagedApp(id: id, name: "Discord", bundlePath: "/Applications/Discord.app", delaySeconds: 5)
        let store = MockManagedAppStore(apps: [app])
        let coordinator = MockStartupRunCoordinator()
        let viewModel = StatusViewModel(managedAppStore: store, startupRunCoordinator: coordinator)

        coordinator.state = StartupRunState(
            phase: .running,
            remainingDelays: [id: 5],
            isNetworkConnected: true
        )

        await Task.yield()

        #expect(viewModel.remainingDelays[id] == 5)
        #expect(viewModel.statusMessage == "Discord in 5s")
    }

    @Test("Coordinator networkStatus updates viewModel networkStatus, networkStatusLevel, and statusMessage")
    func networkStatusUpdatesViewModel() async {
        let coordinator = MockStartupRunCoordinator()
        let viewModel = StatusViewModel(startupRunCoordinator: coordinator)

        #expect(viewModel.networkStatus == "Network connected")
        #expect(viewModel.networkStatusLevel == .connected)

        coordinator.state = StartupRunState(
            phase: .running,
            waitingForNetworkAppIds: [UUID()],
            isNetworkConnected: false
        )
        await Task.yield()

        #expect(viewModel.networkStatus == "Waiting for network...")
        #expect(viewModel.networkStatusLevel == .waiting)
        #expect(viewModel.statusMessage == "Waiting for network...")

        coordinator.state = StartupRunState(
            phase: .deferredRetry,
            isNetworkConnected: false,
            skippedAppIds: [UUID()]
        )
        await Task.yield()

        #expect(viewModel.networkStatus == "Skipped (Offline)")
        #expect(viewModel.networkStatusLevel == .skippedOffline)
        #expect(viewModel.statusMessage == "Skipped (Offline)")
    }

    @Test("Action message from user interaction is preserved across coordinator idle pulses")
    func actionMessagePreservedAcrossIdlePulses() async {
        let coordinator = MockStartupRunCoordinator()
        let app = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app")
        let store = MockManagedAppStore(apps: [app])
        let viewModel = StatusViewModel(managedAppStore: store, startupRunCoordinator: coordinator)

        viewModel.removeApplication(withId: app.id)
        #expect(viewModel.statusMessage == "Removed app")

        // Coordinator emits an idle pulse
        coordinator.state = StartupRunState(
            phase: .idle,
            isNetworkConnected: true
        )
        await Task.yield()

        #expect(viewModel.statusMessage == "Removed app")
    }

    @Test("Active startup run clears ViewModel action message and takes coordinator precedence")
    func activeStartupRunClearsActionMessage() async {
        let coordinator = MockStartupRunCoordinator()
        let app = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app")
        let store = MockManagedAppStore(apps: [app])
        let viewModel = StatusViewModel(managedAppStore: store, startupRunCoordinator: coordinator)

        viewModel.removeApplication(withId: app.id)
        #expect(viewModel.statusMessage == "Removed app")

        // Coordinator begins running
        coordinator.state = StartupRunState(
            phase: .running,
            remainingDelays: [:],
            isNetworkConnected: true
        )
        await Task.yield()

        #expect(viewModel.statusMessage == "Launching...")
    }

    @Test("Status message transitions through running to Ready when run completes")
    func statusMessageTransitionsBackToReady() async {
        let coordinator = MockStartupRunCoordinator()
        let viewModel = StatusViewModel(startupRunCoordinator: coordinator)

        #expect(viewModel.statusMessage == "Ready")

        coordinator.state = StartupRunState(
            phase: .running,
            remainingDelays: [:],
            isNetworkConnected: true
        )
        await Task.yield()

        #expect(viewModel.statusMessage == "Launching...")

        coordinator.state = StartupRunState(
            phase: .idle,
            remainingDelays: [:],
            isNetworkConnected: true
        )
        await Task.yield()

        #expect(viewModel.statusMessage == "Ready")
    }

    @Test("toggleAutoStart registers when disabled and unregisters when enabled")
    func testToggleAutoStart() {
        let autoStart = AutoStartManager(status: .notRegistered)
        let viewModel = StatusViewModel(autoStartManager: autoStart)

        #expect(viewModel.isAutoStartEnabled == false)

        viewModel.toggleAutoStart()

        #expect(viewModel.isAutoStartEnabled == true)
        #expect(viewModel.autoStartStatus == .enabled)

        viewModel.toggleAutoStart()

        #expect(viewModel.isAutoStartEnabled == false)
        #expect(viewModel.autoStartStatus == .notRegistered)
    }

    @Test("AutoStart with requiresApproval sets flag and opens settings")
    func testAutoStartRequiresApproval() {
        var openSettingsCalled = false
        let autoStart = AutoStartManager(
            status: .requiresApproval,
            openSettingsAction: { openSettingsCalled = true }
        )
        let viewModel = StatusViewModel(autoStartManager: autoStart)

        #expect(viewModel.autoStartRequiresApproval == true)
        #expect(viewModel.isAutoStartEnabled == false)

        viewModel.openSystemSettingsLoginItems()
        #expect(openSettingsCalled == true)
    }

    @Test("toggleAutoStart sets statusMessage on failure")
    func testToggleAutoStartFailure() {
        struct TestError: LocalizedError {
            var errorDescription: String? { "Operation not permitted" }
        }
        let autoStart = AutoStartManager(
            status: .notRegistered,
            registerAction: { throw TestError() }
        )
        let viewModel = StatusViewModel(autoStartManager: autoStart)

        viewModel.toggleAutoStart()

        #expect(viewModel.isAutoStartEnabled == false)
        #expect(viewModel.statusMessage == "Failed to update login item: Operation not permitted")
    }

    @Test("ViewModel auto-heals moved app on load and updates store")
    func testAutoHealingOnLoad() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("apps.json")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let mockWorkspace = MockWorkspaceManager()
        mockWorkspace.applicationURLs["com.example.moved"] = URL(fileURLWithPath: "/Applications/NewPath/App.app")

        let store = ManagedAppStore(
            fileURL: fileURL,
            workspaceManager: mockWorkspace,
            fileExistsChecker: { path in path == "/Applications/NewPath/App.app" }
        )
        let movedApp = ManagedApp(
            name: "MovedApp",
            bundlePath: "/Applications/OldPath/App.app",
            bundleIdentifier: "com.example.moved"
        )
        try store.addDirectlyForTesting(movedApp)

        let viewModel = StatusViewModel(
            managedAppStore: store,
            workspaceManager: mockWorkspace
        )

        #expect(viewModel.managedApps.count == 1)
        #expect(viewModel.managedApps.first?.bundlePath == "/Applications/NewPath/App.app")
        #expect(store.apps.first?.bundlePath == "/Applications/NewPath/App.app")
        #expect(viewModel.isAppMissing(movedApp) == false)
    }

    @Test("ViewModel detects missing apps and queries isAppMissing")
    func testMissingAppDetection() {
        let missingApp = ManagedApp(
            name: "DeletedApp",
            bundlePath: "/Applications/DeletedApp.app",
            bundleIdentifier: "com.example.deleted"
        )
        let store = MockManagedAppStore(apps: [missingApp], missingIds: [missingApp.id])

        let viewModel = StatusViewModel(
            managedAppStore: store
        )

        #expect(viewModel.isAppMissing(missingApp) == true)
    }

    @Test("testLaunch on missing app fails gracefully without crashing")
    func testLaunchMissingAppFailsGracefully() async {
        let missingApp = ManagedApp(
            name: "GhostApp",
            bundlePath: "/Applications/GhostApp.app",
            bundleIdentifier: "com.example.ghost"
        )
        let store = MockManagedAppStore(apps: [missingApp], missingIds: [missingApp.id])
        let coordinator = MockStartupRunCoordinator()

        let viewModel = StatusViewModel(
            managedAppStore: store,
            startupRunCoordinator: coordinator
        )

        await viewModel.testLaunch(app: missingApp)

        #expect(coordinator.launchImmediatelyCallCount == 0)
        #expect(viewModel.statusMessage == "Launch failed: Application not found")
        #expect(viewModel.isAppMissing(missingApp) == true)
    }


    @Test("Startup run resolves and heals multiple managed apps before launching")
    func startupRunHealsAndLaunchesMultipleApps() throws {
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("apps.json")
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let discord = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            bundleIdentifier: "com.hnc.Discord",
            customArguments: ""
        )
        let steam = ManagedApp(
            name: "Steam",
            bundlePath: "/Applications/Steam.app",
            bundleIdentifier: "com.valvesoftware.steam",
            customArguments: ""
        )
        let store = ManagedAppStore(
            fileURL: fileURL,
            fileExistsChecker: { _ in true }
        )
        try store.addDirectlyForTesting(discord)
        try store.addDirectlyForTesting(steam)

        let coordinator = MockStartupRunCoordinator()
        let viewModel = StatusViewModel(
            managedAppStore: store,
            startupRunCoordinator: coordinator
        )

        viewModel.startStartupRun()

        #expect(coordinator.startStartupRunCallCount == 1)
        #expect(coordinator.lastAppsStarted.count == 2)
        #expect(viewModel.managedApps.first { $0.bundleIdentifier == "com.hnc.Discord" }?.customArguments == "")
        #expect(viewModel.managedApps.first { $0.bundleIdentifier == "com.valvesoftware.steam" }?.customArguments == "-silent")
    }
}
#endif
