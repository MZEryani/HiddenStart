import AppKit
import Foundation
@testable import HiddenStart

@MainActor
public final class MockWorkspaceManager: WorkspaceManaging {
    public var openedURLs: [URL] = []
    public var configurations: [NSWorkspace.OpenConfiguration] = []
    public var shouldThrowError: Error?
    public var stubbedIcon: NSImage = NSImage()

    public var stubbedRunningApp: any RunningAppRepresentable = MockRunningApp()
    public var stubbedRunningApplications: [any RunningAppRepresentable] = []
    public var applicationURLs: [String: URL] = [:]

    public var runningApplications: [any RunningAppRepresentable] {
        stubbedRunningApplications
    }

    public init() {}

    @discardableResult
    public func openApplication(at url: URL, configuration: NSWorkspace.OpenConfiguration) async throws -> any RunningAppRepresentable {
        if let error = shouldThrowError {
            throw error
        }
        openedURLs.append(url)
        configurations.append(configuration)
        return stubbedRunningApp
    }

    public func icon(forFile fullPath: String) -> NSImage {
        return stubbedIcon
    }

    public func urlForApplication(withBundleIdentifier bundleIdentifier: String) -> URL? {
        applicationURLs[bundleIdentifier]
    }
}
