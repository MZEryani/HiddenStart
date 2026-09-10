import AppKit
import UniformTypeIdentifiers

public enum BundleAppResolver {
    public static func resolveApp(at url: URL) -> ManagedApp {
        let bundle = Bundle(url: url)
        let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let bundleIdentifier = bundle?.bundleIdentifier
        return AppPreset.makeManagedApp(
            name: name,
            bundlePath: url.path,
            bundleIdentifier: bundleIdentifier
        )
    }
}

@MainActor
public final class ApplicationPicker: ApplicationPickerSelecting {
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

    public func pickApplication() async -> ManagedApp? {
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

        return BundleAppResolver.resolveApp(at: url)
    }
}
