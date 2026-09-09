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

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
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

        let coordinator = LaunchCoordinator(
            workspaceManager: mockWorkspace,
            windowSuppressor: mockSuppressor,
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
}
