import Testing
import Foundation
import AppKit
@testable import HiddenStart

@Suite("WindowSuppressionEngine Tests")
@MainActor
struct WindowSuppressionEngineTests {

    @Test("Stage 1 configures OpenConfiguration with hides=true, activates=false, and arguments")
    func stage1Configuration() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            pollingInterval: .milliseconds(10),
            pollingTimeout: .milliseconds(50),
            sleep: { _ in }
        )

        let app = ManagedApp(
            name: "Discord",
            bundlePath: "/Applications/Discord.app",
            launchHidden: true,
            customArguments: "--start-minimized"
        )

        try await engine.launch(app: app)

        #expect(mockWorkspace.openedURLs.count == 1)
        #expect(mockWorkspace.openedURLs.first == app.bundleURL)
        #expect(mockWorkspace.configurations.first?.hides == true)
        #expect(mockWorkspace.configurations.first?.activates == false)
        #expect(mockWorkspace.configurations.first?.arguments == ["--start-minimized"])
    }

    @Test("Stage 2 polls isFinishedLaunching and calls hide() and enters guarding state")
    func stage2PollingAndGuarding() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let runningApp = MockRunningApp(processIdentifier: 5555, isFinishedLaunching: true)
        mockWorkspace.stubbedRunningApp = runningApp

        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            pollingInterval: .milliseconds(10),
            pollingTimeout: .milliseconds(50),
            sleep: { _ in }
        )

        let app = ManagedApp(
            name: "Steam",
            bundlePath: "/Applications/Steam.app",
            launchHidden: true
        )

        try await engine.launch(app: app)

        #expect(runningApp.hideCallCount == 1)
        #expect(engine.isGuarding(appId: app.id))
        #expect(engine.isGuarding)
    }

    @Test("Stage 2 waits until isFinishedLaunching becomes true then calls hide()")
    func stage2WaitsUntilFinishedLaunching() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let runningApp = MockRunningApp(processIdentifier: 6666, isFinishedLaunching: false)
        mockWorkspace.stubbedRunningApp = runningApp

        var sleepCallCount = 0
        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            pollingInterval: .milliseconds(10),
            pollingTimeout: .milliseconds(50),
            sleep: { _ in
                sleepCallCount += 1
                if sleepCallCount >= 2 {
                    runningApp.isFinishedLaunching = true
                }
            }
        )

        let app = ManagedApp(
            name: "Slack",
            bundlePath: "/Applications/Slack.app",
            launchHidden: true
        )

        try await engine.launch(app: app)

        #expect(sleepCallCount >= 2)
        #expect(runningApp.hideCallCount >= 2)
        #expect(engine.isGuarding(appId: app.id))
    }

    @Test("Stage 2 times out gracefully after pollingTimeout and still calls hide()")
    func stage2TimesOutGracefully() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let runningApp = MockRunningApp(processIdentifier: 7777, isFinishedLaunching: false)
        mockWorkspace.stubbedRunningApp = runningApp

        var sleepCallCount = 0
        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            pollingInterval: .milliseconds(10),
            pollingTimeout: .milliseconds(30),
            sleep: { _ in
                sleepCallCount += 1
            }
        )

        let app = ManagedApp(
            name: "UnfinishedApp",
            bundlePath: "/Applications/UnfinishedApp.app",
            launchHidden: true
        )

        try await engine.launch(app: app)

        #expect(sleepCallCount == 3)
        #expect(runningApp.hideCallCount == 4)
        #expect(engine.isGuarding(appId: app.id))
    }

    @Test("When launchHidden is false, Stage 2 is skipped completely and app is not guarded")
    func nonHiddenAppSkipsStage2() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let runningApp = MockRunningApp(processIdentifier: 8888, isFinishedLaunching: true)
        mockWorkspace.stubbedRunningApp = runningApp

        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            pollingInterval: .milliseconds(10),
            pollingTimeout: .milliseconds(50),
            sleep: { _ in }
        )

        let app = ManagedApp(
            name: "Calculator",
            bundlePath: "/Applications/Calculator.app",
            launchHidden: false
        )

        try await engine.launch(app: app)

        #expect(mockWorkspace.configurations.first?.hides == false)
        #expect(mockWorkspace.configurations.first?.activates == true)
        #expect(runningApp.hideCallCount == 0)
        #expect(!engine.isGuarding)
        #expect(!engine.isGuarding(appId: app.id))
    }

    @Test("Workspace error prevents Stage 2 execution and throws")
    func workspaceErrorPreventsStage2() async {
        struct TestLaunchError: Error, Equatable {}
        let mockWorkspace = MockWorkspaceManager()
        mockWorkspace.shouldThrowError = TestLaunchError()

        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            pollingInterval: .milliseconds(10),
            pollingTimeout: .milliseconds(50),
            sleep: { _ in }
        )

        let app = ManagedApp(name: "Faulty", bundlePath: "/Applications/Faulty.app", launchHidden: true)

        do {
            try await engine.launch(app: app)
            Issue.record("Expected TestLaunchError was not thrown")
        } catch is TestLaunchError {
            // Expected error caught
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(!engine.isGuarding)
    }

    @Test("Cancellation during Stage 1 polling aborts launch and does not enter guarding state")
    func cancellationDuringStage1Aborts() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let runningApp = MockRunningApp(processIdentifier: 9988, isFinishedLaunching: false)
        mockWorkspace.stubbedRunningApp = runningApp

        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            pollingInterval: .milliseconds(50),
            pollingTimeout: .seconds(5),
            sleep: { _ in try await Task.sleep(for: .seconds(10)) }
        )

        let app = ManagedApp(name: "LongLaunchApp", bundlePath: "/Applications/LongLaunchApp.app", launchHidden: true)

        let task = Task {
            try await engine.launch(app: app)
        }

        try await Task.sleep(for: .milliseconds(20))
        task.cancel()

        let result = await task.result
        switch result {
        case .success:
            Issue.record("Launch was expected to throw CancellationError upon cancellation")
        case .failure(let error):
            #expect(error is CancellationError)
        }

        #expect(!engine.isGuarding)
        #expect(!engine.isGuarding(appId: app.id))
    }

    @Test("Launching multiple hidden apps guards all processes concurrently")
    func concurrentHiddenAppLaunchesGuardAll() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let app1Running = MockRunningApp(processIdentifier: 1111, isFinishedLaunching: true)
        let app2Running = MockRunningApp(processIdentifier: 2222, isFinishedLaunching: true)

        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            pollingInterval: .milliseconds(10),
            pollingTimeout: .milliseconds(50),
            sleep: { _ in }
        )

        let app1 = ManagedApp(name: "AppOne", bundlePath: "/Applications/AppOne.app", launchHidden: true)
        let app2 = ManagedApp(name: "AppTwo", bundlePath: "/Applications/AppTwo.app", launchHidden: true)

        mockWorkspace.stubbedRunningApp = app1Running
        try await engine.launch(app: app1)

        mockWorkspace.stubbedRunningApp = app2Running
        try await engine.launch(app: app2)

        #expect(engine.isGuarding(appId: app1.id))
        #expect(engine.isGuarding(appId: app2.id))
        #expect(engine.isGuarding)
    }

    @Test("Guarded app activation triggers hide()")
    func guardedAppActivationTriggersHide() async throws {
        let notificationCenter = NotificationCenter()
        let mockWorkspace = MockWorkspaceManager()
        let guardedApp = MockRunningApp(processIdentifier: 4321, isFinishedLaunching: true)
        mockWorkspace.stubbedRunningApp = guardedApp

        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            notificationCenter: notificationCenter,
            gracePeriod: .seconds(10),
            sleep: { _ in }
        )

        let app = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app", launchHidden: true)
        try await engine.launch(app: app)

        #expect(engine.isGuarding)
        let initialHides = guardedApp.hideCallCount // 1 hide from initial launch

        // Post activation notification for guarded app
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: guardedApp]
        )

        #expect(guardedApp.hideCallCount == initialHides + 1)
        engine.cancelAll()
        #expect(!engine.isGuarding)
    }

    @Test("Unrelated app activation does not trigger hide()")
    func unrelatedAppActivationDoesNotTriggerHide() async throws {
        let notificationCenter = NotificationCenter()
        let mockWorkspace = MockWorkspaceManager()
        let guardedApp = MockRunningApp(processIdentifier: 4321, isFinishedLaunching: true)
        mockWorkspace.stubbedRunningApp = guardedApp

        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            notificationCenter: notificationCenter,
            gracePeriod: .seconds(10),
            sleep: { _ in }
        )

        let app = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app", launchHidden: true)
        try await engine.launch(app: app)

        let initialHides = guardedApp.hideCallCount
        let otherApp = MockRunningApp(processIdentifier: 9999)

        // Post activation for other app
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: otherApp]
        )

        #expect(guardedApp.hideCallCount == initialHides)
        engine.cancelAll()
    }

    @Test("Grace period expiration cleanly stops guarding and unsubscribes")
    func gracePeriodExpirationStopsGuarding() async throws {
        let notificationCenter = NotificationCenter()
        let mockWorkspace = MockWorkspaceManager()
        let guardedApp = MockRunningApp(processIdentifier: 4321, isFinishedLaunching: true)
        mockWorkspace.stubbedRunningApp = guardedApp

        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            notificationCenter: notificationCenter,
            gracePeriod: .milliseconds(10),
            sleep: { _ in }
        )

        let app = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app", launchHidden: true)
        try await engine.launch(app: app)

        // Yield to allow grace period Task to execute
        try await Task.sleep(for: .milliseconds(50))

        #expect(!engine.isGuarding)
        #expect(!engine.isGuarding(appId: app.id))

        let currentHides = guardedApp.hideCallCount

        // Notification posted after expiration should NOT invoke hide
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: guardedApp]
        )
        #expect(guardedApp.hideCallCount == currentHides)
    }

    @Test("Explicit cancel by appId removes observer immediately")
    func explicitCancelByAppIdRemovesObserver() async throws {
        let notificationCenter = NotificationCenter()
        let mockWorkspace = MockWorkspaceManager()
        let guardedApp = MockRunningApp(processIdentifier: 4321, isFinishedLaunching: true)
        mockWorkspace.stubbedRunningApp = guardedApp

        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            notificationCenter: notificationCenter,
            gracePeriod: .seconds(10),
            sleep: { _ in }
        )

        let app = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app", launchHidden: true)
        try await engine.launch(app: app)
        #expect(engine.isGuarding)

        engine.cancel(appId: app.id)
        #expect(!engine.isGuarding)

        let currentHides = guardedApp.hideCallCount
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: guardedApp]
        )
        #expect(guardedApp.hideCallCount == currentHides)
    }

    @Test("Explicit cancel by ManagedApp removes observer immediately")
    func explicitCancelByManagedAppRemovesObserver() async throws {
        let notificationCenter = NotificationCenter()
        let mockWorkspace = MockWorkspaceManager()
        let guardedApp = MockRunningApp(processIdentifier: 4321, isFinishedLaunching: true)
        mockWorkspace.stubbedRunningApp = guardedApp

        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            notificationCenter: notificationCenter,
            gracePeriod: .seconds(10),
            sleep: { _ in }
        )

        let app = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app", launchHidden: true)
        try await engine.launch(app: app)
        #expect(engine.isGuarding)

        engine.cancel(app: app)
        #expect(!engine.isGuarding)
    }

    @Test("CancelAll stops all guards and removes observers")
    func cancelAllStopsAllGuards() async throws {
        let notificationCenter = NotificationCenter()
        let mockWorkspace = MockWorkspaceManager()
        let app1 = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app", launchHidden: true)
        let app2 = ManagedApp(name: "Steam", bundlePath: "/Applications/Steam.app", launchHidden: true)
        let running1 = MockRunningApp(processIdentifier: 1111, isFinishedLaunching: true)
        let running2 = MockRunningApp(processIdentifier: 2222, isFinishedLaunching: true)

        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            notificationCenter: notificationCenter,
            gracePeriod: .seconds(10),
            sleep: { _ in }
        )

        mockWorkspace.stubbedRunningApp = running1
        try await engine.launch(app: app1)
        mockWorkspace.stubbedRunningApp = running2
        try await engine.launch(app: app2)

        #expect(engine.isGuarding)
        engine.cancelAll()
        #expect(!engine.isGuarding)
        #expect(!engine.isGuarding(appId: app1.id))
        #expect(!engine.isGuarding(appId: app2.id))
    }

    @Test("Unhide notification triggers hide() for guarded app")
    func unhideNotificationTriggersHide() async throws {
        let notificationCenter = NotificationCenter()
        let mockWorkspace = MockWorkspaceManager()
        let appRunning = MockRunningApp(processIdentifier: 2002, isFinishedLaunching: true)
        mockWorkspace.stubbedRunningApp = appRunning

        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            notificationCenter: notificationCenter,
            gracePeriod: .seconds(20),
            sleep: { _ in }
        )

        let app = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app", launchHidden: true)
        try await engine.launch(app: app)

        let initialHides = appRunning.hideCallCount

        notificationCenter.post(
            name: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: appRunning]
        )
        #expect(appRunning.hideCallCount == initialHides + 1)
        engine.cancelAll()
    }

    @Test("Max suppression episodes threshold disarms process after budget is exhausted")
    func maxSuppressionEpisodesThresholdDisarms() async throws {
        let notificationCenter = NotificationCenter()
        let mockWorkspace = MockWorkspaceManager()
        let appRunning = MockRunningApp(processIdentifier: 3003, isFinishedLaunching: true)
        mockWorkspace.stubbedRunningApp = appRunning

        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            notificationCenter: notificationCenter,
            gracePeriod: .seconds(20),
            maxSuppressionEpisodes: 2,
            debounceInterval: 0,
            sleep: { _ in }
        )

        let app = ManagedApp(name: "Steam", bundlePath: "/Applications/Steam.app", launchHidden: true)
        try await engine.launch(app: app)

        let initialHides = appRunning.hideCallCount

        // Episode 1: updater window activation
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: appRunning]
        )
        #expect(appRunning.hideCallCount == initialHides + 1)
        #expect(engine.isGuarding(appId: app.id))
        #expect(engine.isGuarding)

        // Episode 2: main window unhide
        notificationCenter.post(
            name: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: appRunning]
        )
        #expect(appRunning.hideCallCount == initialHides + 2)
        // Disarmed after 2 episodes
        #expect(!engine.isGuarding(appId: app.id))
        #expect(!engine.isGuarding)

        // Episode 3 attempt (e.g. user intentional interaction): should NOT call hide
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: appRunning]
        )
        #expect(appRunning.hideCallCount == initialHides + 2)
    }

    @Test("Paired didActivate and didUnhide notifications within debounce window coalesce to single episode")
    func pairedNotificationsCoalesceToSingleEpisode() async throws {
        let notificationCenter = NotificationCenter()
        let mockWorkspace = MockWorkspaceManager()
        let appRunning = MockRunningApp(processIdentifier: 3004, isFinishedLaunching: true)
        mockWorkspace.stubbedRunningApp = appRunning

        var mockTime = Date()
        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            notificationCenter: notificationCenter,
            gracePeriod: .seconds(20),
            maxSuppressionEpisodes: 2,
            debounceInterval: 0.3,
            currentTime: { mockTime },
            sleep: { _ in }
        )

        let app = ManagedApp(name: "Steam", bundlePath: "/Applications/Steam.app", launchHidden: true)
        try await engine.launch(app: app)

        let initialHides = appRunning.hideCallCount

        // Event 1: didActivate
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: appRunning]
        )
        #expect(appRunning.hideCallCount == initialHides + 1)
        #expect(engine.isGuarding(appId: app.id))

        // Event 2: didUnhide 10ms later (within 300ms debounce window)
        mockTime = mockTime.addingTimeInterval(0.01)
        notificationCenter.post(
            name: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: appRunning]
        )
        // hide() is called again for safety, but episode is NOT incremented
        #expect(appRunning.hideCallCount == initialHides + 2)
        #expect(engine.isGuarding(appId: app.id))

        // Event 3: Subsequent activation after debounce window (0.5s later) -> Episode 2
        mockTime = mockTime.addingTimeInterval(0.5)
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: appRunning]
        )
        #expect(appRunning.hideCallCount == initialHides + 3)
        // Disarmed after 2 distinct suppression episodes
        #expect(!engine.isGuarding(appId: app.id))
    }

    @Test("Multi-notification Electron launch sequence is suppressed without premature disarming")
    func multiNotificationElectronLaunchSuppressed() async throws {
        let notificationCenter = NotificationCenter()
        let mockWorkspace = MockWorkspaceManager()
        let appRunning = MockRunningApp(processIdentifier: 3005, isFinishedLaunching: true)
        mockWorkspace.stubbedRunningApp = appRunning

        var mockTime = Date()
        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            notificationCenter: notificationCenter,
            gracePeriod: .seconds(20),
            maxSuppressionEpisodes: 3,
            debounceInterval: 0.3,
            currentTime: { mockTime },
            sleep: { _ in }
        )

        let app = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app", launchHidden: true)
        try await engine.launch(app: app)

        let initialHides = appRunning.hideCallCount

        // 1. Initial process launch handshake (paired didActivate + didUnhide within 10ms)
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: appRunning]
        )
        mockTime = mockTime.addingTimeInterval(0.01)
        notificationCenter.post(
            name: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: appRunning]
        )
        #expect(appRunning.hideCallCount == initialHides + 2)
        #expect(engine.isGuarding(appId: app.id))

        // 2. Asynchronous Electron window rendering 0.8s later (paired didActivate + didUnhide)
        mockTime = mockTime.addingTimeInterval(0.8)
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: appRunning]
        )
        mockTime = mockTime.addingTimeInterval(0.01)
        notificationCenter.post(
            name: NSWorkspace.didUnhideApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: appRunning]
        )
        #expect(appRunning.hideCallCount == initialHides + 4)
        #expect(engine.isGuarding(appId: app.id))

        // 3. User intentionally clicks Dock icon 2s later -> Episode 3 disarms guard
        mockTime = mockTime.addingTimeInterval(2.0)
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: appRunning]
        )
        #expect(appRunning.hideCallCount == initialHides + 5)
        #expect(!engine.isGuarding(appId: app.id))
    }

    @Test("Targeted cancellation cancels specific app without affecting other guarded processes")
    func targetedCancellation() async throws {
        let notificationCenter = NotificationCenter()
        let mockWorkspace = MockWorkspaceManager()
        let app1 = ManagedApp(name: "Discord", bundlePath: "/Applications/Discord.app", launchHidden: true)
        let app2 = ManagedApp(name: "Steam", bundlePath: "/Applications/Steam.app", launchHidden: true)
        let running1 = MockRunningApp(processIdentifier: 4001, isFinishedLaunching: true)
        let running2 = MockRunningApp(processIdentifier: 4002, isFinishedLaunching: true)

        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            notificationCenter: notificationCenter,
            gracePeriod: .seconds(20),
            sleep: { _ in }
        )

        mockWorkspace.stubbedRunningApp = running1
        try await engine.launch(app: app1)

        mockWorkspace.stubbedRunningApp = running2
        try await engine.launch(app: app2)

        #expect(engine.isGuarding(appId: app1.id))
        #expect(engine.isGuarding(appId: app2.id))

        let initialHides1 = running1.hideCallCount
        let initialHides2 = running2.hideCallCount

        // Cancel only app1
        engine.cancel(appId: app1.id)

        #expect(!engine.isGuarding(appId: app1.id))
        #expect(engine.isGuarding(appId: app2.id))
        #expect(engine.isGuarding)

        // Notification for app1 should be ignored
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: running1]
        )
        #expect(running1.hideCallCount == initialHides1)

        // Notification for app2 should still suppress
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: running2]
        )
        #expect(running2.hideCallCount == initialHides2 + 1)
        engine.cancelAll()
    }

    @Test("Independent timer expiration cleans up only the expired process")
    func independentTimerExpiration() async throws {
        let notificationCenter = NotificationCenter()
        let mockWorkspace = MockWorkspaceManager()
        let app1 = ManagedApp(name: "App1", bundlePath: "/Applications/App1.app", launchHidden: true)
        let app2 = ManagedApp(name: "App2", bundlePath: "/Applications/App2.app", launchHidden: true)
        let running1 = MockRunningApp(processIdentifier: 5001, isFinishedLaunching: true)
        let running2 = MockRunningApp(processIdentifier: 5002, isFinishedLaunching: true)

        var shouldSleepIndefinitely = false
        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            notificationCenter: notificationCenter,
            gracePeriod: .milliseconds(10),
            sleep: { _ in
                if shouldSleepIndefinitely {
                    try await Task.sleep(for: .seconds(100))
                }
            }
        )

        mockWorkspace.stubbedRunningApp = running1
        try await engine.launch(app: app1)
        try await Task.sleep(for: .milliseconds(50))

        #expect(!engine.isGuarding(appId: app1.id))

        // Now start app2 with long timer so it does not expire
        shouldSleepIndefinitely = true
        mockWorkspace.stubbedRunningApp = running2
        try await engine.launch(app: app2)

        #expect(engine.isGuarding(appId: app2.id))
        #expect(engine.isGuarding)

        let initialHides2 = running2.hideCallCount

        // app2 responds to notifications
        notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            userInfo: [NSWorkspace.applicationUserInfoKey: running2]
        )
        #expect(running2.hideCallCount == initialHides2 + 1)

        // Clean up
        engine.cancelAll()
        #expect(!engine.isGuarding)
    }
}
