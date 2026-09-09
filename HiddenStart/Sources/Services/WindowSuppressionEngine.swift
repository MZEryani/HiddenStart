import AppKit
import Foundation

@MainActor
public final class WindowSuppressionEngine: WindowSuppressing {
    private let workspaceManager: WorkspaceManaging
    private let focusGuard: FocusGuarding
    private let pollingInterval: Duration
    private let pollingTimeout: Duration
    private let sleep: @MainActor (Duration) async throws -> Void

    public init(
        workspaceManager: WorkspaceManaging = SystemWorkspaceManager(),
        focusGuard: FocusGuarding? = nil,
        pollingInterval: Duration = .milliseconds(100),
        pollingTimeout: Duration = .seconds(3),
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.workspaceManager = workspaceManager
        self.focusGuard = focusGuard ?? FocusGuard()
        self.pollingInterval = pollingInterval
        self.pollingTimeout = pollingTimeout
        self.sleep = sleep
    }

    @discardableResult
    public func launch(app: ManagedApp) async throws -> any RunningAppRepresentable {
        let config = NSWorkspace.OpenConfiguration()
        config.hides = app.launchHidden
        config.activates = !app.launchHidden
        let args = app.argumentsArray
        if !args.isEmpty {
            config.arguments = args
        }

        let runningApp = try await workspaceManager.openApplication(at: app.bundleURL, configuration: config)

        if app.launchHidden {
            // Stage 2: Process Watcher & Focus Guard
            focusGuard.startGuarding(app: runningApp)

            runningApp.hide()
            var elapsed: Duration = .zero
            while !runningApp.isFinishedLaunching && elapsed < pollingTimeout {
                try await sleep(pollingInterval)
                elapsed += pollingInterval
                runningApp.hide()
            }
        }

        return runningApp
    }
}
