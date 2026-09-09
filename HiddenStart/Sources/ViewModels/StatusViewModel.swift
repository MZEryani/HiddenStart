import Foundation
import Combine
import AppKit

@MainActor
public final class StatusViewModel: ObservableObject {
    public let title: String
    @Published public var statusMessage: String
    @Published public var managedApps: [ManagedApp] = []

    private let terminator: AppTerminating
    private let settingsStore: SettingsStoring
    private let workspaceManager: WorkspaceManaging
    private let appPicker: ApplicationPickerSelecting
    private let windowSuppressor: WindowSuppressing

    public init(
        title: String = "HiddenStart",
        statusMessage: String = "Ready",
        terminator: AppTerminating = SystemAppTerminator(),
        settingsStore: SettingsStoring? = nil,
        workspaceManager: WorkspaceManaging? = nil,
        appPicker: ApplicationPickerSelecting? = nil,
        windowSuppressor: WindowSuppressing? = nil
    ) {
        self.title = title
        self.statusMessage = statusMessage
        self.terminator = terminator

        let resolvedStore = settingsStore ?? SettingsStore()
        let resolvedWorkspace = workspaceManager ?? SystemWorkspaceManager()
        self.settingsStore = resolvedStore
        self.workspaceManager = resolvedWorkspace
        self.appPicker = appPicker ?? ApplicationPicker()
        self.windowSuppressor = windowSuppressor ?? WindowSuppressionEngine(workspaceManager: resolvedWorkspace)

        if settingsStore == nil {
            try? resolvedStore.load()
        }
        self.managedApps = resolvedStore.apps
    }

    public func quit() {
        terminator.terminate()
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
        do {
            try settingsStore.update(app)
            managedApps = settingsStore.apps
        } catch {
            statusMessage = "Failed to update app"
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
