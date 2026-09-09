import Foundation
import Combine
@testable import HiddenStart

@MainActor
public final class MockNetworkMonitor: ObservableObject, NetworkMonitoring {
    @Published public var isConnected: Bool = false
    public private(set) var startMonitoringCallCount: Int = 0
    public private(set) var stopMonitoringCallCount: Int = 0

    public var isConnectedPublisher: AnyPublisher<Bool, Never> {
        $isConnected.eraseToAnyPublisher()
    }

    public init(isConnected: Bool = false) {
        self.isConnected = isConnected
    }

    public func startMonitoring() {
        startMonitoringCallCount += 1
    }

    public func stopMonitoring() {
        stopMonitoringCallCount += 1
    }

    public func simulateNetworkChange(isConnected: Bool) {
        self.isConnected = isConnected
    }
}
