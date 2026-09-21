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

    private let terminator: AppTerminating
    public let managedAppStore: ManagedAppStoring
    private let workspaceManager: WorkspaceManaging
    private let appPicker: ApplicationPickerSelecting
    private let windowSuppressor: WindowSuppressing
    public let autoStartManager: AutoStartManaging
    public let launchCoordinator: LaunchCoordinating
    private var cancellables = Set<AnyCancellable>()

    public init(
        title: String = "HiddenStart",
        statusMessage: String = "Ready",
        terminator: AppTerminating = SystemAppTerminator(),
        managedAppStore: ManagedAppStoring? = nil,
        workspaceManager: WorkspaceManaging? = nil,
        appPicker: ApplicationPickerSelecting? = nil,
        windowSuppressor: WindowSuppressing? = nil,
        networkMonitor: NetworkMonitoring? = nil,
        autoStartManager: AutoStartManaging? = nil,
        launchCoordinator: LaunchCoordinating? = nil
    ) {
        self.title = title
        self.statusMessage = statusMessage
        self.terminator = terminator

        let resolvedWorkspace = workspaceManager ?? SystemWorkspaceManager()
        let resolvedStore = managedAppStore ?? ManagedAppStore(workspaceManager: resolvedWorkspace)
        let resolvedSuppressor = windowSuppressor ?? WindowSuppressionEngine(workspaceManager: resolvedWorkspace)
        let resolvedAutoStart = autoStartManager ?? AutoStartManager()

        self.managedAppStore = resolvedStore
        self.workspaceManager = resolvedWorkspace
        self.appPicker = appPicker ?? ApplicationPicker()
        self.windowSuppressor = resolvedSuppressor
        self.autoStartManager = resolvedAutoStart

        self.autoStartStatus = resolvedAutoStart.status
        self.isAutoStartEnabled = resolvedAutoStart.isEnabled
        self.autoStartRequiresApproval = resolvedAutoStart.hasApprovalIssue

        let resolvedCoordinator = launchCoordinator ?? LaunchCoordinator(
            workspaceManager: resolvedWorkspace,
            windowSuppressor: resolvedSuppressor,
            networkMonitor: networkMonitor
        )
        self.launchCoordinator = resolvedCoordinator
        self.networkStatus = resolvedCoordinator.networkStatus

        if managedAppStore == nil {
            try? resolvedStore.load()
        }

        resolvedStore.refreshAppHealth()
        self.managedApps = resolvedStore.apps

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
        managedAppStore.refreshAppHealth()
        managedApps = managedAppStore.apps
        let appsToLaunch = managedApps.filter { !managedAppStore.isMissing(appId: $0.id) }
        launchCoordinator.startStartupRun(for: appsToLaunch)
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
        managedAppStore.isMissing(appId: app.id)
    }

    public func addApplication() async {
        guard let url = await appPicker.pickApplicationURL() else {
            return
        }

        do {
            let newApp = try managedAppStore.addApp(at: url)
            managedApps = managedAppStore.apps
            if newApp.isDiscord {
                statusMessage = "Added Discord (Launch Hidden configured; custom arguments empty)"
            } else {
                statusMessage = "Added \(newApp.name)"
            }
        } catch {
            statusMessage = "Failed to add application"
        }
    }

    public func removeApplication(withId id: UUID) {
        launchCoordinator.cancelLaunch(for: id)
        do {
            try managedAppStore.remove(withId: id)
            managedApps = managedAppStore.apps
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
            try managedAppStore.update(app)
            managedApps = managedAppStore.apps
        } catch {
            statusMessage = "Failed to update app"
        }
    }

    public func updateApplication(_ app: ManagedApp) {
        do {
            try managedAppStore.update(app)
            managedApps = managedAppStore.apps
            statusMessage = "Updated \(app.name)"
        } catch {
            statusMessage = "Failed to update \(app.name)"
        }
    }

    public func testLaunch(app: ManagedApp) async {
        managedAppStore.refreshAppHealth()
        managedApps = managedAppStore.apps

        if managedAppStore.isMissing(appId: app.id) {
            statusMessage = "Launch failed: Application not found"
            return
        }

        guard let appToLaunch = managedApps.first(where: { $0.id == app.id }) else {
            statusMessage = "Launch failed: Application not found"
            return
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
