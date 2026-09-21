import Foundation
import Combine
@testable import HiddenStart

@MainActor
public final class MockStartupRunCoordinator: StartupRunCoordinating {
    @Published public var state: StartupRunState

    public var statePublisher: AnyPublisher<StartupRunState, Never> {
        $state.eraseToAnyPublisher()
    }

    public var startStartupRunCallCount: Int = 0
    public var lastAppsStarted: [ManagedApp] = []
    public var cancelledAppIds: [UUID] = []
    public var cancelAllCallCount: Int = 0
    public var launchImmediatelyCallCount: Int = 0
    public var lastAppLaunchedImmediately: ManagedApp?
    public var launchImmediatelyError: (any Error)?

    public init(initialState: StartupRunState = StartupRunState()) {
        self.state = initialState
    }

    public func launchImmediately(app: ManagedApp) async throws {
        launchImmediatelyCallCount += 1
        lastAppLaunchedImmediately = app
        if let launchImmediatelyError {
            throw launchImmediatelyError
        }
    }

    public func startStartupRun(for apps: [ManagedApp]) {

        startStartupRunCallCount += 1
        lastAppsStarted = apps
    }

    public func cancelLaunch(for appWithId: UUID) {
        cancelledAppIds.append(appWithId)
        state.remainingDelays.removeValue(forKey: appWithId)
        state.waitingForNetworkAppIds.remove(appWithId)
        state.skippedAppIds.remove(appWithId)
    }

    public func cancelAll() {
        cancelAllCallCount += 1
        state.remainingDelays.removeAll()
        state.waitingForNetworkAppIds.removeAll()
        state.skippedAppIds.removeAll()
        state.phase = .idle
    }
}
