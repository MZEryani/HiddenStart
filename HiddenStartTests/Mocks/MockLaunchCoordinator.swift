import Foundation
import Combine
@testable import HiddenStart

@MainActor
public final class MockLaunchCoordinator: LaunchCoordinating {
    @Published public var remainingDelays: [UUID: Int] = [:]
    public var isRunning: Bool = false
    @Published public var statusSummary: String = "Ready"

    public var remainingDelaysPublisher: AnyPublisher<[UUID: Int], Never> {
        $remainingDelays.eraseToAnyPublisher()
    }

    public var statusSummaryPublisher: AnyPublisher<String, Never> {
        $statusSummary.eraseToAnyPublisher()
    }

    public var startStartupRunCallCount: Int = 0
    public var lastAppsStarted: [ManagedApp] = []
    public var cancelledAppIds: [UUID] = []
    public var cancelAllCallCount: Int = 0

    public init() {}

    public func startStartupRun(for apps: [ManagedApp]) {
        startStartupRunCallCount += 1
        lastAppsStarted = apps
    }

    public func cancelLaunch(for appWithId: UUID) {
        cancelledAppIds.append(appWithId)
        remainingDelays.removeValue(forKey: appWithId)
    }

    public func cancelAll() {
        cancelAllCallCount += 1
        remainingDelays.removeAll()
        isRunning = false
    }
}
