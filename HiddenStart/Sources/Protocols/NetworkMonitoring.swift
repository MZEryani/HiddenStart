import Foundation
import Combine

@MainActor
public protocol NetworkMonitoring: AnyObject, Sendable {
    var isConnected: Bool { get }
    var isConnectedPublisher: AnyPublisher<Bool, Never> { get }
    func startMonitoring()
    func stopMonitoring()
}
