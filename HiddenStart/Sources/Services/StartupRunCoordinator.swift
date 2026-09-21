import Foundation
import Combine

private final class CancellationResumer: @unchecked Sendable {
    private let lock = NSLock()
    private var isResumed = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var cancellable: AnyCancellable?

    func setContinuation(_ cont: CheckedContinuation<Void, Never>) {
        lock.lock()
        defer { lock.unlock() }
        if isResumed {
            cont.resume()
        } else {
            continuation = cont
        }
    }

    func setCancellable(_ canc: AnyCancellable?) {
        lock.lock()
        defer { lock.unlock() }
        if isResumed {
            canc?.cancel()
        } else {
            cancellable = canc
        }
    }

    func resume() {
        lock.lock()
        defer { lock.unlock() }
        guard !isResumed else { return }
        isResumed = true
        cancellable?.cancel()
        cancellable = nil
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
public final class StartupRunCoordinator: ObservableObject, StartupRunCoordinating {
    public typealias SleepFunction = @Sendable (Duration) async throws -> Void

    @Published public private(set) var state: StartupRunState

    public var statePublisher: AnyPublisher<StartupRunState, Never> {
        $state.eraseToAnyPublisher()
    }

    private let workspaceManager: WorkspaceManaging
    private let windowSuppressor: WindowSuppressing
    private let networkMonitor: NetworkMonitoring
    private let offlineTimeout: Duration
    private let deferredRetryDuration: Duration
    private let delaySleep: SleepFunction

    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var registeredApps: [UUID: ManagedApp] = [:]
    private var skippedGatedApps: [ManagedApp] = []
    private var offlineTimeoutTask: Task<Void, Never>?
    private var deferredRetryTask: Task<Void, Never>?
    private var networkObserverCancellable: AnyCancellable?

    public init(
        workspaceManager: WorkspaceManaging = SystemWorkspaceManager(),
        windowSuppressor: WindowSuppressing? = nil,
        networkMonitor: NetworkMonitoring? = nil,
        offlineTimeout: Duration = .seconds(60),
        deferredRetryDuration: Duration = .seconds(900),
        sleep: @escaping SleepFunction = { try await Task.sleep(for: $0) }
    ) {
        self.workspaceManager = workspaceManager
        self.windowSuppressor = windowSuppressor ?? WindowSuppressionEngine(workspaceManager: workspaceManager)
        let resolvedNetworkMonitor = networkMonitor ?? NetworkMonitor()
        self.networkMonitor = resolvedNetworkMonitor
        self.offlineTimeout = offlineTimeout
        self.deferredRetryDuration = deferredRetryDuration
        self.delaySleep = sleep
        self.state = StartupRunState(
            phase: .idle,
            remainingDelays: [:],
            waitingForNetworkAppIds: [],
            isNetworkConnected: resolvedNetworkMonitor.isConnected,
            skippedAppIds: []
        )
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
            state.phase = .idle
            return
        }

        networkMonitor.startMonitoring()

        var initialDelays: [UUID: Int] = [:]
        for app in appsToLaunch where app.delaySeconds > 0 {
            initialDelays[app.id] = app.delaySeconds
        }

        state = StartupRunState(
            phase: .running,
            remainingDelays: initialDelays,
            waitingForNetworkAppIds: [],
            isNetworkConnected: networkMonitor.isConnected,
            skippedAppIds: []
        )

        let hasNetworkGatedApp = appsToLaunch.contains { $0.waitForInternet }

        networkObserverCancellable = networkMonitor.isConnectedPublisher
            .sink { [weak self] isConnected in
                guard let self else { return }
                self.state.isNetworkConnected = isConnected
                if isConnected {
                    self.offlineTimeoutTask?.cancel()
                    self.offlineTimeoutTask = nil
                }
            }

        if hasNetworkGatedApp && !networkMonitor.isConnected {
            offlineTimeoutTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await self.delaySleep(self.offlineTimeout)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                if !self.networkMonitor.isConnected {
                    self.handleOfflineTimeout()
                }
            }
        }

        for app in appsToLaunch {
            let taskId = app.id
            tasks[taskId] = Task { @MainActor [weak self] in
                guard let self else { return }

                var remaining = app.delaySeconds
                while remaining > 0 {
                    if Task.isCancelled { break }
                    do {
                        try await self.delaySleep(.seconds(1))
                    } catch {
                        break
                    }
                    if Task.isCancelled { break }
                    remaining -= 1
                    if remaining > 0 {
                        self.state.remainingDelays[app.id] = remaining
                    }
                }

                self.state.remainingDelays.removeValue(forKey: app.id)

                if Task.isCancelled {
                    self.tasks.removeValue(forKey: taskId)
                    self.evaluateRunCompletion()
                    return
                }

                if app.waitForInternet && !self.networkMonitor.isConnected {
                    self.state.waitingForNetworkAppIds.insert(app.id)

                    await self.waitUntilConnected()

                    self.state.waitingForNetworkAppIds.remove(app.id)
                }

                if !Task.isCancelled {
                    await self.launchResolvedApp(app)
                }

                self.tasks.removeValue(forKey: taskId)
                self.evaluateRunCompletion()
            }
        }
    }

    public func cancelLaunch(for appWithId: UUID) {
        if let task = tasks.removeValue(forKey: appWithId) {
            task.cancel()
        }
        registeredApps.removeValue(forKey: appWithId)
        windowSuppressor.cancel(appId: appWithId)
        state.remainingDelays.removeValue(forKey: appWithId)
        state.waitingForNetworkAppIds.remove(appWithId)
        state.skippedAppIds.remove(appWithId)
        skippedGatedApps.removeAll(where: { $0.id == appWithId })

        let hasRemainingGatedApp = registeredApps.values.contains { $0.waitForInternet }
        if !hasRemainingGatedApp {
            offlineTimeoutTask?.cancel()
            offlineTimeoutTask = nil
        }

        if skippedGatedApps.isEmpty && deferredRetryTask != nil {
            deferredRetryTask?.cancel()
            deferredRetryTask = nil
        }

        evaluateRunCompletion()
    }

    public func cancelAll() {
        for (_, task) in tasks {
            task.cancel()
        }
        tasks.removeAll()
        windowSuppressor.cancelAll()
        skippedGatedApps.removeAll()

        offlineTimeoutTask?.cancel()
        offlineTimeoutTask = nil

        deferredRetryTask?.cancel()
        deferredRetryTask = nil

        networkObserverCancellable?.cancel()
        networkObserverCancellable = nil

        networkMonitor.stopMonitoring()

        state = StartupRunState(
            phase: .idle,
            remainingDelays: [:],
            waitingForNetworkAppIds: [],
            isNetworkConnected: networkMonitor.isConnected,
            skippedAppIds: []
        )
    }

    private func handleOfflineTimeout() {
        offlineTimeoutTask = nil
        var appsToSkip: [ManagedApp] = []
        var tasksToCancel: [Task<Void, Never>] = []

        for (id, app) in registeredApps where app.waitForInternet {
            if let task = tasks.removeValue(forKey: id) {
                tasksToCancel.append(task)
                appsToSkip.append(app)
            }
            state.remainingDelays.removeValue(forKey: id)
            state.waitingForNetworkAppIds.remove(id)
            state.skippedAppIds.insert(id)
        }

        skippedGatedApps = appsToSkip

        if !skippedGatedApps.isEmpty {
            startDeferredRetryObserver()
        } else {
            networkMonitor.stopMonitoring()
            evaluateRunCompletion()
        }

        for task in tasksToCancel {
            task.cancel()
        }
    }

    private func startDeferredRetryObserver() {
        if tasks.isEmpty {
            state.phase = .deferredRetry
        }

        deferredRetryTask?.cancel()
        deferredRetryTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let remainingWindow = self.deferredRetryDuration > self.offlineTimeout
                ? self.deferredRetryDuration - self.offlineTimeout
                : .zero

            await self.waitForNetworkConnection(timeout: remainingWindow)

            guard !Task.isCancelled else {
                self.networkMonitor.stopMonitoring()
                return
            }

            if self.networkMonitor.isConnected {
                let deferredToLaunch = self.skippedGatedApps
                self.skippedGatedApps.removeAll()
                self.state.phase = .running

                for app in deferredToLaunch {
                    if Task.isCancelled { break }
                    let taskId = app.id
                    self.tasks[taskId] = Task { @MainActor [weak self] in
                        guard let self else { return }
                        await self.launchResolvedApp(app)
                        self.state.skippedAppIds.remove(app.id)
                        self.tasks.removeValue(forKey: taskId)
                        self.evaluateRunCompletion()
                    }
                }
                if self.tasks.isEmpty {
                    self.evaluateRunCompletion()
                }
            } else {
                self.skippedGatedApps.removeAll()
                self.evaluateRunCompletion()
            }
            self.deferredRetryTask = nil
        }
    }

    private func evaluateRunCompletion() {
        if tasks.isEmpty {
            if deferredRetryTask != nil && !skippedGatedApps.isEmpty {
                state.phase = .deferredRetry
            } else {
                state.phase = .idle
                offlineTimeoutTask?.cancel()
                offlineTimeoutTask = nil
                networkObserverCancellable?.cancel()
                networkObserverCancellable = nil
                networkMonitor.stopMonitoring()
            }
        }
    }

    private func waitUntilConnected() async {
        await waitForNetworkConnection()
    }

    private func waitForNetworkConnection(timeout: Duration? = nil) async {
        if networkMonitor.isConnected { return }
        let resumer = CancellationResumer()

        let timeoutTask: Task<Void, Never>? = timeout.map { duration in
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.delaySleep(duration)
                    resumer.resume()
                } catch {
                    // Cancelled
                }
            }
        }

        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                resumer.setContinuation(continuation)
                let cancellable = self.networkMonitor.isConnectedPublisher
                    .filter { $0 }
                    .first()
                    .sink { _ in
                        resumer.resume()
                    }
                resumer.setCancellable(cancellable)
            }
        } onCancel: {
            timeoutTask?.cancel()
            resumer.resume()
        }

        timeoutTask?.cancel()
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

    public func launchImmediately(app: ManagedApp) async throws {
        try await self.windowSuppressor.launch(app: app)
    }

    private func launchResolvedApp(_ app: ManagedApp) async {
        try? await self.windowSuppressor.launch(app: app)
    }
}

