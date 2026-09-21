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
    public let startupRunCoordinator: StartupRunCoordinating
    private var previousPhase: StartupRunState.Phase?
    private var cancellables = Set<AnyCancellable>()

    public init(
        title: String = "HiddenStart",
        statusMessage: String = "Ready",
        terminator: AppTerminating = SystemAppTerminator(),
        managedAppStore: ManagedAppStoring? = nil,
        workspaceManager: WorkspaceManaging? = nil,
        appPicker: ApplicationPickerSelecting? = nil,
        windowSuppressor: WindowSuppressing? = nil,
        autoStartManager: AutoStartManaging? = nil,
        startupRunCoordinator: StartupRunCoordinating? = nil
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

        let resolvedCoordinator = startupRunCoordinator ?? StartupRunCoordinator(
            workspaceManager: resolvedWorkspace,
            windowSuppressor: resolvedSuppressor
        )
        self.startupRunCoordinator = resolvedCoordinator
        self.networkStatus = Self.deriveNetworkStatus(from: resolvedCoordinator.state)

        if managedAppStore == nil {
            try? resolvedStore.load()
        }

        resolvedStore.refreshAppHealth()
        self.managedApps = resolvedStore.apps

        resolvedCoordinator.statePublisher
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                self.remainingDelays = state.remainingDelays
                self.networkStatus = Self.deriveNetworkStatus(from: state)

                if let derivedMessage = Self.deriveStatusMessage(from: state, apps: self.managedApps) {
                    if state.phase != .idle || self.previousPhase != nil || self.statusMessage == "Ready" {
                        self.statusMessage = derivedMessage
                    }
                }
                self.previousPhase = state.phase
            }
            .store(in: &cancellables)
    }

    public static func deriveNetworkStatus(from state: StartupRunState) -> String {
        if state.phase == .deferredRetry || !state.skippedAppIds.isEmpty {
            return "Skipped (Offline)"
        } else if !state.isNetworkConnected {
            return "Waiting for network..."
        } else {
            return "Network connected"
        }
    }

    public static func deriveStatusMessage(from state: StartupRunState, apps: [ManagedApp]) -> String? {
        if !state.remainingDelays.isEmpty {
            let sorted = state.remainingDelays.compactMap { (id, remaining) -> (String, Int)? in
                guard let app = apps.first(where: { $0.id == id }) else { return nil }
                return (app.name, remaining)
            }.sorted { $0.1 < $1.1 }
            if !sorted.isEmpty {
                return sorted.map { "\($0.0) in \($0.1)s" }.joined(separator: ", ")
            }
        }

        if !state.waitingForNetworkAppIds.isEmpty {
            return "Waiting for network..."
        }

        if state.phase == .deferredRetry || (!state.skippedAppIds.isEmpty && state.phase == .idle) {
            return "Skipped (Offline)"
        }

        if state.phase == .running {
            return "Launching..."
        }

        if state.phase == .idle {
            return "Ready"
        }

        return nil
    }

    public func quit() {
        startupRunCoordinator.cancelAll()
        terminator.terminate()
    }

    public func startStartupRun() {
        managedAppStore.refreshAppHealth()
        managedApps = managedAppStore.apps
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
        startupRunCoordinator.cancelLaunch(for: id)
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
            startupRunCoordinator.cancelLaunch(for: id)
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
