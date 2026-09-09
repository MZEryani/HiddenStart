import AppKit

@MainActor
public protocol WorkspaceManaging: AnyObject, Sendable {
    var runningApplications: [any RunningAppRepresentable] { get }
    @discardableResult
    func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) async throws -> any RunningAppRepresentable
    func icon(forFile fullPath: String) -> NSImage
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
}
