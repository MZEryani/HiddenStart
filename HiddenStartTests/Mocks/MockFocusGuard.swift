import Foundation
@testable import HiddenStart

@MainActor
public final class MockFocusGuard: FocusGuarding {
    public var guardedApps: [any RunningAppRepresentable] = []
    public var cancelCallCount: Int = 0
    public var isGuarding: Bool = false

    public init() {}

    public func startGuarding(app: any RunningAppRepresentable) {
        isGuarding = true
        guardedApps.append(app)
    }

    public func cancel() {
        isGuarding = false
        cancelCallCount += 1
    }
}
