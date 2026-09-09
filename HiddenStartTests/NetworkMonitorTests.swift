import Testing
import Foundation
import Combine
@testable import HiddenStart

@Suite("NetworkMonitor Tests")
@MainActor
struct NetworkMonitorTests {

    @Test("MockNetworkMonitor tracks start and stop monitoring lifecycle")
    func mockNetworkMonitorLifecycle() {
        let mock = MockNetworkMonitor(isConnected: false)
        #expect(!mock.isConnected)
        #expect(mock.startMonitoringCallCount == 0)
        #expect(mock.stopMonitoringCallCount == 0)

        mock.startMonitoring()
        #expect(mock.startMonitoringCallCount == 1)

        mock.simulateNetworkChange(isConnected: true)
        #expect(mock.isConnected)

        mock.stopMonitoring()
        #expect(mock.stopMonitoringCallCount == 1)
    }

    @Test("MockNetworkMonitor publisher publishes updates")
    func mockNetworkMonitorPublisher() async {
        let mock = MockNetworkMonitor(isConnected: false)
        var receivedValues: [Bool] = []
        var cancellables = Set<AnyCancellable>()

        mock.isConnectedPublisher
            .sink { receivedValues.append($0) }
            .store(in: &cancellables)

        #expect(receivedValues == [false])

        mock.simulateNetworkChange(isConnected: true)
        #expect(receivedValues == [false, true])

        mock.simulateNetworkChange(isConnected: false)
        #expect(receivedValues == [false, true, false])
    }

    @Test("System NetworkMonitor can start and stop monitoring without crash")
    func systemNetworkMonitorLifecycle() {
        let monitor = NetworkMonitor()
        monitor.startMonitoring()
        // Calling startMonitoring multiple times should be idempotent
        monitor.startMonitoring()
        monitor.stopMonitoring()
        // Calling stopMonitoring multiple times should be idempotent
        monitor.stopMonitoring()
    }
}
