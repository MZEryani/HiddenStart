import AppKit

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
        try await withCheckedThrowingContinuation { continuation in
            workspace.openApplication(at: url, configuration: configuration) { app, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let app = app {
                    continuation.resume(returning: app)
                } else {
                    continuation.resume(throwing: NSError(domain: "WorkspaceError", code: -1))
                }
            }
        }
    }

    public func icon(forFile fullPath: String) -> NSImage {
        workspace.icon(forFile: fullPath)
    }

    public func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        workspace.urlForApplication(withBundleIdentifier: bundleIdentifier)
    }
}
