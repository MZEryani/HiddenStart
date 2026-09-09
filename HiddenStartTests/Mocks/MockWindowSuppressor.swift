import Foundation
@testable import HiddenStart

@MainActor
public final class MockWindowSuppressor: WindowSuppressing {
    public var launchedApps: [ManagedApp] = []
    public var shouldThrowError: Error?
    public var stubbedRunningApp: any RunningAppRepresentable = MockRunningApp()
    public var cancelledPids: [pid_t] = []
    public var cancelAllCallCount: Int = 0

    public init() {}

    @discardableResult
    public func launch(app: ManagedApp) async throws -> any RunningAppRepresentable {
        if let shouldThrowError {
            throw shouldThrowError
        }
        launchedApps.append(app)
        return stubbedRunningApp
    }

    public func cancel(processIdentifier: pid_t) {
        cancelledPids.append(processIdentifier)
    }

    public func cancelAll() {
        cancelAllCallCount += 1
    }
}
