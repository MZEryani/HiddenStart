import AppKit
import UniformTypeIdentifiers

@MainActor
public final class ApplicationPicker {
    private let appActivator: @MainActor (Bool) -> Void
    private let panelFactory: @MainActor () -> NSOpenPanel
    private let panelPresenter: @MainActor (NSOpenPanel) async -> (NSApplication.ModalResponse, URL?)

    public init(
        appActivator: @escaping @MainActor (Bool) -> Void = { NSApp.activate(ignoringOtherApps: $0) },
        panelFactory: @escaping @MainActor () -> NSOpenPanel = { NSOpenPanel() },
        panelPresenter: @escaping @MainActor (NSOpenPanel) async -> (NSApplication.ModalResponse, URL?) = { (await $0.begin(), $0.url) }
    ) {
        self.appActivator = appActivator
        self.panelFactory = panelFactory
        self.panelPresenter = panelPresenter
    }

    public func pickApplicationURL() async -> URL? {
        appActivator(true)

        let panel = panelFactory()
        panel.title = "Select Application to Manage"
        panel.showsHiddenFiles = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        let (response, chosenURL) = await panelPresenter(panel)
        guard response == .OK, let url = chosenURL else {
            return nil
        }

        return url
    }
}
