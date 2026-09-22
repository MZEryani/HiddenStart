import Foundation

public enum NetworkStatusLevel: Equatable, Sendable {
    case connected
    case waiting
    case skippedOffline

    public var displayText: String {
        switch self {
        case .connected: return "Network connected"
        case .waiting: return "Waiting for network..."
        case .skippedOffline: return "Skipped (Offline)"
        }
    }
}

public struct StatusDisplay: Equatable, Sendable {
    public let message: String
    public let networkStatusLevel: NetworkStatusLevel
    public var networkStatusText: String { networkStatusLevel.displayText }
    public let remainingDelays: [UUID: Int]

    public init(
        message: String,
        networkStatusLevel: NetworkStatusLevel,
        remainingDelays: [UUID: Int] = [:]
    ) {
        self.message = message
        self.networkStatusLevel = networkStatusLevel
        self.remainingDelays = remainingDelays
    }
}

public struct StatusPresenter: Sendable {
    public private(set) var currentDisplay: StatusDisplay
    private var previousPhase: StartupRunState.Phase?
    private var isActionMessageActive: Bool

    public init(
        initialMessage: String = "Ready",
        initialLevel: NetworkStatusLevel = .connected
    ) {
        self.currentDisplay = StatusDisplay(
            message: initialMessage,
            networkStatusLevel: initialLevel,
            remainingDelays: [:]
        )
        self.previousPhase = nil
        self.isActionMessageActive = false
    }

    @discardableResult
    public mutating func setActionMessage(_ message: String) -> StatusDisplay {
        isActionMessageActive = true
        currentDisplay = StatusDisplay(
            message: message,
            networkStatusLevel: currentDisplay.networkStatusLevel,
            remainingDelays: currentDisplay.remainingDelays
        )
        return currentDisplay
    }

    @discardableResult
    public mutating func update(state: StartupRunState, apps: [ManagedApp]) -> StatusDisplay {
        let level = Self.deriveNetworkStatusLevel(from: state)
        let coordinatorMessage = Self.deriveCoordinatorMessage(from: state, apps: apps)
        let messageToDisplay: String

        if state.phase != .idle {
            // Startup Run is active: action messages are cleared, coordinator messages take priority
            isActionMessageActive = false
            messageToDisplay = coordinatorMessage ?? "Launching..."
        } else if previousPhase != nil && previousPhase != .idle {
            // A run just completed: action message cleared, returns to coordinator idle message (e.g. "Ready" or "Skipped (Offline)")
            isActionMessageActive = false
            messageToDisplay = coordinatorMessage ?? "Ready"
        } else if isActionMessageActive {
            // Idle pulse: preserve current action message
            messageToDisplay = currentDisplay.message
        } else {
            // Normal idle update
            messageToDisplay = coordinatorMessage ?? "Ready"
        }

        previousPhase = state.phase
        currentDisplay = StatusDisplay(
            message: messageToDisplay,
            networkStatusLevel: level,
            remainingDelays: state.remainingDelays
        )
        return currentDisplay
    }

    public static func deriveNetworkStatusLevel(from state: StartupRunState) -> NetworkStatusLevel {
        if state.phase == .deferredRetry || !state.skippedAppIds.isEmpty {
            return .skippedOffline
        } else if !state.isNetworkConnected {
            return .waiting
        } else {
            return .connected
        }
    }

    public static func deriveCoordinatorMessage(from state: StartupRunState, apps: [ManagedApp]) -> String? {
        if !state.remainingDelays.isEmpty {
            let sorted = state.remainingDelays.compactMap { (id, remaining) -> (appName: String, delay: Int)? in
                guard let app = apps.first(where: { $0.id == id }) else { return nil }
                return (appName: app.name, delay: remaining)
            }.sorted { $0.delay < $1.delay }
            if !sorted.isEmpty {
                return sorted.map { "\($0.appName) in \($0.delay)s" }.joined(separator: ", ")
            }
        }

        if !state.waitingForNetworkAppIds.isEmpty {
            return NetworkStatusLevel.waiting.displayText
        }

        if state.phase == .deferredRetry || (!state.skippedAppIds.isEmpty && state.phase == .idle) {
            return NetworkStatusLevel.skippedOffline.displayText
        }

        if state.phase == .running {
            return "Launching..."
        }

        if state.phase == .idle {
            return "Ready"
        }

        return nil
    }
}
