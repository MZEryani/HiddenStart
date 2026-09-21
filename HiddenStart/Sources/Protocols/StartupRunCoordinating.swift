import Foundation
import Combine

public struct StartupRunState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case running
        case deferredRetry
    }

    public var phase: Phase
    public var remainingDelays: [UUID: Int]
    public var waitingForNetworkAppIds: Set<UUID>
    public var isNetworkConnected: Bool
    public var skippedAppIds: Set<UUID>

    public init(
        phase: Phase = .idle,
        remainingDelays: [UUID: Int] = [:],
        waitingForNetworkAppIds: Set<UUID> = [],
        isNetworkConnected: Bool = true,
        skippedAppIds: Set<UUID> = []
    ) {
        self.phase = phase
        self.remainingDelays = remainingDelays
        self.waitingForNetworkAppIds = waitingForNetworkAppIds
        self.isNetworkConnected = isNetworkConnected
        self.skippedAppIds = skippedAppIds
    }
}

@MainActor
public protocol StartupRunCoordinating: AnyObject, Sendable {
    var state: StartupRunState { get }
    var statePublisher: AnyPublisher<StartupRunState, Never> { get }
    func startStartupRun(for apps: [ManagedApp])
    func launchImmediately(app: ManagedApp) async throws
    func cancelLaunch(for appWithId: UUID)
    func cancelAll()
}

