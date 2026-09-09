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
public final class LaunchCoordinator: ObservableObject, LaunchCoordinating {
    public typealias SleepFunction = @Sendable (Duration) async throws -> Void

    @Published public private(set) var remainingDelays: [UUID: Int] = [:]
    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var statusSummary: String = "Ready"
    @Published public private(set) var networkStatus: String = "Network connected"

    public var remainingDelaysPublisher: AnyPublisher<[UUID: Int], Never> {
        $remainingDelays.eraseToAnyPublisher()
    }

    public var statusSummaryPublisher: AnyPublisher<String, Never> {
        $statusSummary.eraseToAnyPublisher()
    }

    public var networkStatusPublisher: AnyPublisher<String, Never> {
        $networkStatus.eraseToAnyPublisher()
    }

    private let workspaceManager: WorkspaceManaging
    private let windowSuppressor: WindowSuppressing
    private let networkMonitor: NetworkMonitoring
    private let appResolver: AppResolving?
    private let settingsStore: SettingsStoring?
    private let offlineTimeout: Duration
    private let deferredRetryDuration: Duration
    private let delaySleep: SleepFunction

    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var registeredApps: [UUID: ManagedApp] = [:]
    private var launchedPids: [UUID: pid_t] = [:]
    private var waitingForNetworkApps: Set<UUID> = []
    private var skippedGatedApps: [ManagedApp] = []
    private var offlineTimeoutTask: Task<Void, Never>?
    private var deferredRetryTask: Task<Void, Never>?
    private var networkObserverCancellable: AnyCancellable?

    public init(
        workspaceManager: WorkspaceManaging = SystemWorkspaceManager(),
        windowSuppressor: WindowSuppressing? = nil,
        networkMonitor: NetworkMonitoring? = nil,
        appResolver: AppResolving? = nil,
        settingsStore: SettingsStoring? = nil,
        offlineTimeout: Duration = .seconds(60),
        deferredRetryDuration: Duration = .seconds(900),
        sleep: @escaping SleepFunction = { try await Task.sleep(for: $0) }
    ) {
        self.workspaceManager = workspaceManager
        self.windowSuppressor = windowSuppressor ?? WindowSuppressionEngine(workspaceManager: workspaceManager)
        let resolvedNetworkMonitor = networkMonitor ?? NetworkMonitor()
        self.networkMonitor = resolvedNetworkMonitor
        self.appResolver = appResolver
        self.settingsStore = settingsStore
        self.offlineTimeout = offlineTimeout
        self.deferredRetryDuration = deferredRetryDuration
        self.delaySleep = sleep
        self.networkStatus = resolvedNetworkMonitor.isConnected ? "Network connected" : "Waiting for network..."
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
        networkMonitor.startMonitoring()

        let hasNetworkGatedApp = appsToLaunch.contains { $0.waitForInternet }
        if networkMonitor.isConnected {
            networkStatus = "Network connected"
        } else {
            networkStatus = "Waiting for network..."
        }

        networkObserverCancellable = networkMonitor.isConnectedPublisher
            .sink { [weak self] isConnected in
                guard let self else { return }
                if isConnected {
                    if self.networkStatus == "Waiting for network..." {
                        self.networkStatus = "Network connected"
                    }
                    self.offlineTimeoutTask?.cancel()
                    self.offlineTimeoutTask = nil
                }
            }

        if hasNetworkGatedApp && !networkMonitor.isConnected {
            offlineTimeoutTask = Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try await Task.sleep(for: self.offlineTimeout)
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
                        try await self.delaySleep(.seconds(1))
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

                if Task.isCancelled {
                    self.tasks.removeValue(forKey: taskId)
                    if self.tasks.isEmpty {
                        self.isRunning = false
                        self.updateStatusSummary()
                        if self.deferredRetryTask == nil {
                            self.networkMonitor.stopMonitoring()
                        }
                    }
                    return
                }

                if app.waitForInternet && !self.networkMonitor.isConnected {
                    self.waitingForNetworkApps.insert(app.id)
                    self.updateStatusSummary()

                    await self.waitUntilConnected()

                    self.waitingForNetworkApps.remove(app.id)
                    self.updateStatusSummary()
                }

                if !Task.isCancelled {
                    await self.launchResolvedApp(app)
                }

                self.tasks.removeValue(forKey: taskId)

                if self.tasks.isEmpty {
                    self.isRunning = false
                    self.updateStatusSummary()
                    if self.deferredRetryTask == nil {
                        self.networkMonitor.stopMonitoring()
                    }
                }
            }
        }
    }

    public func cancelLaunch(for appWithId: UUID) {
        if let task = tasks.removeValue(forKey: appWithId) {
            task.cancel()
        }
        if let pid = launchedPids.removeValue(forKey: appWithId) {
            windowSuppressor.cancel(processIdentifier: pid)
        }
        remainingDelays.removeValue(forKey: appWithId)
        waitingForNetworkApps.remove(appWithId)
        skippedGatedApps.removeAll(where: { $0.id == appWithId })

        if tasks.isEmpty {
            isRunning = false
            if deferredRetryTask == nil {
                networkMonitor.stopMonitoring()
            }
        }
        updateStatusSummary()
    }

    public func cancelAll() {
        for (_, task) in tasks {
            task.cancel()
        }
        tasks.removeAll()
        windowSuppressor.cancelAll()
        launchedPids.removeAll()
        remainingDelays.removeAll()
        waitingForNetworkApps.removeAll()
        skippedGatedApps.removeAll()

        offlineTimeoutTask?.cancel()
        offlineTimeoutTask = nil

        deferredRetryTask?.cancel()
        deferredRetryTask = nil

        networkObserverCancellable?.cancel()
        networkObserverCancellable = nil

        networkMonitor.stopMonitoring()

        isRunning = false
        updateStatusSummary()
    }

    private func handleOfflineTimeout() {
        offlineTimeoutTask = nil
        var appsToSkip: [ManagedApp] = []

        for (id, app) in registeredApps where app.waitForInternet {
            if let task = tasks.removeValue(forKey: id) {
                task.cancel()
                appsToSkip.append(app)
            }
            remainingDelays.removeValue(forKey: id)
            waitingForNetworkApps.remove(id)
        }

        skippedGatedApps = appsToSkip
        networkStatus = "Skipped (Offline)"

        if tasks.isEmpty {
            isRunning = false
        }
        updateStatusSummary()

        if !skippedGatedApps.isEmpty {
            startDeferredRetryObserver()
        } else {
            networkMonitor.stopMonitoring()
        }
    }

    private func startDeferredRetryObserver() {
        deferredRetryTask?.cancel()
        deferredRetryTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let remainingWindow = self.deferredRetryDuration > self.offlineTimeout
                ? self.deferredRetryDuration - self.offlineTimeout
                : .zero

            let resumer = CancellationResumer()

            let timeoutTask = Task { [weak self] in
                guard self != nil else { return }
                do {
                    try await Task.sleep(for: remainingWindow)
                    resumer.resume()
                } catch {
                    // Cancelled
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
                timeoutTask.cancel()
                resumer.resume()
            }

            timeoutTask.cancel()

            guard !Task.isCancelled else {
                self.networkMonitor.stopMonitoring()
                return
            }

            if self.networkMonitor.isConnected {
                let deferredToLaunch = self.skippedGatedApps
                self.skippedGatedApps.removeAll()
                self.networkStatus = "Network connected"

                for app in deferredToLaunch {
                    if Task.isCancelled { break }
                    let taskId = app.id
                    self.tasks[taskId] = Task { @MainActor [weak self] in
                        guard let self else { return }
                        await self.launchResolvedApp(app)
                        self.tasks.removeValue(forKey: taskId)
                        if self.tasks.isEmpty {
                            self.isRunning = false
                            self.updateStatusSummary()
                            self.networkMonitor.stopMonitoring()
                        }
                    }
                }
                self.isRunning = !self.tasks.isEmpty
                self.updateStatusSummary()
            } else {
                self.skippedGatedApps.removeAll()
                self.networkMonitor.stopMonitoring()
            }
            self.deferredRetryTask = nil
        }
    }

    private func waitUntilConnected() async {
        if networkMonitor.isConnected { return }
        let resumer = CancellationResumer()

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
            resumer.resume()
        }
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
            if !waitingForNetworkApps.isEmpty {
                statusSummary = "Waiting for network..."
                return
            }
            if networkStatus == "Skipped (Offline)" && !isRunning {
                statusSummary = "Skipped (Offline)"
                return
            }
            statusSummary = isRunning ? "Launching..." : "Ready"
            return
        }

        let sorted = remainingDelays.compactMap { (id, remaining) -> (String, Int)? in
            guard let app = registeredApps[id] else { return nil }
            return (app.name, remaining)
        }.sorted { $0.1 < $1.1 }

        statusSummary = sorted.map { "\($0.0) in \($0.1)s" }.joined(separator: ", ")
    }

    private func launchResolvedApp(_ app: ManagedApp) async {
        if let appResolver = self.appResolver {
            let resolution = appResolver.resolveApp(app)
            switch resolution {
            case .valid(let validApp):
                if let running = try? await self.windowSuppressor.launch(app: validApp) {
                    self.launchedPids[app.id] = running.processIdentifier
                }
            case .healed(let healedApp):
                try? self.settingsStore?.update(healedApp)
                if let running = try? await self.windowSuppressor.launch(app: healedApp) {
                    self.launchedPids[app.id] = running.processIdentifier
                }
            case .missing:
                break
            }
        } else {
            if let running = try? await self.windowSuppressor.launch(app: app) {
                self.launchedPids[app.id] = running.processIdentifier
            }
        }
    }
}
