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
        let mockGuard = MockFocusGuard()
        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            focusGuard: mockGuard,
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

        _ = try await engine.launch(app: app)

        #expect(mockWorkspace.openedURLs.count == 1)
        #expect(mockWorkspace.openedURLs.first == app.bundleURL)
        #expect(mockWorkspace.configurations.first?.hides == true)
        #expect(mockWorkspace.configurations.first?.activates == false)
        #expect(mockWorkspace.configurations.first?.arguments == ["--start-minimized"])
    }

    @Test("Stage 2 polls isFinishedLaunching and calls hide() and activates FocusGuard")
    func stage2PollingAndFocusGuard() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockGuard = MockFocusGuard()
        let runningApp = MockRunningApp(processIdentifier: 5555, isFinishedLaunching: true)
        mockWorkspace.stubbedRunningApp = runningApp

        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            focusGuard: mockGuard,
            pollingInterval: .milliseconds(10),
            pollingTimeout: .milliseconds(50),
            sleep: { _ in }
        )

        let app = ManagedApp(
            name: "Steam",
            bundlePath: "/Applications/Steam.app",
            launchHidden: true
        )

        _ = try await engine.launch(app: app)

        #expect(runningApp.hideCallCount == 1)
        #expect(mockGuard.guardedApps.count == 1)
        #expect(mockGuard.guardedApps.first?.processIdentifier == 5555)
    }

    @Test("Stage 2 waits until isFinishedLaunching becomes true then calls hide()")
    func stage2WaitsUntilFinishedLaunching() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockGuard = MockFocusGuard()
        let runningApp = MockRunningApp(processIdentifier: 6666, isFinishedLaunching: false)
        mockWorkspace.stubbedRunningApp = runningApp

        var sleepCallCount = 0
        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            focusGuard: mockGuard,
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

        _ = try await engine.launch(app: app)

        #expect(sleepCallCount >= 2)
        #expect(runningApp.hideCallCount >= 2)
        #expect(mockGuard.guardedApps.count == 1)
    }

    @Test("Stage 2 times out gracefully after pollingTimeout and still calls hide()")
    func stage2TimesOutGracefully() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockGuard = MockFocusGuard()
        let runningApp = MockRunningApp(processIdentifier: 7777, isFinishedLaunching: false)
        mockWorkspace.stubbedRunningApp = runningApp

        var sleepCallCount = 0
        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            focusGuard: mockGuard,
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

        _ = try await engine.launch(app: app)

        #expect(sleepCallCount == 3)
        #expect(runningApp.hideCallCount == 4)
        #expect(mockGuard.guardedApps.count == 1)
    }

    @Test("When launchHidden is false, Stage 2 is skipped completely")
    func nonHiddenAppSkipsStage2() async throws {
        let mockWorkspace = MockWorkspaceManager()
        let mockGuard = MockFocusGuard()
        let runningApp = MockRunningApp(processIdentifier: 8888, isFinishedLaunching: true)
        mockWorkspace.stubbedRunningApp = runningApp

        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            focusGuard: mockGuard,
            pollingInterval: .milliseconds(10),
            pollingTimeout: .milliseconds(50),
            sleep: { _ in }
        )

        let app = ManagedApp(
            name: "Calculator",
            bundlePath: "/Applications/Calculator.app",
            launchHidden: false
        )

        _ = try await engine.launch(app: app)

        #expect(mockWorkspace.configurations.first?.hides == false)
        #expect(mockWorkspace.configurations.first?.activates == true)
        #expect(runningApp.hideCallCount == 0)
        #expect(mockGuard.guardedApps.isEmpty)
    }

    @Test("Workspace error prevents Stage 2 execution and throws")
    func workspaceErrorPreventsStage2() async {
        struct TestLaunchError: Error, Equatable {}
        let mockWorkspace = MockWorkspaceManager()
        mockWorkspace.shouldThrowError = TestLaunchError()
        let mockGuard = MockFocusGuard()

        let engine = WindowSuppressionEngine(
            workspaceManager: mockWorkspace,
            focusGuard: mockGuard,
            pollingInterval: .milliseconds(10),
            pollingTimeout: .milliseconds(50),
            sleep: { _ in }
        )

        let app = ManagedApp(name: "Faulty", bundlePath: "/Applications/Faulty.app", launchHidden: true)

        await #expect(throws: TestLaunchError.self) {
            try await engine.launch(app: app)
        }

        #expect(mockGuard.guardedApps.isEmpty)
    }
}
