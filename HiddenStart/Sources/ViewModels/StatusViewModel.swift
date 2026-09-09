import Foundation
import Combine
import AppKit

@MainActor
public final class StatusViewModel: ObservableObject {
    public let title: String
    @Published public var statusMessage: String
    @Published public var managedApps: [ManagedApp] = []
    @Published public var remainingDelays: [UUID: Int] = [:]

    private let terminator: AppTerminating
    private let settingsStore: SettingsStoring
    private let workspaceManager: WorkspaceManaging
    private let appPicker: ApplicationPickerSelecting
    private let windowSuppressor: WindowSuppressing
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
        launchCoordinator: LaunchCoordinating? = nil
    ) {
        self.title = title
        self.statusMessage = statusMessage
        self.terminator = terminator

        let resolvedStore = settingsStore ?? SettingsStore()
        let resolvedWorkspace = workspaceManager ?? SystemWorkspaceManager()
        let resolvedSuppressor = windowSuppressor ?? WindowSuppressionEngine(workspaceManager: resolvedWorkspace)
        self.settingsStore = resolvedStore
        self.workspaceManager = resolvedWorkspace
        self.appPicker = appPicker ?? ApplicationPicker()
        self.windowSuppressor = resolvedSuppressor

        let resolvedCoordinator = launchCoordinator ?? LaunchCoordinator(
            workspaceManager: resolvedWorkspace,
            windowSuppressor: resolvedSuppressor
        )
        self.launchCoordinator = resolvedCoordinator

        if settingsStore == nil {
            try? resolvedStore.load()
        }
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
                if self.launchCoordinator.isRunning || summary == "Ready" {
                    self.statusMessage = summary
                }
            }
            .store(in: &cancellables)
    }

    public func quit() {
        launchCoordinator.cancelAll()
        terminator.terminate()
    }

    public func startStartupRun() {
        launchCoordinator.startStartupRun(for: managedApps)
    }

    public func cancelLaunch(for id: UUID) {
        launchCoordinator.cancelLaunch(for: id)
    }

    public func addApplication() async {
        guard let newApp = await appPicker.pickApplication() else {
            return
        }

        do {
            try settingsStore.add(newApp)
            managedApps = settingsStore.apps
            statusMessage = "Added \(newApp.name)"
        } catch {
            statusMessage = "Failed to add \(newApp.name)"
        }
    }

    public func removeApplication(withId id: UUID) {
        launchCoordinator.cancelLaunch(for: id)
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
            statusMessage = "Updated \(app.name)"
        } catch {
            statusMessage = "Failed to update \(app.name)"
        }
    }

    public func testLaunch(app: ManagedApp) async {
        statusMessage = "Launching \(app.name)..."
        do {
            try await windowSuppressor.launch(app: app)
            statusMessage = "Test launch triggered for \(app.name)"
        } catch {
            statusMessage = "Launch failed: \(error.localizedDescription)"
        }
    }

    public func icon(for app: ManagedApp) -> NSImage {
        workspaceManager.icon(forFile: app.bundlePath)
    }
}
