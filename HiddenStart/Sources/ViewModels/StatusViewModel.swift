import Foundation
import Combine
import AppKit

@MainActor
public final class StatusViewModel: ObservableObject {
    public let title: String
    @Published public var statusMessage: String
    @Published public var networkStatus: String
    @Published public var managedApps: [ManagedApp] = []
    @Published public var remainingDelays: [UUID: Int] = [:]
    @Published public var autoStartStatus: AutoStartStatus = .notRegistered
    @Published public var isAutoStartEnabled: Bool = false
    @Published public var autoStartRequiresApproval: Bool = false
    @Published public var missingAppIds: Set<UUID> = []

    private let terminator: AppTerminating
    private let settingsStore: SettingsStoring
    private let workspaceManager: WorkspaceManaging
    private let appPicker: ApplicationPickerSelecting
    private let windowSuppressor: WindowSuppressing
    public let autoStartManager: AutoStartManaging
    private let appResolver: AppResolving
    public let launchCoordinator: LaunchCoordinating
    private var cancellables = Set<AnyCancellable>()

    public init(
        title: String = "HiddenStart",
        statusMessage: String = "Ready",
        terminator: AppTerminating = SystemAppTerminator(),
        settingsStore: SettingsStoring? = nil,
        workspaceManager: WorkspaceManaging? = nil,
        appPicker: ApplicationPickerSelecting? = nil,
        windowSuppressor: WindowSuppressing? = nil,
        networkMonitor: NetworkMonitoring? = nil,
        autoStartManager: AutoStartManaging? = nil,
        appResolver: AppResolving? = nil,
        launchCoordinator: LaunchCoordinating? = nil
    ) {
        self.title = title
        self.statusMessage = statusMessage
        self.terminator = terminator

        let resolvedStore = settingsStore ?? SettingsStore()
        let resolvedWorkspace = workspaceManager ?? SystemWorkspaceManager()
        let resolvedSuppressor = windowSuppressor ?? WindowSuppressionEngine(workspaceManager: resolvedWorkspace)
        let resolvedResolver = appResolver ?? AppResolver(workspaceManager: resolvedWorkspace)
        let resolvedAutoStart = autoStartManager ?? AutoStartManager()

        self.settingsStore = resolvedStore
        self.workspaceManager = resolvedWorkspace
        self.appPicker = appPicker ?? ApplicationPicker()
        self.windowSuppressor = resolvedSuppressor
        self.appResolver = resolvedResolver
        self.autoStartManager = resolvedAutoStart

        self.autoStartStatus = resolvedAutoStart.status
        self.isAutoStartEnabled = resolvedAutoStart.isEnabled
        self.autoStartRequiresApproval = resolvedAutoStart.hasApprovalIssue

        let resolvedCoordinator = launchCoordinator ?? LaunchCoordinator(
            workspaceManager: resolvedWorkspace,
            windowSuppressor: resolvedSuppressor,
            networkMonitor: networkMonitor,
            appResolver: resolvedResolver,
            settingsStore: resolvedStore
        )
        self.launchCoordinator = resolvedCoordinator
        self.networkStatus = resolvedCoordinator.networkStatus

        if settingsStore == nil {
            try? resolvedStore.load()
        }

        let healedApps = resolvedResolver.resolveAndHeal(apps: resolvedStore.apps, store: resolvedStore)
        self.managedApps = healedApps
        self.missingAppIds = Set(healedApps.filter { resolvedResolver.resolveApp($0).isMissing }.map(\.id))

        resolvedCoordinator.remainingDelaysPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] delays in
                guard let self else { return }
                self.remainingDelays = delays
            }
            .store(in: &cancellables)

        resolvedCoordinator.statusSummaryPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] summary in
                guard let self else { return }
                if self.launchCoordinator.isRunning || summary == "Ready" || summary == "Skipped (Offline)" || summary == "Waiting for network..." {
                    self.statusMessage = summary
                }
            }
            .store(in: &cancellables)

        resolvedCoordinator.networkStatusPublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                self.networkStatus = status
            }
            .store(in: &cancellables)
    }

    public func quit() {
        launchCoordinator.cancelAll()
        terminator.terminate()
    }

    public func startStartupRun() {
        resolveAndHealApps()
        launchCoordinator.startStartupRun(for: managedApps)
    }

    public func resolveAndHealApps() {
        let healedApps = appResolver.resolveAndHeal(apps: managedApps, store: settingsStore)
        self.managedApps = healedApps
        self.missingAppIds = Set(healedApps.filter { appResolver.resolveApp($0).isMissing }.map(\.id))
    }

    public func cancelLaunch(for id: UUID) {
        launchCoordinator.cancelLaunch(for: id)
    }

    public func toggleAutoStart() {
        do {
            try autoStartManager.toggle()
            syncAutoStartState()
        } catch {
            statusMessage = "Failed to update login item: \(error.localizedDescription)"
            syncAutoStartState()
        }
    }

    public func openSystemSettingsLoginItems() {
        autoStartManager.openSystemSettings()
    }

    public func refreshAutoStartStatus() {
        autoStartManager.refreshStatus()
        syncAutoStartState()
    }

    private func syncAutoStartState() {
        isAutoStartEnabled = autoStartManager.isEnabled
        autoStartStatus = autoStartManager.status
        autoStartRequiresApproval = autoStartManager.hasApprovalIssue
    }

    public func isAppMissing(_ app: ManagedApp) -> Bool {
        missingAppIds.contains(app.id)
    }

    public func checkAppResolution(for app: ManagedApp) {
        let resolution = appResolver.resolveApp(app)
        if resolution.isMissing {
            missingAppIds.insert(app.id)
        } else if resolution.isHealed {
            missingAppIds.remove(app.id)
            updateApplication(resolution.app)
        } else {
            missingAppIds.remove(app.id)
        }
    }

    public func addApplication() async {
        guard let newApp = await appPicker.pickApplication() else {
            return
        }

        do {
            try settingsStore.add(newApp)
            managedApps = settingsStore.apps
            checkAppResolution(for: newApp)
            if newApp.isDiscord {
                statusMessage = "Added Discord (Launch Hidden configured; custom arguments empty)"
            } else {
                statusMessage = "Added \(newApp.name)"
            }
        } catch {
            statusMessage = "Failed to add \(newApp.name)"
        }
    }

    public func removeApplication(withId id: UUID) {
        launchCoordinator.cancelLaunch(for: id)
        missingAppIds.remove(id)
        do {
            try settingsStore.remove(withId: id)
            managedApps = settingsStore.apps
            statusMessage = "Removed app"
        } catch {
            statusMessage = "Failed to remove app"
        }
    }

    public func toggleAppEnabled(withId id: UUID) {
        guard let index = managedApps.firstIndex(where: { $0.id == id }) else { return }
        var app = managedApps[index]
        app.isEnabled.toggle()
        if !app.isEnabled {
            launchCoordinator.cancelLaunch(for: id)
        }
        do {
            try settingsStore.update(app)
            managedApps = settingsStore.apps
        } catch {
            statusMessage = "Failed to update app"
        }
    }

    public func updateApplication(_ app: ManagedApp) {
        do {
            try settingsStore.update(app)
            managedApps = settingsStore.apps
            checkAppResolution(for: app)
            statusMessage = "Updated \(app.name)"
        } catch {
            statusMessage = "Failed to update \(app.name)"
        }
    }

    public func testLaunch(app: ManagedApp) async {
        let resolution = appResolver.resolveApp(app)
        if resolution.isMissing {
            missingAppIds.insert(app.id)
            statusMessage = "Launch failed: Application not found"
            return
        }

        let appToLaunch = resolution.app
        if resolution.isHealed {
            missingAppIds.remove(app.id)
            updateApplication(appToLaunch)
        } else {
            missingAppIds.remove(app.id)
        }

        statusMessage = "Launching \(appToLaunch.name)..."
        do {
            try await windowSuppressor.launch(app: appToLaunch)
            statusMessage = "Test launch triggered for \(appToLaunch.name)"
        } catch {
            statusMessage = "Launch failed: \(error.localizedDescription)"
        }
    }

    public func icon(for app: ManagedApp) -> NSImage {
        workspaceManager.icon(forFile: app.bundlePath)
    }
}
