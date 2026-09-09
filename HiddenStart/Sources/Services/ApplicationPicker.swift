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
    public init() {}

    public func pickApplication() async -> ManagedApp? {
        let panel = NSOpenPanel()
        panel.title = "Select Application to Manage"
        panel.showsResizeIndicator = true
        panel.showsHiddenFiles = false
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")

        let response = await panel.begin()
        guard response == .OK, let url = panel.url else {
            return nil
        }

        return BundleAppResolver.resolveApp(at: url)
    }
}
