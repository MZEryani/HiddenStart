import Foundation
@testable import HiddenStart

@MainActor
public final class MockFocusGuard: FocusGuarding {
    public var guardedApps: [any RunningAppRepresentable] = []
    public var cancelledPids: [pid_t] = []
    public var cancelCallCount: Int = 0
    private var guardedPids: Set<pid_t> = []

    public var isGuarding: Bool {
        !guardedPids.isEmpty
    }

    public init() {}

    public func isGuarding(processIdentifier: pid_t) -> Bool {
        guardedPids.contains(processIdentifier)
    }

    public func startGuarding(app: any RunningAppRepresentable) {
        guardedApps.append(app)
        guardedPids.insert(app.processIdentifier)
    }

    public func cancel(processIdentifier: pid_t) {
        cancelledPids.append(processIdentifier)
        guardedPids.remove(processIdentifier)
    }

    public func cancel() {
        guardedPids.removeAll()
        cancelCallCount += 1
    }
}
