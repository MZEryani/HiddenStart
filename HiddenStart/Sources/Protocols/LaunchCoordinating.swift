import Foundation
import Combine

@MainActor
public protocol LaunchCoordinating: AnyObject, Sendable {
    var remainingDelays: [UUID: Int] { get }
    var isRunning: Bool { get }
    var statusSummary: String { get }
    var networkStatus: String { get }
    var remainingDelaysPublisher: AnyPublisher<[UUID: Int], Never> { get }
    var statusSummaryPublisher: AnyPublisher<String, Never> { get }
    var networkStatusPublisher: AnyPublisher<String, Never> { get }
    func startStartupRun(for apps: [ManagedApp])
    func cancelLaunch(for appWithId: UUID)
    func cancelAll()
}
