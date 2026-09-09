import Foundation
import Combine

@MainActor
public final class LaunchCoordinator: ObservableObject, LaunchCoordinating {
    public typealias SleepFunction = @Sendable (Duration) async throws -> Void

    @Published public private(set) var remainingDelays: [UUID: Int] = [:]
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var statusSummary: String = "Ready"

    public var remainingDelaysPublisher: AnyPublisher<[UUID: Int], Never> {
        $remainingDelays.eraseToAnyPublisher()
    }

    public var statusSummaryPublisher: AnyPublisher<String, Never> {
        $statusSummary.eraseToAnyPublisher()
    }

    private let workspaceManager: WorkspaceManaging
    private let windowSuppressor: WindowSuppressing
    private let sleep: SleepFunction

    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var registeredApps: [UUID: ManagedApp] = [:]

    public init(
        workspaceManager: WorkspaceManaging = SystemWorkspaceManager(),
        windowSuppressor: WindowSuppressing? = nil,
        sleep: @escaping SleepFunction = { try await Task.sleep(for: $0) }
    ) {
        self.workspaceManager = workspaceManager
        self.windowSuppressor = windowSuppressor ?? WindowSuppressionEngine(workspaceManager: workspaceManager)
        self.sleep = sleep
    }

    public func startStartupRun(for apps: [ManagedApp]) {
        cancelAll()

        let enabledApps = apps.filter { $0.isEnabled }
        registeredApps.removeAll()
        for app in enabledApps {
            registeredApps[app.id] = app
        }

        let appsToLaunch = enabledApps.filter { !isAppAlreadyRunning($0) }
        guard !appsToLaunch.isEmpty else {
            isRunning = false
            statusSummary = "Ready"
            return
        }

        isRunning = true

        for app in appsToLaunch {
            if app.delaySeconds > 0 {
                remainingDelays[app.id] = app.delaySeconds
            }
        }
        updateStatusSummary()

        for app in appsToLaunch {
            let taskId = app.id
            tasks[taskId] = Task { @MainActor [weak self] in
                guard let self else { return }

                var remaining = app.delaySeconds
                while remaining > 0 {
                    if Task.isCancelled { break }
                    do {
                        try await self.sleep(.seconds(1))
                    } catch {
                        break
                    }
                    if Task.isCancelled { break }
                    remaining -= 1
                    if remaining > 0 {
                        self.remainingDelays[app.id] = remaining
                        self.updateStatusSummary()
                    }
                }

                self.remainingDelays.removeValue(forKey: app.id)
                self.updateStatusSummary()

                if !Task.isCancelled {
                    _ = try? await self.windowSuppressor.launch(app: app)
                }

                self.tasks.removeValue(forKey: taskId)

                if self.tasks.isEmpty {
                    self.isRunning = false
                    self.updateStatusSummary()
                }
            }
        }
    }

    public func cancelLaunch(for appWithId: UUID) {
        if let task = tasks.removeValue(forKey: appWithId) {
            task.cancel()
        }
        remainingDelays.removeValue(forKey: appWithId)

        if tasks.isEmpty {
            isRunning = false
        }
        updateStatusSummary()
    }

    public func cancelAll() {
        for (_, task) in tasks {
            task.cancel()
        }
        tasks.removeAll()
        remainingDelays.removeAll()
        isRunning = false
        updateStatusSummary()
    }

    private func isAppAlreadyRunning(_ app: ManagedApp) -> Bool {
        let runningApps = workspaceManager.runningApplications
        return runningApps.contains { running in
            if let runningId = running.bundleIdentifier,
               let appIdentifier = app.bundleIdentifier,
               !appIdentifier.isEmpty,
               runningId.caseInsensitiveCompare(appIdentifier) == .orderedSame {
                return true
            }

            if let runningURL = running.bundleURL {
                if runningURL.standardizedFileURL.path == app.bundleURL.standardizedFileURL.path {
                    return true
                }
                if runningURL.lastPathComponent.caseInsensitiveCompare(app.bundleURL.lastPathComponent) == .orderedSame {
                    return true
                }
            }

            return false
        }
    }

    private func updateStatusSummary() {
        if remainingDelays.isEmpty {
            statusSummary = isRunning ? "Launching..." : "Ready"
            return
        }

        let sorted = remainingDelays.compactMap { (id, remaining) -> (String, Int)? in
            guard let app = registeredApps[id] else { return nil }
            return (app.name, remaining)
        }.sorted { $0.1 < $1.1 }

        statusSummary = sorted.map { "\($0.0) in \($0.1)s" }.joined(separator: ", ")
    }
}
