import Testing
import Foundation
@testable import HiddenStart

@Suite("StartupRunCoordinator Tests")
@MainActor
struct StartupRunCoordinatorTests {

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
        let coordinator = StartupRunCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            sleep: { _ in }
        )

        coordinator.startStartupRun(for: [discord, steam])
        await Task.yield()

        #expect(mockSuppressor.launchedApps.contains { $0.id == steam.id })
        #expect(!mockSuppressor.launchedApps.contains { $0.id == discord.id })
    }

    @Test("Skips disabled applications and remains idle")
    func skipsDisabledApps() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()

        let disabledApp = ManagedApp(
            name: "Spotify",
            bundlePath: "/Applications/Spotify.app",
            delaySeconds: 0,
            isEnabled: false
        )

        let coordinator = StartupRunCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            sleep: { _ in }
        )

        coordinator.startStartupRun(for: [disabledApp])
        await Task.yield()

        #expect(mockSuppressor.launchedApps.isEmpty)
        #expect(coordinator.state.phase == .idle)
    }

    @Test("Concurrently schedules launch delays and updates state remainingDelays")
    func schedulesDelaysConcurrently() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: true)

        let coordinator = StartupRunCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            sleep: { _ in
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
        #expect(coordinator.state.phase == .running)
        #expect(coordinator.state.remainingDelays[app.id] == 2)

        for _ in 0..<10 {
            if coordinator.state.remainingDelays[app.id] == 1 { break }
            await Task.yield()
        }
        #expect(coordinator.state.remainingDelays[app.id] == 1)

        while coordinator.state.phase == .running {
            await Task.yield()
        }

        #expect(mockSuppressor.launchedApps.count == 1)
        #expect(mockSuppressor.launchedApps.first?.id == app.id)
        #expect(coordinator.state.remainingDelays[app.id] == nil)
        #expect(coordinator.state.phase == .idle)
    }

    @Test("Cancelling a single app aborts its task without launching")
    func cancelLaunchAbortsPendingTask() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()

        let coordinator = StartupRunCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            sleep: { _ in
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
        #expect(coordinator.state.remainingDelays[app.id] == 10)

        coordinator.cancelLaunch(for: app.id)

        #expect(coordinator.state.remainingDelays[app.id] == nil)
        #expect(mockSuppressor.launchedApps.isEmpty)
        #expect(coordinator.state.phase == .idle)
    }

    @Test("cancelAll cleanly aborts all pending launches and resets state")
    func cancelAllAbortsAllPendingLaunches() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()

        let coordinator = StartupRunCoordinator(
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
        #expect(coordinator.state.phase == .running)

        coordinator.cancelAll()

        #expect(coordinator.state.phase == .idle)
        #expect(coordinator.state.remainingDelays.isEmpty)
        #expect(coordinator.state.waitingForNetworkAppIds.isEmpty)
        #expect(coordinator.state.skippedAppIds.isEmpty)
        #expect(mockSuppressor.launchedApps.isEmpty)
    }

    @Test("App with waitForInternet launches immediately when network is already connected")
    func onlineNetworkGatedAppLaunches() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: true)

        let coordinator = StartupRunCoordinator(
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

        #expect(coordinator.state.isNetworkConnected == true)
        #expect(mockSuppressor.launchedApps.count == 1)
        #expect(mockSuppressor.launchedApps.first?.id == app.id)
    }

    @Test("Network conjunction: app waits for network when offline, then launches on connect")
    func networkConjunctionWaitsThenLaunches() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: false)

        let coordinator = StartupRunCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            offlineTimeout: .seconds(60),
            sleep: { duration in
                if duration >= .seconds(60) {
                    try await Task.sleep(for: .seconds(100))
                }
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
        await Task.yield()

        #expect(coordinator.state.isNetworkConnected == false)
        #expect(coordinator.state.waitingForNetworkAppIds.contains(app.id))
        #expect(mockSuppressor.launchedApps.isEmpty)

        // Simulate network reconnecting
        mockNetwork.simulateNetworkChange(isConnected: true)
        await Task.yield()

        #expect(coordinator.state.isNetworkConnected == true)
        #expect(coordinator.state.waitingForNetworkAppIds.isEmpty)
        #expect(mockSuppressor.launchedApps.count == 1)
        #expect(mockSuppressor.launchedApps.first?.id == app.id)
    }

    @Test("Non-gated app launches even when network is offline")
    func nonGatedAppLaunchesOffline() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: false)

        let coordinator = StartupRunCoordinator(
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

    @Test("Offline fail-safe timeout skips gated apps and transitions to deferred retry")
    func offlineTimeoutSkipsGatedApps() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: false)

        let coordinator = StartupRunCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            offlineTimeout: .seconds(60),
            deferredRetryDuration: .seconds(900),
            sleep: { duration in
                // Instant sleep allows 60s timeout to trigger immediately
                if duration == .seconds(60) {
                    return
                }
                // For deferred retry sleep, hold until cancelled
                try await Task.sleep(for: .seconds(100))
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

        // Yield for the offline timeout task to execute
        for _ in 0..<10 {
            if coordinator.state.phase == .deferredRetry { break }
            await Task.yield()
        }

        #expect(coordinator.state.skippedAppIds.contains(app.id))
        #expect(coordinator.state.phase == .deferredRetry)
        #expect(mockSuppressor.launchedApps.isEmpty)
    }

    @Test("Deferred retry triggers skipped gated apps when network reconnects within retry window")
    func deferredRetryTriggersOnReconnect() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: false)

        let coordinator = StartupRunCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            offlineTimeout: .seconds(60),
            deferredRetryDuration: .seconds(900),
            sleep: { duration in
                if duration == .seconds(60) {
                    return
                }
                // Hold deferred retry window until reconnected
                try await Task.sleep(for: .seconds(100))
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

        for _ in 0..<10 {
            if coordinator.state.phase == .deferredRetry { break }
            await Task.yield()
        }

        #expect(coordinator.state.skippedAppIds.contains(app.id))
        #expect(coordinator.state.phase == .deferredRetry)
        #expect(mockSuppressor.launchedApps.isEmpty)

        // Now within deferred retry window, simulate network reconnection
        mockNetwork.simulateNetworkChange(isConnected: true)
        for _ in 0..<10 {
            if !mockSuppressor.launchedApps.isEmpty { break }
            await Task.yield()
        }

        #expect(coordinator.state.isNetworkConnected == true)
        #expect(mockSuppressor.launchedApps.count == 1)
        #expect(mockSuppressor.launchedApps.first?.id == app.id)
    }

    @Test("Deferred retry observer cleanly expires after window without launching")
    func deferredRetryObserverCleanlyExpires() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: false)

        let coordinator = StartupRunCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            offlineTimeout: .seconds(60),
            deferredRetryDuration: .seconds(900),
            sleep: { _ in
                // Instant sleep allows offline timeout and deferred retry window to expire immediately
                return
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

        for _ in 0..<20 {
            if mockNetwork.stopMonitoringCallCount >= 1 && coordinator.state.phase == .idle { break }
            await Task.yield()
        }

        #expect(coordinator.state.phase == .idle)
        #expect(mockSuppressor.launchedApps.isEmpty)
        #expect(mockNetwork.stopMonitoringCallCount >= 1)

        // Connecting AFTER the deferred retry window expired should NOT trigger launch
        mockNetwork.simulateNetworkChange(isConnected: true)
        await Task.yield()

        #expect(mockSuppressor.launchedApps.isEmpty)
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

        let coordinator = StartupRunCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            offlineTimeout: .seconds(60),
            sleep: { _ in
                let current = counter.increment()
                if current == 1 {
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

        while coordinator.state.phase == .running {
            await Task.yield()
        }

        #expect(mockSuppressor.launchedApps.count == 1)
        #expect(mockSuppressor.launchedApps.first?.id == app.id)
        #expect(coordinator.state.isNetworkConnected == true)
    }

    @Test("Conjunction: when delay finishes before network connects, launch waits for network")
    func conjunctionDelayFinishesBeforeNetworkConnects() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: false)

        let coordinator = StartupRunCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            offlineTimeout: .seconds(60),
            sleep: { duration in
                if duration >= .seconds(60) {
                    try await Task.sleep(for: .seconds(100))
                } else {
                    await Task.yield()
                }
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

        while coordinator.state.remainingDelays[app.id] != nil {
            await Task.yield()
        }

        #expect(coordinator.state.remainingDelays[app.id] == nil)
        #expect(coordinator.state.waitingForNetworkAppIds.contains(app.id))
        #expect(mockSuppressor.launchedApps.isEmpty)

        // Now connect network
        mockNetwork.simulateNetworkChange(isConnected: true)
        for _ in 0..<10 {
            if mockSuppressor.launchedApps.count == 1 { break }
            await Task.yield()
        }

        #expect(mockSuppressor.launchedApps.count == 1)
        #expect(mockSuppressor.launchedApps.first?.id == app.id)
        #expect(coordinator.state.isNetworkConnected == true)
    }

    @Test("cancelAll cleanly stops network monitoring")
    func cancelAllStopsNetworkMonitoring() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: false)

        let coordinator = StartupRunCoordinator(
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

        let coordinator = StartupRunCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            sleep: { _ in }
        )

        coordinator.startStartupRun(for: [app1, app2])
        for _ in 0..<10 {
            if mockSuppressor.launchedApps.count == 2 { break }
            await Task.yield()
        }

        #expect(mockSuppressor.launchedApps.count == 2)
        #expect(mockSuppressor.launchedApps.contains { $0.id == app1.id })
        #expect(mockSuppressor.launchedApps.contains { $0.id == app2.id })
    }

    @Test("Cancelling a launched app cancels suppression for that specific app")
    func cancelLaunchCancelsSuppressorForApp() async throws {
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

        let coordinator = StartupRunCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            sleep: { _ in }
        )

        coordinator.startStartupRun(for: [app])
        for _ in 0..<10 {
            if mockSuppressor.launchedApps.count == 1 { break }
            await Task.yield()
        }

        #expect(mockSuppressor.launchedApps.count == 1)

        coordinator.cancelLaunch(for: app.id)

        #expect(mockSuppressor.cancelledAppIds == [app.id])
    }

    @Test("CancelAll delegates cancelAll to window suppressor")
    func cancelAllDelegatesToSuppressor() {
        let mockWorkspace = MockWorkspaceManager()
        let mockSuppressor = MockWindowSuppressor()
        let mockNetwork = MockNetworkMonitor(isConnected: true)

        let coordinator = StartupRunCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
            networkMonitor: mockNetwork,
            sleep: { _ in }
        )

        coordinator.cancelAll()

        #expect(mockSuppressor.cancelAllCallCount == 1)
    }
}
