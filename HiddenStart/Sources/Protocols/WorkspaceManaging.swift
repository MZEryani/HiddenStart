@preconcurrency import AppKit

#if compiler(>=6.0)
extension NSWorkspace: @retroactive @unchecked Sendable {}
extension NSWorkspace.OpenConfiguration: @retroactive @unchecked Sendable {}
#else
extension NSWorkspace: @unchecked Sendable {}
extension NSWorkspace.OpenConfiguration: @unchecked Sendable {}
#endif

@MainActor
public protocol WorkspaceManaging: AnyObject, Sendable {
    var runningApplications: [any RunningAppRepresentable] { get }
    @discardableResult
    func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) async throws -> any RunningAppRepresentable
    func icon(forFile fullPath: String) -> NSImage
    func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL?
}

@MainActor
public final class SystemWorkspaceManager: WorkspaceManaging {
    private let workspace: NSWorkspace

    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    public var runningApplications: [any RunningAppRepresentable] {
        workspace.runningApplications
    }

    @discardableResult
    public func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) async throws -> any RunningAppRepresentable {
        let app = try await workspace.openApplication(at: url, configuration: configuration)
        return app
    }

    public func icon(forFile fullPath: String) -> NSImage {
        workspace.icon(forFile: fullPath)
    }

    public func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }
}
