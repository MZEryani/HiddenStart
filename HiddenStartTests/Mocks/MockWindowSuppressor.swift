import Foundation
@testable import HiddenStart

@MainActor
public final class MockWindowSuppressor: WindowSuppressing {
    public var launchedApps: [ManagedApp] = []
    public var shouldThrowError: Error?
    public var cancelledAppIds: [UUID] = []
    public var cancelAllCallCount: Int = 0

    public init() {}

    public func launch(app: ManagedApp) async throws {
        if let shouldThrowError {
            throw shouldThrowError
        }
        launchedApps.append(app)
    }

    public func cancel(appId: UUID) {
        cancelledAppIds.append(appId)
    }

    public func cancelAll() {
        cancelAllCallCount += 1
    }
}
