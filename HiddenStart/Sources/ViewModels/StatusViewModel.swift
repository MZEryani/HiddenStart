import Foundation
import Combine
import AppKit

@MainActor
public final class StatusViewModel: ObservableObject {
    public let title: String
    @Published public var statusMessage: String
    @Published public var networkStatus: String
    @Published public var networkStatusLevel: NetworkStatusLevel
    @Published public var managedApps: [ManagedApp] = []
    @Published public var remainingDelays: [UUID: Int] = [:]
    @Published public var autoStartStatus: AutoStartStatus = .notRegistered
    @Published public var isAutoStartEnabled: Bool = false
    @Published public var autoStartRequiresApproval: Bool = false

    public let managedAppStore: ManagedAppStoring
    public let startupRunCoordinator: StartupRunCoordinating
    public let autoStartManager: AutoStartManager
    private let appPicker: ApplicationPicker
    private let workspaceManager: WorkspaceManaging
    private let terminateApp: @MainActor () -> Void
    private var presenter: StatusPresenter
    private var cancellables = Set<AnyCancellable>()

    public init(
        title: String = "HiddenStart",
        statusMessage: String = "Ready",
        managedAppStore: ManagedAppStoring? = nil,
        startupRunCoordinator: StartupRunCoordinating? = nil,
        autoStartManager: AutoStartManager? = nil,
        appPicker: ApplicationPicker? = nil,
        workspaceManager: WorkspaceManaging? = nil,
        terminateApp: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }
    ) {
        self.title = title
        self.terminateApp = terminateApp

        let resolvedWorkspace = workspaceManager ?? SystemWorkspaceManager()
        let resolvedStore = managedAppStore ?? ManagedAppStore(workspaceManager: resolvedWorkspace)
        let resolvedAutoStart = autoStartManager ?? AutoStartManager()

        self.managedAppStore = resolvedStore
        self.workspaceManager = resolvedWorkspace
        self.appPicker = appPicker ?? ApplicationPicker()
        self.autoStartManager = resolvedAutoStart

        self.autoStartStatus = resolvedAutoStart.status
        self.isAutoStartEnabled = resolvedAutoStart.isEnabled
        self.autoStartRequiresApproval = resolvedAutoStart.hasApprovalIssue

        let resolvedCoordinator = startupRunCoordinator ?? StartupRunCoordinator(
            workspaceManager: resolvedWorkspace
        )
        self.startupRunCoordinator = resolvedCoordinator

        let initialPresenter = StatusPresenter(
            initialMessage: statusMessage,
            initialLevel: StatusPresenter.deriveNetworkStatusLevel(from: resolvedCoordinator.state)
        )
        self.presenter = initialPresenter
        self.statusMessage = initialPresenter.currentDisplay.message
        self.networkStatusLevel = initialPresenter.currentDisplay.networkStatusLevel
        self.networkStatus = initialPresenter.currentDisplay.networkStatusText

        if managedAppStore == nil {
            try? resolvedStore.load()
        }

        // Single subscription — managedApps stays in sync with the store automatically.
        // @Published fires synchronously on @MainActor, so managedApps is seeded before init returns.
        resolvedStore.appsPublisher
            .sink { [weak self] apps in
                self?.managedApps = apps
            }
            .store(in: &cancellables)

        resolvedCoordinator.statePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                let display = self.presenter.update(state: state, apps: self.managedApps)
                self.remainingDelays = display.remainingDelays
                self.networkStatusLevel = display.networkStatusLevel
                self.networkStatus = display.networkStatusText
                self.statusMessage = display.message
            }
            .store(in: &cancellables)
    }

    public func quit() {
        startupRunCoordinator.cancelAll()
        terminateApp()
    }


    private func setActionMessage(_ message: String) {
        let display = presenter.setActionMessage(message)
        statusMessage = display.message
    }

    public func startStartupRun() {
        let appsToLaunch = managedApps.filter { !managedAppStore.isMissing(appId: $0.id) }
        startupRunCoordinator.startStartupRun(for: appsToLaunch)
    }

    public func cancelLaunch(for id: UUID) {
        startupRunCoordinator.cancelLaunch(for: id)
    }

    public func toggleAutoStart() {
        do {
            try autoStartManager.toggle()
            syncAutoStartState()
        } catch {
            setActionMessage("Failed to update login item: \(error.localizedDescription)")
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
            if newApp.isDiscord {
                setActionMessage("Added Discord (Launch Hidden configured; custom arguments empty)")
            } else {
                setActionMessage("Added \(newApp.name)")
            }
        } catch {
            setActionMessage("Failed to add application")
        }
    }

    public func removeApplication(withId id: UUID) {
        startupRunCoordinator.cancelLaunch(for: id)
        do {
            try managedAppStore.remove(withId: id)
            setActionMessage("Removed app")
        } catch {
            setActionMessage("Failed to remove app")
        }
    }

    public func toggleAppEnabled(withId id: UUID) {
        guard let index = managedApps.firstIndex(where: { $0.id == id }) else { return }
        var app = managedApps[index]
        app.isEnabled.toggle()
        if !app.isEnabled {
            startupRunCoordinator.cancelLaunch(for: id)
        }
        do {
            try managedAppStore.update(app)
        } catch {
            setActionMessage("Failed to update app")
        }
    }

    public func updateApplication(_ app: ManagedApp) {
        do {
            try managedAppStore.update(app)
            setActionMessage("Updated \(app.name)")
        } catch {
            setActionMessage("Failed to update \(app.name)")
        }
    }

    public func testLaunch(app: ManagedApp) async {
        if managedAppStore.isMissing(appId: app.id) {
            setActionMessage("Launch failed: Application not found")
            return
        }

        guard let storeApp = managedApps.first(where: { $0.id == app.id }) else {
            setActionMessage("Launch failed: Application not found")
            return
        }

        var appToLaunch = app
        appToLaunch.bundlePath = storeApp.bundlePath

        setActionMessage("Launching \(appToLaunch.name)...")

        do {
            try await startupRunCoordinator.launchImmediately(app: appToLaunch)
            setActionMessage("Test launch triggered for \(appToLaunch.name)")
        } catch {
            setActionMessage("Launch failed: \(error.localizedDescription)")
        }
    }

    public func icon(for app: ManagedApp) -> NSImage {
        workspaceManager.icon(forFile: app.bundlePath)
    }
}
