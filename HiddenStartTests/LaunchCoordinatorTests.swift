import Testing
import Foundation
@testable import HiddenStart

@Suite("LaunchCoordinator Tests")
@MainActor
struct LaunchCoordinatorTests {

    @Test("Skips already running applications and launches non-running apps")
    func skipsAlreadyRunningApps() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()

        let runningApp = MockRunningApp(
            processIdentifier: 101,
            bundleIdentifier: "com.discord.app",
            bundleURL: URL(fileURLWithPath: "/Applications/Discord.app")
        )
        mockWorkspace.stubbedRunningApplications = [runningApp]

        let discord = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            bundleIdentifier: "com.discord.app",
            delaySeconds: 0,
            isEnabled: true
        )
        let steam = ManagedApp(
            name: "Steam",
            bundlePath: "/Applications/Steam.app",
            bundleIdentifier: "com.valvesoftware.steam",
            delaySeconds: 0,
            isEnabled: true
        )

        let mockNetwork = MockNetworkMonitor(isConnected: true)
        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            sleep: { _ in }
        )

        coordinator.startStartupRun(for: [discord, steam])

        // Wait a microtick for synchronous/immediate tasks
        await Task.yield()

        // Discord should be skipped because it was already running
        #expect(mockSuppressor.launchedApps.contains { $0.id == steam.id })
        #expect(!mockSuppressor.launchedApps.contains { $0.id == discord.id })
    }

    @Test("Skips disabled applications")
    func skipsDisabledApps() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()

        let disabledApp = ManagedApp(
            name: "Spotify",
            bundlePath: "/Applications/Spotify.app",
            delaySeconds: 0,
            isEnabled: false
        )

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            sleep: { _ in }
        )

        coordinator.startStartupRun(for: [disabledApp])
        await Task.yield()

        #expect(mockSuppressor.launchedApps.isEmpty)
        #expect(coordinator.isRunning == false)
    }

    @Test("Concurrently schedules launch delays and updates statusSummary and remainingDelays")
    func schedulesDelaysConcurrently() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: true)

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            sleep: { _ in
                // Yield to allow coordinator state inspection
                await Task.yield()
            }
        )

        let app = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            delaySeconds: 2,
            isEnabled: true
        )

        coordinator.startStartupRun(for: [app])
        #expect(coordinator.isRunning == true)
        #expect(coordinator.remainingDelays[app.id] == 2)
        #expect(coordinator.statusSummary == "Discord in 2s")

        // Let the task run
        while coordinator.isRunning {
            await Task.yield()
        }

        #expect(mockSuppressor.launchedApps.count == 1)
        #expect(mockSuppressor.launchedApps.first?.id == app.id)
        #expect(coordinator.remainingDelays[app.id] == nil)
        #expect(coordinator.isRunning == false)
    }

    @Test("Cancelling a single app aborts its task without launching")
    func cancelLaunchAbortsPendingTask() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            sleep: { _ in
                // Sleep indefinitely until cancelled
                try await Task.sleep(for: .seconds(100))
            }
        )

        let app = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            delaySeconds: 10,
            isEnabled: true
        )

        coordinator.startStartupRun(for: [app])
        #expect(coordinator.remainingDelays[app.id] == 10)

        coordinator.cancelLaunch(for: app.id)

        #expect(coordinator.remainingDelays[app.id] == nil)
        #expect(mockSuppressor.launchedApps.isEmpty)
    }

    @Test("cancelAll cleanly aborts all pending launches")
    func cancelAllAbortsAllPendingLaunches() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            sleep: { _ in
                try await Task.sleep(for: .seconds(100))
            }
        )

        let app1 = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            delaySeconds: 10,
            isEnabled: true
        )
        let app2 = ManagedApp(
            name: "Steam",
            bundlePath: "/Applications/Steam.app",
            delaySeconds: 20,
            isEnabled: true
        )

        coordinator.startStartupRun(for: [app1, app2])
        #expect(coordinator.isRunning == true)

        coordinator.cancelAll()

        #expect(coordinator.isRunning == false)
        #expect(coordinator.remainingDelays.isEmpty)
        #expect(mockSuppressor.launchedApps.isEmpty)
    }

    @Test("App with waitForInternet launches immediately when network is already connected")
    func onlineNetworkGatedAppLaunches() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: true)

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            sleep: { _ in }
        )

        let app = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            delaySeconds: 0,
            waitForInternet: true,
            isEnabled: true
        )

        coordinator.startStartupRun(for: [app])
        await Task.yield()

        #expect(coordinator.networkStatus == "Network connected")
        #expect(mockSuppressor.launchedApps.count == 1)
        #expect(mockSuppressor.launchedApps.first?.id == app.id)
    }

    @Test("Network conjunction: app waits for network when offline, then launches on connect")
    func networkConjunctionWaitsThenLaunches() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: false)

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            offlineTimeout: .seconds(60),
            sleep: { _ in }
        )

        let app = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            delaySeconds: 0,
            waitForInternet: true,
            isEnabled: true
        )

        coordinator.startStartupRun(for: [app])
        await Task.yield()

        #expect(coordinator.networkStatus == "Waiting for network...")
        #expect(coordinator.statusSummary == "Waiting for network...")
        #expect(mockSuppressor.launchedApps.isEmpty)

        // Simulate network reconnecting
        mockNetwork.simulateNetworkChange(isConnected: true)
        await Task.yield()

        #expect(coordinator.networkStatus == "Network connected")
        #expect(mockSuppressor.launchedApps.count == 1)
        #expect(mockSuppressor.launchedApps.first?.id == app.id)
    }

    @Test("Non-gated app launches even when network is offline")
    func nonGatedAppLaunchesOffline() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: false)

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            sleep: { _ in }
        )

        let app = ManagedApp(
            name: "Calculator",
            bundlePath: "/Applications/Calculator.app",
            delaySeconds: 0,
            waitForInternet: false,
            isEnabled: true
        )

        coordinator.startStartupRun(for: [app])
        await Task.yield()

        #expect(mockSuppressor.launchedApps.count == 1)
        #expect(mockSuppressor.launchedApps.first?.id == app.id)
    }

    @Test("Offline fail-safe timeout skips gated apps after timeout and sets status to Skipped (Offline)")
    func offlineTimeoutSkipsGatedApps() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: false)

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            offlineTimeout: .milliseconds(20),
            deferredRetryDuration: .seconds(900),
            sleep: { duration in
                try await Task.sleep(for: duration)
            }
        )

        let app = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            delaySeconds: 0,
            waitForInternet: true,
            isEnabled: true
        )

        coordinator.startStartupRun(for: [app])
        #expect(coordinator.networkStatus == "Waiting for network...")

        // Wait for offline timeout to fire
        for _ in 0..<30 {
            if coordinator.networkStatus == "Skipped (Offline)" { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(coordinator.networkStatus == "Skipped (Offline)")
        #expect(coordinator.statusSummary == "Skipped (Offline)")
        #expect(mockSuppressor.launchedApps.isEmpty)
        #expect(coordinator.isRunning == false)
    }

    @Test("Deferred retry triggers skipped gated apps when network reconnects within retry window")
    func deferredRetryTriggersOnReconnect() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: false)

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            offlineTimeout: .milliseconds(20),
            deferredRetryDuration: .milliseconds(200),
            sleep: { duration in
                try await Task.sleep(for: duration)
            }
        )

        let app = ManagedApp(
            name: "Steam",
            bundlePath: "/Applications/Steam.app",
            delaySeconds: 0,
            waitForInternet: true,
            isEnabled: true
        )

        coordinator.startStartupRun(for: [app])

        // Wait for offline timeout to fire and skip app
        for _ in 0..<30 {
            if coordinator.networkStatus == "Skipped (Offline)" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(coordinator.networkStatus == "Skipped (Offline)")
        #expect(mockSuppressor.launchedApps.isEmpty)

        // Now within the deferred retry window, simulate network reconnection
        mockNetwork.simulateNetworkChange(isConnected: true)
        for _ in 0..<30 {
            if !mockSuppressor.launchedApps.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(coordinator.networkStatus == "Network connected")
        #expect(mockSuppressor.launchedApps.count == 1)
        #expect(mockSuppressor.launchedApps.first?.id == app.id)
    }

    @Test("Deferred retry observer cleanly expires after window without launching")
    func deferredRetryObserverCleanlyExpires() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: false)

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            offlineTimeout: .milliseconds(20),
            deferredRetryDuration: .milliseconds(40),
            sleep: { duration in
                try await Task.sleep(for: duration)
            }
        )

        let app = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            delaySeconds: 0,
            waitForInternet: true,
            isEnabled: true
        )

        coordinator.startStartupRun(for: [app])

        // Wait for offline timeout (20ms) + deferred retry window (40ms) to fully expire
        try await Task.sleep(for: .milliseconds(100))

        #expect(coordinator.networkStatus == "Skipped (Offline)")
        // Connecting AFTER the deferred retry window expired should NOT trigger launch
        mockNetwork.simulateNetworkChange(isConnected: true)
        try await Task.sleep(for: .milliseconds(30))

        #expect(mockSuppressor.launchedApps.isEmpty)
        #expect(mockNetwork.stopMonitoringCallCount >= 1)
    }

    @Test("Conjunction: when network connects before delay finishes, launch occurs at delay end")
    func conjunctionNetworkConnectsBeforeDelayFinishes() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: false)

        final class DelayCounter: @unchecked Sendable {
            let lock = NSLock()
            var count = 0
            func increment() -> Int {
                lock.lock()
                defer { lock.unlock() }
                count += 1
                return count
            }
        }
        let counter = DelayCounter()

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            offlineTimeout: .seconds(60),
            sleep: { _ in
                let current = counter.increment()
                if current == 1 {
                    // Connect midway through delay
                    await MainActor.run {
                        mockNetwork.simulateNetworkChange(isConnected: true)
                    }
                }
                await Task.yield()
            }
        )

        let app = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            delaySeconds: 2,
            waitForInternet: true,
            isEnabled: true
        )

        coordinator.startStartupRun(for: [app])

        while coordinator.isRunning {
            await Task.yield()
        }

        #expect(mockSuppressor.launchedApps.count == 1)
        #expect(mockSuppressor.launchedApps.first?.id == app.id)
        #expect(coordinator.networkStatus == "Network connected")
    }

    @Test("Conjunction: when delay finishes before network connects, launch waits for network")
    func conjunctionDelayFinishesBeforeNetworkConnects() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: false)

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            offlineTimeout: .seconds(60),
            sleep: { _ in
                await Task.yield()
            }
        )

        let app = ManagedApp(
            name: "Steam",
            bundlePath: "/Applications/Steam.app",
            delaySeconds: 1,
            waitForInternet: true,
            isEnabled: true
        )

        coordinator.startStartupRun(for: [app])

        // Allow delay of 1s to tick down to 0
        while coordinator.remainingDelays[app.id] != nil {
            await Task.yield()
        }

        // App should be waiting for network, not launched yet
        #expect(coordinator.remainingDelays[app.id] == nil)
        #expect(coordinator.statusSummary == "Waiting for network...")
        #expect(mockSuppressor.launchedApps.isEmpty)

        // Now connect network
        mockNetwork.simulateNetworkChange(isConnected: true)
        await Task.yield()

        #expect(mockSuppressor.launchedApps.count == 1)
        #expect(mockSuppressor.launchedApps.first?.id == app.id)
        #expect(coordinator.networkStatus == "Network connected")
    }

    @Test("cancelAll cleanly stops network monitoring")
    func cancelAllStopsNetworkMonitoring() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: false)

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            sleep: { _ in try await Task.sleep(for: .seconds(100)) }
        )

        let app = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            delaySeconds: 10,
            waitForInternet: true,
            isEnabled: true
        )

        coordinator.startStartupRun(for: [app])
        #expect(mockNetwork.startMonitoringCallCount == 1)
        let stopsBefore = mockNetwork.stopMonitoringCallCount

        coordinator.cancelAll()
        #expect(mockNetwork.stopMonitoringCallCount == stopsBefore + 1)
    }

    @Test("Coordinator auto-heals moved app and launches with healed path")
    func coordinatorAutoHealsMovedApp() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: true)

        let movedURL = URL(fileURLWithPath: "/Applications/NewLocation/Discord.app")
        mockWorkspace.applicationURLs["com.hnc.Discord"] = movedURL

        let resolver = AppResolver(
            workspaceManager: mockWorkspace,
            fileExistsChecker: { path in path == "/Applications/NewLocation/Discord.app" }
        )

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storeURL = tempDir.appendingPathComponent("apps.json")
        let store = SettingsStore(fileURL: storeURL)

        let app = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/OldLocation/Discord.app",
            bundleIdentifier: "com.hnc.Discord",
            delaySeconds: 0,
            waitForInternet: false,
            isEnabled: true
        )
        try store.add(app)

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            appResolver: resolver,
            settingsStore: store,
            sleep: { _ in }
        )

        coordinator.startStartupRun(for: [app])
        try await Task.sleep(for: .milliseconds(30))

        #expect(mockSuppressor.launchedApps.count == 1)
        #expect(mockSuppressor.launchedApps.first?.bundlePath == "/Applications/NewLocation/Discord.app")

        // Verify store updated with healed path
        let updatedInStore = store.apps.first { $0.id == app.id }
        #expect(updatedInStore?.bundlePath == "/Applications/NewLocation/Discord.app")

        try? FileManager.default.removeItem(at: tempDir)
    }

    @Test("Coordinator safely skips missing app without crashing")
    func coordinatorSafelySkipsMissingApp() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: true)

        let resolver = AppResolver(
            workspaceManager: mockWorkspace,
            fileExistsChecker: { _ in false }
        )

        let app = ManagedApp(
            name: "GhostApp",
            bundlePath: "/Applications/GhostApp.app",
            bundleIdentifier: "com.example.ghost",
            delaySeconds: 0,
            waitForInternet: false,
            isEnabled: true
        )

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            appResolver: resolver,
            sleep: { _ in }
        )

        coordinator.startStartupRun(for: [app])
        try await Task.sleep(for: .milliseconds(30))

        #expect(mockSuppressor.launchedApps.isEmpty)
        #expect(coordinator.isRunning == false)
    }

    @Test("Concurrent network-gated apps completing delay both launch and register in suppressor")
    func concurrentNetworkGatedAppsBothLaunch() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: true)

        let app1 = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            bundleIdentifier: "com.hnc.Discord",
            delaySeconds: 0,
            waitForInternet: true,
            isEnabled: true
        )
        let app2 = ManagedApp(
            name: "Antigravity",
            bundlePath: "/Applications/Antigravity.app",
            bundleIdentifier: "com.google.antigravity",
            delaySeconds: 0,
            waitForInternet: true,
            isEnabled: true
        )

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            sleep: { _ in }
        )

        coordinator.startStartupRun(for: [app1, app2])
        try await Task.sleep(for: .milliseconds(30))

        #expect(mockSuppressor.launchedApps.count == 2)
        #expect(mockSuppressor.launchedApps.contains { $0.id == app1.id })
        #expect(mockSuppressor.launchedApps.contains { $0.id == app2.id })
    }

    @Test("Cancelling a launched app cancels suppression for that specific process identifier")
    func cancelLaunchCancelsSuppressorForProcess() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: true)

        let app = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            bundleIdentifier: "com.hnc.Discord",
            delaySeconds: 0,
            waitForInternet: false,
            isEnabled: true
        )

        mockSuppressor.stubbedRunningApp = MockRunningApp(processIdentifier: 8877)

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            sleep: { _ in }
        )

        coordinator.startStartupRun(for: [app])
        try await Task.sleep(for: .milliseconds(30))

        #expect(mockSuppressor.launchedApps.count == 1)

        coordinator.cancelLaunch(for: app.id)

        #expect(mockSuppressor.cancelledPids == [8877])
    }

    @Test("CancelAll delegates cancelAll to window suppressor")
    func cancelAllDelegatesToSuppressor() {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: true)

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            sleep: { _ in }
        )

        coordinator.cancelAll()

        #expect(mockSuppressor.cancelAllCallCount == 1)
    }
}

