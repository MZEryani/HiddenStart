import Foundation
import ServiceManagement

public enum AutoStartStatus: Equatable, Sendable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound

    public init(serviceStatus: SMAppService.Status) {
        switch serviceStatus {
        case .enabled:
            self = .enabled
        case .requiresApproval:
            self = .requiresApproval
        case .notRegistered:
            self = .notRegistered
        case .notFound:
            self = .notFound
        @unknown default:
            self = .notRegistered
        }
    }
}

public protocol AutoStartServiceRepresentable: AnyObject, Sendable {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

@MainActor
public protocol AutoStartManaging: AnyObject {
    var isEnabled: Bool { get }
    var status: AutoStartStatus { get }
    var requiresApproval: Bool { get }
    var isDenied: Bool { get }
    var hasApprovalIssue: Bool { get }
    func register() throws
    func unregister() throws
    func toggle() throws
    func openSystemSettings()
    func refreshStatus()
}
