import AppKit
import Foundation

@MainActor
public final class WindowSuppressionEngine: NSObject, WindowSuppressing {
    public static let defaultMaxSuppressionEpisodes = 3
    public static let defaultDebounceInterval: TimeInterval = 0.3
    public static let defaultGracePeriod: Duration = .seconds(20)
    public static let defaultPollingInterval: Duration = .milliseconds(100)
    public static let defaultPollingTimeout: Duration = .seconds(3)

    private struct SuppressionEpisodeBudget {
        let maxEpisodes: Int
        let debounceInterval: TimeInterval
        private(set) var episodeCount: Int = 0
        private(set) var lastEpisodeTime: Date = .distantPast

        init(maxEpisodes: Int, debounceInterval: TimeInterval) {
            self.maxEpisodes = maxEpisodes
            self.debounceInterval = debounceInterval
        }

        var isExhausted: Bool {
            episodeCount >= maxEpisodes
        }

        @discardableResult
        mutating func recordEpisode(at now: Date) -> Bool {
            if now.timeIntervalSince(lastEpisodeTime) < debounceInterval {
                return false
            }
            episodeCount += 1
            lastEpisodeTime = now
            return true
        }
    }

    private struct GuardEntry {
        let appId: UUID
        let processIdentifier: pid_t
        let app: any RunningAppRepresentable
        var budget: SuppressionEpisodeBudget
        var timeoutTask: Task<Void, Never>?
    }

    private let workspaceManager: WorkspaceManaging
    private let notificationCenter: NotificationCenter
    private let pollingInterval: Duration
    private let pollingTimeout: Duration
    private let gracePeriod: Duration
    private let maxSuppressionEpisodes: Int
    private let debounceInterval: TimeInterval
    private let currentTime: @MainActor () -> Date
    private let sleep: @MainActor (Duration) async throws -> Void

    private var entriesByAppId: [UUID: GuardEntry] = [:]
    private var appIdByPid: [pid_t: UUID] = [:]
    private var isObserving: Bool = false

    public var isGuarding: Bool {
        !entriesByAppId.isEmpty
    }

    public init(
        workspaceManager: WorkspaceManaging = SystemWorkspaceManager(),
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        pollingInterval: Duration = WindowSuppressionEngine.defaultPollingInterval,
        pollingTimeout: Duration = WindowSuppressionEngine.defaultPollingTimeout,
        gracePeriod: Duration = WindowSuppressionEngine.defaultGracePeriod,
        maxSuppressionEpisodes: Int = WindowSuppressionEngine.defaultMaxSuppressionEpisodes,
        debounceInterval: TimeInterval = WindowSuppressionEngine.defaultDebounceInterval,
        currentTime: @escaping @MainActor () -> Date = { Date() },
        sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.workspaceManager = workspaceManager
        self.notificationCenter = notificationCenter
        self.pollingInterval = pollingInterval
        self.pollingTimeout = pollingTimeout
        self.gracePeriod = gracePeriod
        self.maxSuppressionEpisodes = maxSuppressionEpisodes
        self.debounceInterval = debounceInterval
        self.currentTime = currentTime
        self.sleep = sleep
        super.init()
    }

    deinit {
        for entry in entriesByAppId.values {
            entry.timeoutTask?.cancel()
        }
        notificationCenter.removeObserver(self)
    }

    public func isGuarding(appId: UUID) -> Bool {
        entriesByAppId[appId] != nil
    }

    public func launch(app: ManagedApp) async throws {
        let config = NSWorkspace.OpenConfiguration()
        config.hides = app.launchHidden
        config.activates = !app.launchHidden
        let args = app.argumentsArray
        if !args.isEmpty {
            config.arguments = args
        }

        let runningApp = try await workspaceManager.openApplication(at: app.bundleURL, configuration: config)

        if app.launchHidden {
            // Stage 1: Active hide polling
            runningApp.hide()
            var elapsed: Duration = .zero
            while !runningApp.isFinishedLaunching && elapsed < pollingTimeout {
                try Task.checkCancellation()
                try await sleep(pollingInterval)
                elapsed += pollingInterval
                runningApp.hide()
            }

            try Task.checkCancellation()

            // Stage 2: Process Watcher & Focus Guard (grace period)
            startGuarding(appId: app.id, runningApp: runningApp)
        }
    }

    public func cancel(appId: UUID) {
        stopGuarding(appId: appId)
    }

    public func cancel(app: ManagedApp) {
        cancel(appId: app.id)
    }

    public func cancelAll() {
        for entry in entriesByAppId.values {
            entry.timeoutTask?.cancel()
        }
        entriesByAppId.removeAll()
        appIdByPid.removeAll()
        removeObserversIfEmpty()
    }

    private func startGuarding(appId: UUID, runningApp: any RunningAppRepresentable) {
        stopGuarding(appId: appId)
        let pid = runningApp.processIdentifier
        if let existingAppId = appIdByPid[pid] {
            stopGuarding(appId: existingAppId)
        }

        addObserversIfNeeded()

        let timeoutTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.sleep(self.gracePeriod)
                self.stopGuarding(appId: appId)
            } catch {
                // Task cancelled
            }
        }

        let entry = GuardEntry(
            appId: appId,
            processIdentifier: pid,
            app: runningApp,
            budget: SuppressionEpisodeBudget(
                maxEpisodes: maxSuppressionEpisodes,
                debounceInterval: debounceInterval
            ),
            timeoutTask: timeoutTask
        )
        entriesByAppId[appId] = entry
        appIdByPid[pid] = appId
    }

    private func stopGuarding(appId: UUID) {
        if let entry = entriesByAppId.removeValue(forKey: appId) {
            entry.timeoutTask?.cancel()
            appIdByPid.removeValue(forKey: entry.processIdentifier)
        }
        removeObserversIfEmpty()
    }

    private func addObserversIfNeeded() {
        guard !isObserving else { return }
        isObserving = true
        notificationCenter.addObserver(
            self,
            selector: #selector(handleApplicationEvent(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(handleApplicationEvent(_:)),
            name: NSWorkspace.didUnhideApplicationNotification,
            object: nil
        )
    }

    private func removeObserversIfEmpty() {
        guard entriesByAppId.isEmpty, isObserving else { return }
        isObserving = false
        notificationCenter.removeObserver(self, name: NSWorkspace.didActivateApplicationNotification, object: nil)
        notificationCenter.removeObserver(self, name: NSWorkspace.didUnhideApplicationNotification, object: nil)
    }

    @objc private func handleApplicationEvent(_ notification: Notification) {
        guard let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? any RunningAppRepresentable else {
            return
        }
        let pid = activated.processIdentifier
        guard let appId = appIdByPid[pid], var entry = entriesByAppId[appId] else { return }

        entry.app.hide()

        let now = currentTime()
        entry.budget.recordEpisode(at: now)

        if entry.budget.isExhausted {
            stopGuarding(appId: appId)
        } else {
            entriesByAppId[appId] = entry
        }
    }
}
