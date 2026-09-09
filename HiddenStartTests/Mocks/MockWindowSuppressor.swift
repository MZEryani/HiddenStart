import Foundation
@testable import HiddenStart

@MainActor
public final class MockWindowSuppressor: WindowSuppressing {
    public var launchedApps: [ManagedApp] = []
    public var shouldThrowError: Error?
    public var stubbedRunningApp: any RunningAppRepresentable = MockRunningApp()

    public init() {}

    @discardableResult
    public func launch(app: ManagedApp) async throws -> any RunningAppRepresentable {
        if let shouldThrowError {
            throw shouldThrowError
        }
        launchedApps.append(app)
        return stubbedRunningApp
    }
}
