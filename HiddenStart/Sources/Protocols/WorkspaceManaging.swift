import AppKit

@MainActor
public protocol WorkspaceManaging: AnyObject, Sendable {
    func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) async throws
    func icon(forFile fullPath: String) -> NSImage
}

@MainActor
public final class SystemWorkspaceManager: WorkspaceManaging {
    private let workspace: NSWorkspace

    public init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    public func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) async throws {
        _ = try await workspace.openApplication(at: url, configuration: configuration)
    }

    public func icon(forFile fullPath: String) -> NSImage {
        workspace.icon(forFile: fullPath)
    }
}
