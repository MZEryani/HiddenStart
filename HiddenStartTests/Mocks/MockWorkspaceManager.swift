import AppKit
import Foundation
@testable import HiddenStart

@MainActor
public final class MockWorkspaceManager: WorkspaceManaging {
    public var openedURLs: [URL] = []
    public var configurations: [NSWorkspace.OpenConfiguration] = []
    public var shouldThrowError: Error?
    public var stubbedIcon: NSImage = NSImage()

    public init() {}

    public func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) async throws {
        if let error = shouldThrowError {
            throw error
        }
        openedURLs.append(url)
        configurations.append(configuration)
    }

    public func icon(forFile fullPath: String) -> NSImage {
        return stubbedIcon
    }
}
