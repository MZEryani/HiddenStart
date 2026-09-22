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

    public let managedAppStore: ManagedAppStoring
    public let startupRunCoordinator: StartupRunCoordinating
    public let autoStartManager: AutoStartManager
    private let appPicker: ApplicationPicker
    private let workspaceManager: WorkspaceManaging
    private let terminateApp: @MainActor () -> Void
    private var previousPhase: StartupRunState.Phase?
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
        self.statusMessage = statusMessage
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
        self.networkStatus = Self.deriveNetworkStatus(from: resolvedCoordinator.state)

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
        terminateApp()
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
        } catch {
            statusMessage = "Failed to update app"
        }
    }

    public func updateApplication(_ app: ManagedApp) {
        do {
            try managedAppStore.update(app)
            statusMessage = "Updated \(app.name)"
        } catch {
            statusMessage = "Failed to update \(app.name)"
        }
    }

    public func testLaunch(app: ManagedApp) async {
        if managedAppStore.isMissing(appId: app.id) {
            statusMessage = "Launch failed: Application not found"
            return
        }

        guard let storeApp = managedApps.first(where: { $0.id == app.id }) else {
            statusMessage = "Launch failed: Application not found"
            return
        }

        var appToLaunch = app
        appToLaunch.bundlePath = storeApp.bundlePath

        statusMessage = "Launching \(appToLaunch.name)..."

        do {
            try await startupRunCoordinator.launchImmediately(app: appToLaunch)
            statusMessage = "Test launch triggered for \(appToLaunch.name)"
        } catch {
            statusMessage = "Launch failed: \(error.localizedDescription)"
        }
    }


    public func icon(for app: ManagedApp) -> NSImage {
        workspaceManager.icon(forFile: app.bundlePath)
    }
}
